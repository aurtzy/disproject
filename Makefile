EMACS ?= emacs

srcdir ?= $(shell dirname "$(realpath $(lastword $(MAKEFILE_LIST)))")

SHELL = /bin/sh

PKG = disproject

EMACS_ARGS = --quick --directory $(srcdir)

testdir = $(srcdir)/test

run:
	$(EMACS) $(EMACS_ARGS) \
		--load $(srcdir)/$(PKG)

test:
	$(EMACS) $(EMACS_ARGS) --batch \
		--directory $(testdir) \
		--load $(testdir)/$(PKG)-test \
		--funcall ert-run-tests-batch-and-exit

.PHONY: build clean run test
