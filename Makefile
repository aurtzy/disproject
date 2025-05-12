SHELL = /bin/sh

SRCDIR = $(shell dirname "$(realpath $(lastword $(MAKEFILE_LIST)))")

DOCDIR = $(SRCDIR)/doc

TESTDIR = $(SRCDIR)/test

PKG = disproject

EMACS ?= emacs

EMACS_Q = $(EMACS) --quick

EMACS_BATCH = $(EMACS_Q) --batch

.PHONY: all clean clean-doc doc info run texi

all: doc

clean:
	rm *.info

# Run Emacs for interactive testing.

run:
	$(EMACS_Q) --load $(SRCDIR)/$(PKG)

# Build documentation.

MAKEINFO ?= makeinfo

doc: info

texi:
	$(EMACS_BATCH) $(DOCDIR)/$(PKG).org \
		--load ox-texinfo \
		--funcall org-texinfo-export-to-texinfo

info: texi
	$(MAKEINFO) $(DOCDIR)/$(PKG).texi

# Tests.

check:
	$(EMACS_BATCH) \
		--directory $(SRCDIR) \
		--load $(TESTDIR)/$(PKG)-test \
		--funcall ert-run-tests-batch-and-exit
