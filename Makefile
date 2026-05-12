# https://www.gnu.org/software/make/manual/make.html

DOCKER_IMAGE ?= fritzgrabo.github.io

sources-build-artefacts-pattern := source/posts/index.org* source/posts/rss.org*
sources-build-artefacts := $(wildcard $(sources-build-artefacts-pattern))
sources := $(filter-out $(sources-build-artefacts), $(shell find source -type f))

emacs-load-options := --load .emacs --load config.el --load build.el

.PHONY: all
all: docs

docs: build.el $(sources)
	@docker run --rm -it -v "$(CURDIR)":/workspace -w /workspace $(DOCKER_IMAGE) \
	  emacs -Q $(emacs-load-options) --funcall build

.PHONY: serve
serve:
	@docker run --rm -it -p 80:8088 -v "$(CURDIR)":/workspace -w /workspace $(DOCKER_IMAGE) \
	  emacs -Q $(emacs-load-options) --funcall serve

.PHONY: clean
clean:
	@rm -rf .timestamps
	@rm -rf $(sources-build-artefacts)
	@rm -rf docs

.PHONY: cleaner
cleaner: clean
	@rm -rf .packages
