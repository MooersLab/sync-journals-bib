# Makefile for sync-journals-bib
# Author: Blaine Mooers <blaine-mooers@ou.edu>
#
# Common targets:
#   make          # byte-compile and run tests
#   make test     # run ERT tests in batch mode
#   make compile  # byte-compile the library
#   make info     # build the info manual from the texi source
#   make install-info  # install the info file into INFODIR
#   make lint     # byte-compile with warnings as errors
#   make clean    # remove generated files

EMACS       ?= emacs
EMACSFLAGS  ?= -Q --batch
MAKEINFO    ?= makeinfo
INSTALL_INFO ?= install-info

PACKAGE      = sync-journals-bib
SRC          = $(PACKAGE).el
TEST         = test/$(PACKAGE)-test.el
TEXI         = $(PACKAGE).texi
INFO         = $(PACKAGE).info

PREFIX      ?= /usr/local
INFODIR     ?= $(PREFIX)/share/info

LOAD_PATH    = -L . -L test

.PHONY: all test compile info install-info uninstall-info lint clean help

all: compile test

help:
	@echo "Targets:"
	@echo "  make test          run ERT tests in batch mode"
	@echo "  make compile       byte-compile the library"
	@echo "  make info          build $(INFO) from $(TEXI)"
	@echo "  make install-info  install $(INFO) into \$$INFODIR"
	@echo "  make uninstall-info remove $(INFO) from \$$INFODIR"
	@echo "  make lint          byte-compile with warnings as errors"
	@echo "  make clean         remove generated files"

test:
	$(EMACS) $(EMACSFLAGS) $(LOAD_PATH) \
	  -l ert \
	  -l $(TEST) \
	  -f ert-run-tests-batch-and-exit

compile: $(SRC)
	$(EMACS) $(EMACSFLAGS) $(LOAD_PATH) \
	  --eval "(setq byte-compile-error-on-warn nil)" \
	  -f batch-byte-compile $(SRC)

lint: $(SRC)
	$(EMACS) $(EMACSFLAGS) $(LOAD_PATH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(SRC)

info: $(INFO)

$(INFO): $(TEXI)
	$(MAKEINFO) --no-split $(TEXI) -o $(INFO)

install-info: $(INFO)
	install -d $(DESTDIR)$(INFODIR)
	install -m 0644 $(INFO) $(DESTDIR)$(INFODIR)/$(INFO)
	$(INSTALL_INFO) --info-dir=$(DESTDIR)$(INFODIR) $(DESTDIR)$(INFODIR)/$(INFO)

uninstall-info:
	-$(INSTALL_INFO) --remove --info-dir=$(DESTDIR)$(INFODIR) $(DESTDIR)$(INFODIR)/$(INFO)
	-rm -f $(DESTDIR)$(INFODIR)/$(INFO)

clean:
	rm -f *.elc test/*.elc $(INFO)
