# https://www.gnu.org/software/make/manual/make.html

EMACS ?= emacs
SITE_CONFIG_FILE ?= config.el

sources-build-artefacts-pattern := source/posts/index.org* source/posts/rss.org*
sources-build-artefacts := $(wildcard $(sources-build-artefacts-pattern))
sources := $(filter-out $(sources-build-artefacts), $(shell find source -type f))

emacs-scripts := .emacs $(SITE_CONFIG_FILE) build.el
emacs-load-options := $(foreach emacs-script,$(emacs-scripts), --load $(emacs-script))

define emacs-call-function
  $(shell $(EMACS) -Q $(emacs-load-options) --funcall $1)
endef

.PHONY: all
all: docs

docs: build.el $(sources)
	@$(call emacs-call-function,build)

.PHONY: serve
serve:
	@$(call emacs-call-function,serve)

.PHONY: clean
clean:
	@rm -rf .timestamps
	@rm -rf $(sources-build-artefacts)
	@rm -rf docs

.PHONY: cleaner
cleaner: clean
	@rm -rf .packages
