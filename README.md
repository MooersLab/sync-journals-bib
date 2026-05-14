# sync-journals-bib

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1%2B-purple.svg)](https://www.gnu.org/software/emacs/)
[![Made with Org](https://img.shields.io/badge/Made_with-Emacs_Lisp-7F5AB6.svg)](https://www.gnu.org/software/emacs/manual/html_node/elisp/index.html)

An Emacs Lisp package that reconciles the journal field values of a master BibTeX file with the abbreviation table used by org-ref. It writes ready-to-paste `add-to-list` forms for the journals that are missing and consults the Chemical Abstracts Service Source Index (CASSI) to fill in the official abbreviations.

## Table of contents

- [Motivation](#motivation)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Manual install](#manual-install)
  - [use-package](#use-package)
  - [straight.el](#straightel)
- [Configuration](#configuration)
- [Usage tutorial](#usage-tutorial)
  - [First run](#first-run)
  - [Offline mode](#offline-mode)
  - [Programmatic use](#programmatic-use)
- [Commands](#commands)
- [Customizable variables](#customizable-variables)
- [How it works](#how-it-works)
- [Building the info manual](#building-the-info-manual)
- [Running the test suite](#running-the-test-suite)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Citation](#citation)
- [License](#license)
- [Author](#author)

## Motivation

Org-ref ships with an abbreviation table named `org-ref-bibtex-journal-abbreviations` that maps full journal names to their CAS-style short forms. The table is not exhaustive. Authors who maintain a large `global.bib` file routinely cite journals that the table does not know, and the missing entries make automatic abbreviation impossible. `sync-journals-bib` closes the gap by harvesting the unique journal names from a BibTeX file, comparing them against the table, and writing the `add-to-list` forms needed to grow the table.

## Features

- Reads `journal` and `journaltitle` fields from any BibTeX file
- Deduplicates and normalizes journal names with a case-insensitive comparator
- Generates `add-to-list` forms for missing journals
- Scrapes a CASSI search result page and fills the official abbreviation slot when a match is found
- Exposes a single interactive command and a programmatic helper
- Ships with an ERT test suite, a Texinfo manual, and a Makefile

## Requirements

- GNU Emacs 27.1 or newer
- `org-ref` 3.0 or newer (only the variable `org-ref-bibtex-journal-abbreviations` is touched)
- Network access for the CASSI lookup (optional)
- `makeinfo` if you want to build the info manual

## Installation

### Manual install

```bash
git clone https://github.com/MooersLab/sync-journals-bib.git ~/src/sync-journals-bib
```

Then add the following lines to your init file.

```elisp
(add-to-list 'load-path "~/src/sync-journals-bib")
(require 'sync-journals-bib)
```

### use-package

```elisp
(use-package sync-journals-bib
  :load-path "~/src/sync-journals-bib"
  :commands (sync-journals-bib-sync
             sync-journals-bib-list-missing)
  :custom
  (sync-journals-bib-file (expand-file-name "~/Documents/global.bib")))
```

### straight.el

```elisp
(straight-use-package
 '(sync-journals-bib
   :type git
   :host github
   :repo "MooersLab/sync-journals-bib"))
```

## Configuration

The defaults already point at `~/Documents/global.bib`, so for most users no configuration is required. To change the BibTeX file or the CASSI URL, set the variables before calling the command.

```elisp
(setq sync-journals-bib-file "~/projects/manuscript/refs.bib")
(setq sync-journals-bib-cassi-url
      "https://cassi.cas.org/publication.jsp?P=YOUR_QUERY_TOKEN")
```

## Usage tutorial

### First run

1. Open Emacs.
2. Load `org-ref` so that `org-ref-bibtex-journal-abbreviations` is bound.
3. Run `M-x sync-journals-bib-sync`.
4. A buffer named `*sync-journals-bib*` opens with one `add-to-list` form per missing journal. The third slot holds the CAS abbreviation when the CASSI page reported a match and `FILL ME IN` otherwise.
5. Copy the forms that look correct into your init file, evaluate the region, and the org-ref table grows.

A finished form looks like this.

```elisp
(add-to-list 'org-ref-bibtex-journal-abbreviations
             '("JCTC" "Journal of Chemical Theory and Computation" "J. Chem. Theory Comput. "))
```

### Offline mode

Pass a prefix argument to skip the network step.

```text
C-u M-x sync-journals-bib-sync
```

In offline mode every emitted form has `FILL ME IN` in the third slot, and you fill the abbreviations by hand.

### Programmatic use

The helper `sync-journals-bib-list-missing` returns the list of missing journal names as plain Lisp data. Use it from a hook, a build script, or a batch job.

```elisp
(let ((missing (sync-journals-bib-list-missing)))
  (when missing
    (message "Missing %d journal(s)" (length missing))))
```

## Commands

| Command                          | Description                                                                          |
|----------------------------------|--------------------------------------------------------------------------------------|
| `sync-journals-bib-sync`         | Build a buffer of `add-to-list` forms for journals missing from org-ref              |
| `sync-journals-bib-list-missing` | Return the list of missing journals without touching the buffer or the network       |

## Customizable variables

| Variable                          | Default                                  | Purpose                                   |
|-----------------------------------|------------------------------------------|-------------------------------------------|
| `sync-journals-bib-file`          | `~/Documents/global.bib`                 | Path to the master BibTeX file            |
| `sync-journals-bib-cassi-url`     | CASSI search result URL                  | URL used for the abbreviation lookup      |
| `sync-journals-bib-buffer-name`   | `*sync-journals-bib*`                    | Name of the output buffer                 |
| `sync-journals-bib-fetch-timeout` | `30`                                     | Seconds to wait for the CASSI page        |

Open the customization group with `M-x customize-group RET sync-journals-bib RET`.

## How it works

The pipeline runs in four steps.

1. The BibTeX file is parsed with a regular expression that captures any `journal` or `journaltitle` field. Surrounding braces and quotes are stripped, internal whitespace is collapsed, and duplicates are removed with a hash table.
2. The full-name slot of every triple in `org-ref-bibtex-journal-abbreviations` is normalized with the same comparator. Names that are already known drop out.
3. The remaining names are passed to a snippet builder that wraps each one in an `add-to-list` form. A short key is invented from the initials of the full name.
4. When the CASSI URL is reachable, the HTML is parsed with `libxml-parse-html-region` and a regex fallback. Each row of the CASSI table contributes one (title, abbreviation) pair. Matching pairs fill the third slot of the snippet.

## Building the info manual

```bash
make info
```

This produces `sync-journals-bib.info`. Install it system-wide with

```bash
sudo make install-info INFODIR=/usr/local/share/info
```

After installation, open it in Emacs with `C-h i d m Sync Journals Bib RET`.

## Running the test suite

```bash
make test
```

The Makefile launches Emacs in batch mode, loads the library and the ERT test file, and runs every `ert-deftest`. The fixtures under `test/fixtures` exercise the BibTeX parser, the CASSI HTML parser, the snippet builder, and the full pipeline against a mocked `org-ref-bibtex-journal-abbreviations`.

To run a single test by name, use the following pattern.

```bash
emacs -Q --batch -L . -L test \
  -l test/sync-journals-bib-test.el \
  --eval '(ert-run-tests-batch-and-exit "sync-journals-bib-test-normalize-strips-punctuation")'
```

## Troubleshooting

If the output buffer is empty even though the BibTeX file contains many journals, check that `org-ref-bibtex-journal-abbreviations` is bound. Load `org-ref` first.

If the CASSI page yields zero rows, the URL token may have expired. Regenerate the URL at [cassi.cas.org](https://cassi.cas.org) and update `sync-journals-bib-cassi-url`.

If the BibTeX file uses `crossref` or `@string` macros, the simple regex parser may miss some fields. File an issue with a minimal example.

## Contributing

Bug reports, pull requests, and feature suggestions are welcome. Please run `make test` before submitting a pull request. Follow the package prefix convention. Public symbols use a single hyphen after the prefix, and internal symbols use a double hyphen.

## Citation

If `sync-journals-bib` aids your work, please cite the repository.

```bibtex
@misc{MooersBlaine2026SyncJournalsBib,
  author       = {Mooers, Blaine},
  title        = {sync-journals-bib: Reconcile BibTeX journal names with org-ref and CASSI},
  year         = {2026},
  howpublished = {\url{https://github.com/MooersLab/sync-journals-bib}},
  note         = {Emacs Lisp package},
  doi          = {10.0000/example.0000}
}
```

## License

`sync-journals-bib` is released under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE) for the full text.

## Author

Blaine Mooers
Department of Biochemistry and Physiology
University of Oklahoma Health Campus
Oklahoma City, Oklahoma, United States 73104
blaine-mooers@ou.edu
