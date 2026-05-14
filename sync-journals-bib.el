;;; sync-journals-bib.el --- Sync BibTeX journal names with org-ref and CASSI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers and University of Oklahoma Board of Regents

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Created: 2026-05-13
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org-ref "3.0"))
;; Keywords: bib, tex, tools, bibtex, org-ref
;; URL: https://github.com/MooersLab/sync-journals-bib
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; sync-journals-bib reconciles the journal field values in a master
;; BibTeX file with the abbreviation table used by org-ref. It scans
;; the BibTeX file for unique journal names, compares them against the
;; full-name slot of every triple in
;; `org-ref-bibtex-journal-abbreviations', and writes one
;; `add-to-list' form per missing journal into a dedicated buffer. The
;; package also consults a Chemical Abstracts Service Source Index
;; (CASSI) URL and tries to fill the abbreviation slot of each
;; generated form with the official CAS abbreviation when it finds a
;; match.
;;
;; Basic use:
;;
;;   (require 'sync-journals-bib)
;;   M-x sync-journals-bib-sync
;;
;; Customize `sync-journals-bib-file' to point at your global BibTeX
;; file. Customize `sync-journals-bib-cassi-url' to point at a CASSI
;; result page. Both variables ship with sensible defaults.

;;; Code:

(require 'cl-lib)
(require 'url)
(require 'subr-x)
(require 'dom nil 'noerror)

(defgroup sync-journals-bib nil
  "Reconcile BibTeX journal names with org-ref and CASSI."
  :group 'bib
  :prefix "sync-journals-bib-")

(defcustom sync-journals-bib-file
  (expand-file-name "~/Documents/global.bib")
  "Path to the master BibTeX file."
  :type 'file
  :group 'sync-journals-bib)

(defcustom sync-journals-bib-cassi-url
  "https://cassi.cas.org/publication.jsp?P=eCQtRPJo9AQyz133K_ll3zLPXfcr-WXfT440DfGTqecyz133K_ll3zLPXfcr-WXfDImI6aj6gdQyz133K_ll3zLPXfcr-WXfFKSiLGXbG-3fzKcm8PwFCg"
  "URL of a CASSI search result page used to look up CAS abbreviations."
  :type 'string
  :group 'sync-journals-bib)

(defcustom sync-journals-bib-buffer-name "*sync-journals-bib*"
  "Name of the output buffer that receives the generated forms."
  :type 'string
  :group 'sync-journals-bib)

(defcustom sync-journals-bib-fetch-timeout 30
  "Number of seconds to wait for the CASSI page to download."
  :type 'integer
  :group 'sync-journals-bib)


;;;; ---------------------------------------------------------------------
;;;; 1. Harvest unique journal names from a BibTeX file
;;;; ---------------------------------------------------------------------

(defun sync-journals-bib--journals-in-file (bibfile)
  "Return a sorted list of unique journal names found in BIBFILE.
The function scans for `journal' or `journaltitle' fields, strips
braces or quotes, and collapses internal whitespace."
  (unless (file-readable-p bibfile)
    (error "Cannot read BibTeX file %s" bibfile))
  (let ((seen (make-hash-table :test #'equal))
        (case-fold-search t))
    (with-temp-buffer
      (insert-file-contents bibfile)
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*journal\\(?:title\\)?[ \t]*=[ \t]*\\({\\|\"\\)\\([^{}\"\n]+\\)\\(?:}\\|\"\\)"
              nil t)
        (let* ((raw (match-string 2))
               (clean (string-trim
                       (replace-regexp-in-string "[ \t\n\r]+" " " raw))))
          (when (and clean (not (string-empty-p clean)))
            (puthash clean t seen)))))
    (sort (hash-table-keys seen) #'string<)))


;;;; ---------------------------------------------------------------------
;;;; 2. Compare against org-ref-bibtex-journal-abbreviations
;;;; ---------------------------------------------------------------------

(defun sync-journals-bib--normalize (s)
  "Normalize string S for case-insensitive journal comparison."
  (downcase
   (replace-regexp-in-string
    "[[:space:]]+" " "
    (replace-regexp-in-string "[.,]" "" (or s "")))))

(defun sync-journals-bib--known-journals ()
  "Return the list of full journal names known to org-ref."
  (unless (boundp 'org-ref-bibtex-journal-abbreviations)
    (error "org-ref-bibtex-journal-abbreviations is not loaded"))
  (mapcar (lambda (entry) (nth 1 entry))
          (symbol-value 'org-ref-bibtex-journal-abbreviations)))

(defun sync-journals-bib--missing-journals (&optional bibfile)
  "Return journal names in BIBFILE that are absent from org-ref.
BIBFILE defaults to `sync-journals-bib-file'."
  (let* ((known (mapcar #'sync-journals-bib--normalize
                        (sync-journals-bib--known-journals)))
         (found (sync-journals-bib--journals-in-file
                 (or bibfile sync-journals-bib-file))))
    (cl-remove-if
     (lambda (j) (member (sync-journals-bib--normalize j) known))
     found)))


;;;; ---------------------------------------------------------------------
;;;; 3. Build add-to-list snippets
;;;; ---------------------------------------------------------------------

(defun sync-journals-bib--guess-abbrev-key (full-name)
  "Return a short uppercase key built from the initials of FULL-NAME."
  (let ((words (split-string (or full-name "") "[^[:alnum:]]+" t)))
    (if (null words)
        ""
      (mapconcat (lambda (w) (upcase (substring w 0 1))) words ""))))

(defun sync-journals-bib--build-snippet (full-name &optional cassi-abbrev key)
  "Return an `add-to-list' form for FULL-NAME.
CASSI-ABBREV is inserted in the third slot when non-nil. KEY is
the short identifier and defaults to the initials of FULL-NAME."
  (format
   "(add-to-list 'org-ref-bibtex-journal-abbreviations\n             '(\"%s\" \"%s\" \"%s\"))"
   (or key (sync-journals-bib--guess-abbrev-key full-name))
   full-name
   (or cassi-abbrev "FILL ME IN")))


;;;; ---------------------------------------------------------------------
;;;; 4. Scrape CASSI for an official abbreviation
;;;; ---------------------------------------------------------------------

(defun sync-journals-bib--fetch-page (url)
  "Return the body of URL as a raw HTML string."
  (with-current-buffer
      (url-retrieve-synchronously
       url t t sync-journals-bib-fetch-timeout)
    (goto-char (point-min))
    (re-search-forward "\n\n" nil t)
    (prog1 (buffer-substring-no-properties (point) (point-max))
      (kill-buffer (current-buffer)))))

(defun sync-journals-bib--parse-cassi-html (html)
  "Return an alist of (FULL-TITLE . CAS-ABBREV) pulled from HTML.
The function tries `libxml-parse-html-region' first and falls
back to a regex sweep when libxml is unavailable."
  (let (rows)
    (cond
     ((and (fboundp 'libxml-parse-html-region)
           (fboundp 'dom-by-tag))
      (with-temp-buffer
        (insert html)
        (let* ((dom (libxml-parse-html-region (point-min) (point-max)))
               (cells (dom-by-tag dom 'td))
               (texts
                (cl-loop for td in cells
                         for txt = (string-trim (dom-texts td))
                         when (and txt (not (string-empty-p txt)))
                         collect txt)))
          (cl-loop for (title abbrev) on texts by #'cddr
                   when (and title abbrev)
                   do (push (cons title abbrev) rows)))))
     (t
      (let ((pos 0))
        (while (string-match
                "<td[^>]*>\\([^<]+\\)</td>[[:space:]]*<td[^>]*>\\([^<]+\\)</td>"
                html pos)
          (push (cons (string-trim (match-string 1 html))
                      (string-trim (match-string 2 html)))
                rows)
          (setq pos (match-end 0))))))
    (nreverse rows)))

(defun sync-journals-bib--cassi-lookup (journal cassi-rows)
  "Return the CASSI abbreviation that best matches JOURNAL.
CASSI-ROWS is an alist returned by `sync-journals-bib--parse-cassi-html'."
  (let ((target (sync-journals-bib--normalize journal)))
    (cdr (cl-find-if
          (lambda (row)
            (string= target (sync-journals-bib--normalize (car row))))
          cassi-rows))))


;;;; ---------------------------------------------------------------------
;;;; 5. Public commands
;;;; ---------------------------------------------------------------------

;;;###autoload
(defun sync-journals-bib-list-missing ()
  "Return a list of journals in `sync-journals-bib-file' missing from org-ref.
Useful as a programmatic entry point, for example from a hook or
a build script."
  (sync-journals-bib--missing-journals))

;;;###autoload
(defun sync-journals-bib-sync (&optional skip-cassi)
  "Generate `add-to-list' forms for journals missing from org-ref.
With prefix argument SKIP-CASSI, do not attempt the network
lookup. Forms are written into the buffer named by
`sync-journals-bib-buffer-name'."
  (interactive "P")
  (let* ((missing (sync-journals-bib--missing-journals))
         (cassi-rows
          (unless skip-cassi
            (let ((html (ignore-errors
                          (sync-journals-bib--fetch-page
                           sync-journals-bib-cassi-url))))
              (and html (sync-journals-bib--parse-cassi-html html)))))
         (buf (get-buffer-create sync-journals-bib-buffer-name)))
    (with-current-buffer buf
      (erase-buffer)
      (emacs-lisp-mode)
      (insert ";; Journals in " sync-journals-bib-file " that are not yet\n")
      (insert ";; in org-ref-bibtex-journal-abbreviations.\n")
      (insert (format ";; CASSI rows parsed: %d\n\n"
                      (length cassi-rows)))
      (if (null missing)
          (insert ";; Nothing missing. The lists agree.\n")
        (dolist (j missing)
          (let ((cas (and cassi-rows
                          (sync-journals-bib--cassi-lookup j cassi-rows))))
            (insert (sync-journals-bib--build-snippet j cas))
            (insert "\n\n")))))
    (pop-to-buffer buf)
    missing))

(provide 'sync-journals-bib)

;;; sync-journals-bib.el ends here
