# Project configuration.
PROJECT_NAME = scrapd

# Makefile variables.
SHELL = /bin/bash

# Makefile parameters.
RUN ?= local
TAG ?= $(shell git describe)

# Misc.
TOPDIR = $(shell git rev-parse --show-toplevel)
YAPF_EXCLUDE=*.eggs/*,*.tox/*,*venv/*
TWINE_REPO =

# Docker.
DOCKERFILE = Dockerfile$(SUFFIX)
DOCKER_ORG = scrapd
DOCKER_REPO = $(DOCKER_ORG)/$(PROJECT_NAME)
DOCKER_IMG = $(DOCKER_REPO):$(TAG)

# Run commands.
VENV_BIN = venv/bin
DOCKER_RUN_CMD = docker run --rm -t -v=$$(pwd):/usr/src/app $(DOCKER_IMG)
LOCAL_RUN_CMD = source $(VENV_BIN)/activate &&

# Determine whether running the command in a container or locally.
ifeq ($(RUN),docker)
  RUN_CMD = $(DOCKER_RUN_CMD)
else
  RUN_CMD = $(LOCAL_RUN_CMD)
endif

default: setup

.PHONY: help
help: # Display help
	@awk -F ':|##' \
		'/^[^\t].+?:.*?##/ {\
			printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
		}' $(MAKEFILE_LIST) | sort


.PHONY: build-docker
build-docker: Dockerfile ## Build a docker development image
	@docker build -t $(DOCKER_IMG) .

.PHONY: ci
ci: docs lint test

.PHONY: docs
docs: venv ## Ensure the documentation builds
	$(RUN_CMD) tox -e docs

.PHONY: lint
lint: venv ## Run the static analyzers
	$(RUN_CMD) tox -e flake8,pydocstyle,pylint,yapf

.PHONY: lint-format
lint-format: venv ## Check the code formatting using YAPF
	$(RUN_CMD) tox -e yapf

.PHONY: clean
clean: clean-repo clean-docker ## Clean everything (!DESTRUCTIVE!)

.PHONY: clean-repo
clean-repo: ## Remove unwanted files in project (!DESTRUCTIVE!)
	cd $(TOPDIR) && git clean -ffdx && git reset --hard

.PHONY: clean-docker
clean-docker: ## Remove all docker images built for this project (!DESTRUCTIVE!)
	@docker image rm -f $$(docker image ls --filter reference=$(DOCKER_IMAGE) -q) || true

.PHONY: dist
dist: wheel ## Package the application

.PHONY: dist-upload
dist-upload:
	$(RUN_CMD) twine upload $(TWINE_REPO) dist/*

.PHONY: format
format: ## Format the codebase using YAPF
	$(RUN_CMD) yapf -r -i -e{$(YAPF_EXCLUDE)} .

publish: ## Publish the documentation
	@bash $(TOPDIR)/.circleci/publish.sh

.PHONY: test
test: venv ## Run the unit tests
	$(RUN_CMD) tox

.PHONY: test-units
test-units: venv ## Run the unit tests
	$(RUN_CMD) tox -- -m "not integrations"

.PHONY: test-integrations
test-integrations: venv ## Run the unit tests
	$(RUN_CMD) tox -- -m "integrations"

setup: venv ## Setup the full environment (default)

venv: venv/bin/activate ## Setup local venv

venv/bin/activate: requirements.txt
	test -d venv || python3 -m venv venv
	. venv/bin/activate \
		&& pip install --upgrade pip setuptools \
		&& pip install -r requirements-dev.txt \
		&& pip install -e .
	echo "[ -f $(VENV_BIN)/postactivate ] && . $(VENV_BIN)/postactivate" >> $(VENV_BIN)/activate
	echo "export PYTHONBREAKPOINT=bpdb.set_trace" > $(VENV_BIN)/postactivate
	echo "source contrib/scrapd-complete.sh" > $(VENV_BIN)/postactivate
	echo "unset PYTHONBREAKPOINT" > $(VENV_BIN)/predeactivate

.PHONY: wheel
wheel: venv ## Build a wheel package
	$(RUN_CMD) python setup.py bdist_wheel
