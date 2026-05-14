;;; sync-journals-bib-test.el --- ERT tests for sync-journals-bib -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers
;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run interactively with `M-x ert RET t RET' after loading this
;; file, or in batch mode through the Makefile target `test'.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Allow loading the library when this test file lives in test/.
(add-to-list 'load-path
             (expand-file-name ".."
                               (file-name-directory
                                (or load-file-name buffer-file-name))))
(require 'sync-journals-bib)

;; Declare the org-ref variable as special at the top level so that
;; `let' over it produces a dynamic binding visible to `boundp' and
;; `symbol-value' inside the library. Without this declaration, the
;; lexical-binding mode of this file would create a lexical binding
;; that the library cannot see.
(defvar org-ref-bibtex-journal-abbreviations nil
  "Stub binding used by the test suite.")

(defvar sync-journals-bib-test--fixtures-dir
  (expand-file-name "fixtures"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Directory holding sample bib and HTML fixtures.")

(defun sync-journals-bib-test--fixture (name)
  "Return the absolute path of fixture NAME."
  (expand-file-name name sync-journals-bib-test--fixtures-dir))

(defmacro sync-journals-bib-test--with-mock-org-ref (table &rest body)
  "Bind `org-ref-bibtex-journal-abbreviations' to TABLE and run BODY."
  (declare (indent 1))
  `(let ((org-ref-bibtex-journal-abbreviations ,table))
     ,@body))


;;;; ---------------------------------------------------------------------
;;;; Normalization
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-normalize-downcases ()
  (should (equal (sync-journals-bib--normalize "Journal Of Chemistry")
                 "journal of chemistry")))

(ert-deftest sync-journals-bib-test-normalize-strips-punctuation ()
  (should (equal (sync-journals-bib--normalize "J. Chem. Theory Comput.")
                 "j chem theory comput")))

(ert-deftest sync-journals-bib-test-normalize-collapses-whitespace ()
  (should (equal (sync-journals-bib--normalize "Journal   of    Chemistry")
                 "journal of chemistry")))

(ert-deftest sync-journals-bib-test-normalize-nil-input ()
  (should (equal (sync-journals-bib--normalize nil) "")))


;;;; ---------------------------------------------------------------------
;;;; Key guessing
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-guess-abbrev-key-basic ()
  (should (equal (sync-journals-bib--guess-abbrev-key
                  "Journal of Chemical Theory and Computation")
                 "JOCTAC")))

(ert-deftest sync-journals-bib-test-guess-abbrev-key-with-punctuation ()
  (should (equal (sync-journals-bib--guess-abbrev-key
                  "Proc. Natl. Acad. Sci. U.S.A.")
                 "PNASUSA")))

(ert-deftest sync-journals-bib-test-guess-abbrev-key-empty ()
  (should (equal (sync-journals-bib--guess-abbrev-key "") ""))
  (should (equal (sync-journals-bib--guess-abbrev-key nil) "")))


;;;; ---------------------------------------------------------------------
;;;; Snippet construction
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-build-snippet-with-cassi ()
  (let ((s (sync-journals-bib--build-snippet
            "Journal of Chemical Theory and Computation"
            "J. Chem. Theory Comput. "
            "JCTC")))
    (should (string-match-p "\"JCTC\"" s))
    (should (string-match-p "\"Journal of Chemical Theory and Computation\"" s))
    (should (string-match-p "\"J\\. Chem\\. Theory Comput\\. \"" s))))

(ert-deftest sync-journals-bib-test-build-snippet-without-cassi ()
  (let ((s (sync-journals-bib--build-snippet "Acta Crystallographica")))
    (should (string-match-p "\"AC\"" s))
    (should (string-match-p "FILL ME IN" s))))

(ert-deftest sync-journals-bib-test-build-snippet-shape ()
  ;; The snippet should parse back into a quoted form that begins
  ;; with `add-to-list'.
  (let* ((s (sync-journals-bib--build-snippet "Nature"))
         (form (car (read-from-string s))))
    (should (eq (car form) 'add-to-list))
    (should (equal (cadr form) '(quote org-ref-bibtex-journal-abbreviations)))))


;;;; ---------------------------------------------------------------------
;;;; Bib parsing
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-journals-in-file-basic ()
  (let ((result (sync-journals-bib--journals-in-file
                 (sync-journals-bib-test--fixture "sample.bib"))))
    (should (member "Journal of Chemical Theory and Computation" result))
    (should (member "Nature" result))
    (should (member "Acta Crystallographica Section D" result))))

(ert-deftest sync-journals-bib-test-journals-in-file-deduplicates ()
  ;; Two entries cite Nature, but the unique list has only one.
  (let ((result (sync-journals-bib--journals-in-file
                 (sync-journals-bib-test--fixture "sample.bib"))))
    (should (= 1 (cl-count "Nature" result :test #'equal)))))

(ert-deftest sync-journals-bib-test-journals-in-file-supports-journaltitle ()
  (let ((result (sync-journals-bib--journals-in-file
                 (sync-journals-bib-test--fixture "sample.bib"))))
    (should (member "Cell" result))))

(ert-deftest sync-journals-bib-test-journals-in-file-quoted ()
  ;; The library should read a journal wrapped in double quotes.
  (let ((result (sync-journals-bib--journals-in-file
                 (sync-journals-bib-test--fixture "sample.bib"))))
    (should (member "Science" result))))

(ert-deftest sync-journals-bib-test-journals-in-file-missing-file ()
  (should-error
   (sync-journals-bib--journals-in-file "/does/not/exist.bib")))


;;;; ---------------------------------------------------------------------
;;;; Missing-journal pipeline
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-missing-journals-returns-only-new ()
  (sync-journals-bib-test--with-mock-org-ref
      '(("Nature" "Nature" "Nature ")
        ("Cell" "Cell" "Cell "))
    (let* ((sync-journals-bib-file
            (sync-journals-bib-test--fixture "sample.bib"))
           (missing (sync-journals-bib--missing-journals)))
      (should-not (member "Nature" missing))
      (should-not (member "Cell" missing))
      (should (member "Journal of Chemical Theory and Computation"
                      missing)))))

(ert-deftest sync-journals-bib-test-missing-journals-case-insensitive ()
  (sync-journals-bib-test--with-mock-org-ref
      '(("NAT" "nature" "Nature "))
    (let* ((sync-journals-bib-file
            (sync-journals-bib-test--fixture "sample.bib"))
           (missing (sync-journals-bib--missing-journals)))
      (should-not (member "Nature" missing)))))


;;;; ---------------------------------------------------------------------
;;;; CASSI HTML parsing
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-parse-cassi-html-extracts-rows ()
  (let* ((html
          (with-temp-buffer
            (insert-file-contents
             (sync-journals-bib-test--fixture "cassi-sample.html"))
            (buffer-string)))
         (rows (sync-journals-bib--parse-cassi-html html)))
    (should (> (length rows) 0))
    (should (cl-some (lambda (r)
                       (string= "Nature" (car r)))
                     rows))))

(ert-deftest sync-journals-bib-test-cassi-lookup-hits ()
  (let ((rows '(("Journal of Chemical Theory and Computation"
                 . "J. Chem. Theory Comput.")
                ("Nature" . "Nature"))))
    (should (equal (sync-journals-bib--cassi-lookup
                    "Journal of Chemical Theory and Computation" rows)
                   "J. Chem. Theory Comput."))))

(ert-deftest sync-journals-bib-test-cassi-lookup-misses ()
  (let ((rows '(("Nature" . "Nature"))))
    (should (null (sync-journals-bib--cassi-lookup
                   "Journal of Made Up Science" rows)))))


;;;; ---------------------------------------------------------------------
;;;; End-to-end (mocked CASSI and bib fixture)
;;;; ---------------------------------------------------------------------

(ert-deftest sync-journals-bib-test-sync-writes-buffer ()
  (sync-journals-bib-test--with-mock-org-ref
      '(("Nature" "Nature" "Nature "))
    (let* ((sync-journals-bib-file
            (sync-journals-bib-test--fixture "sample.bib"))
           (sync-journals-bib-buffer-name
            "*sync-journals-bib-test*"))
      (cl-letf (((symbol-function 'sync-journals-bib--fetch-page)
                 (lambda (_url) "")))
        (sync-journals-bib-sync t))
      (with-current-buffer sync-journals-bib-buffer-name
        (let ((text (buffer-string)))
          (should (string-match-p "add-to-list" text))
          (should (string-match-p
                   "Journal of Chemical Theory and Computation"
                   text)))))))

(ert-deftest sync-journals-bib-test-sync-empty-when-everything-known ()
  (sync-journals-bib-test--with-mock-org-ref
      '(("N" "Nature" "Nature ")
        ("C" "Cell" "Cell ")
        ("S" "Science" "Sci. ")
        ("JCTC" "Journal of Chemical Theory and Computation"
         "J. Chem. Theory Comput. ")
        ("ACD" "Acta Crystallographica Section D"
         "Acta Crystallogr. D "))
    (let* ((sync-journals-bib-file
            (sync-journals-bib-test--fixture "sample.bib"))
           (sync-journals-bib-buffer-name
            "*sync-journals-bib-test-empty*"))
      (sync-journals-bib-sync t)
      (with-current-buffer sync-journals-bib-buffer-name
        (should (string-match-p "Nothing missing"
                                (buffer-string)))))))

(provide 'sync-journals-bib-test)

;;; sync-journals-bib-test.el ends here
