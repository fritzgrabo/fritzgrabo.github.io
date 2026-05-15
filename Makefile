# https://www.gnu.org/software/make/manual/make.html

DOCKER_IMAGE ?= fritzgrabo.github.io

sources-build-artefacts-pattern := source/posts/index.org* source/posts/rss.org*
sources-build-artefacts := $(wildcard $(sources-build-artefacts-pattern))
sources := $(filter-out $(sources-build-artefacts), $(shell find source -type f))

emacs-load-options := --load .emacs --load config.el --load build.el

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: docs ## Build docs (alias)

docs: build.el $(sources) ## Build the site
	@docker run --rm -it -v "$(CURDIR)":/workspace -w /workspace $(DOCKER_IMAGE) \
	  emacs -Q $(emacs-load-options) --funcall build

.PHONY: serve
serve: ## Serve the site locally
	@docker run --rm -it -p 80:8088 -v "$(CURDIR)":/workspace -w /workspace $(DOCKER_IMAGE) \
	  emacs -Q $(emacs-load-options) --funcall serve

.PHONY: clean
clean: ## Remove built artefacts and docs
	@rm -rf $(sources-build-artefacts)
	@rm -rf docs

.PHONY: cleaner
cleaner: clean ## Remove built artefacts, docs, and packages
	@rm -rf .packages
