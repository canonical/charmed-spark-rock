# Copyright 2023 Canonical Ltd.
# See LICENSE file for licensing details.

# Makefile macros (or variables) are defined a little bit differently than traditional bash, keep in mind that in the Makefile there's top-level Makefile-only syntax, and everything else is bash script syntax.

# .PHONY defines parts of the makefile that are not dependant on any specific file
# This is most often used to store functions
.PHONY: help clean build import tests

# ======================
# EXTERNAL VARIABLES
# ======================

REPOSITORY :=
PREFIX :=
TARGET := docker
PLATFORM := amd64
FLAVOUR := "spark"

# ======================
# INTERNAL VARIABLES
# ======================

_MAKE_DIR := .make_cache
$(shell mkdir -p $(_MAKE_DIR))

K8S_TAG := $(_MAKE_DIR)/.k8s_tag
AWS_TAG := $(_MAKE_DIR)/.aws_tag

IMAGE_NAME := $(shell yq .name rockcraft.yaml)

VERSION := $(shell yq .version rockcraft.yaml)

VERSION_FLAVOUR=$(shell grep "version:$(FLAVOUR)" rockcraft.yaml | sed "s/^#//" | cut -d ":" -f3)

_ROCK_OCI=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).rock

CHARMED_OCI_FULL_NAME=$(REPOSITORY)$(PREFIX)$(IMAGE_NAME)
CHARMED_OCI_JUPYTER=$(CHARMED_OCI_FULL_NAME)-jupyterlab

ifeq ($(FLAVOUR), jupyter)
NAME=$(CHARMED_OCI_JUPYTER)
TAG=$(VERSION)-$(VERSION_FLAVOUR)
BASE_NAME=$(IMAGE_NAME)-jupyterlab_$(VERSION)_$(PLATFORM).tar
else
NAME=$(CHARMED_OCI_FULL_NAME)
TAG=$(VERSION)
BASE_NAME=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).tar
endif

FTAG=$(_MAKE_DIR)/$(NAME)/$(TAG)

CHARMED_OCI_TAG := $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(TAG)
CHARMED_OCI_JUPYTER_TAG := $(_MAKE_DIR)/$(CHARMED_OCI_JUPYTER)/$(TAG)

_TMP_OCI_NAME := stage-$(IMAGE_NAME)
_TMP_OCI_TAG := $(_MAKE_DIR)/$(_TMP_OCI_NAME)/$(TAG)

help:
	@echo "---------------HELP-----------------"
	@echo "Name: $(IMAGE_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Platform: $(PLATFORM)"
	@echo " "
	@echo "Flavour: $(FLAVOUR)"
	@echo " "
	@echo "Image: $(NAME)"
	@echo "Tag: $(TAG)"
	@echo "Artifact: $(BASE_NAME)"
	@echo " "
	@echo "Type 'make' followed by one of these keywords:"
	@echo " "
	@echo "  - build for creating the OCI Images"
	@echo "  - import for importing the images to a container registry"
	@echo "  - microk8s setup a local Microk8s cluster for running integration tests"
	@echo "  - tests for running integration tests"
	@echo "  - clean for removing cache file"
	@echo "------------------------------------"

$(_ROCK_OCI): rockcraft.yaml
	@echo "=== Building Charmed Image ==="
	rockcraft pack

$(_TMP_OCI_TAG).tag: $(_ROCK_OCI)
	skopeo --insecure-policy \
          copy \
          oci-archive:"$(_ROCK_OCI)" \
          docker-daemon:"$(_TMP_OCI_NAME):$(TAG)"
	if [ ! -d "$(_MAKE_DIR)/$(_TMP_OCI_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(_TMP_OCI_NAME)"; fi
	touch $(_TMP_OCI_TAG).tag

$(K8S_TAG):
	@echo "=== Setting up and configure local Microk8s cluster ==="
	/bin/bash ./tests/integration/setup-microk8s.sh
	sg microk8s ./tests/integration/config-microk8s.sh
	@touch $(K8S_TAG)

$(AWS_TAG): $(K8S_TAG)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(AWS_TAG)

microk8s: $(K8S_TAG)

$(CHARMED_OCI_TAG).tag: $(_TMP_OCI_TAG).tag build/Dockerfile
	docker build -t "$(CHARMED_OCI_FULL_NAME):$(TAG)" \
		--build-arg BASE_IMAGE="$(_TMP_OCI_NAME):$(TAG)" \
		-f build/Dockerfile .
	if [ ! -d "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)"; fi
	touch $(CHARMED_OCI_TAG).tag

$(CHARMED_OCI_JUPYTER_TAG).tag: $(CHARMED_OCI_TAG).tag build/Dockerfile.jupyter files/jupyter
	docker build -t "$(CHARMED_OCI_JUPYTER):$(TAG)" \
		--build-arg BASE_IMAGE="$(CHARMED_OCI_FULL_NAME):$(TAG)" \
		--build-arg JUPYTERLAB_VERSION="$(VERSION_FLAVOUR)" \
		-f build/Dockerfile.jupyter .
	if [ ! -d "$(_MAKE_DIR)/$(CHARMED_OCI_JUPYTER)" ]; then mkdir -p "$(_MAKE_DIR)/$(CHARMED_OCI_JUPYTER)"; fi
	touch $(CHARMED_OCI_JUPYTER_TAG).tag

$(_MAKE_DIR)/%/$(TAG).tar: $(_MAKE_DIR)/%/$(TAG).tag
	docker save $*:$(TAG) -o $(_MAKE_DIR)/$*/$(TAG).tar

$(BASE_NAME): $(FTAG).tar
	@echo "=== Creating $(BASE_NAME) OCI archive (flavour: $(FLAVOUR)) ==="
	cp $(FTAG).tar $(BASE_NAME)

build: $(BASE_NAME)

ifeq ($(TARGET), docker)
import: build
	@echo "=== Importing image $(NAME):$(TAG) into docker ==="
	$(eval IMAGE := $(shell docker load -i $(BASE_NAME)))
	docker tag $(lastword $(IMAGE)) $(NAME):$(TAG)
	if [ ! -d "$(_MAKE_DIR)/$(NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(NAME)"; fi
	touch $(FTAG).tag
endif

ifeq ($(TARGET), microk8s)
import: $(K8S_TAG) build
	@echo "=== Importing image $(NAME):$(TAG) into Microk8s container registry ==="
	microk8s ctr images import --base-name $(NAME):$(TAG) $(BASE_NAME)
endif

tests: $(K8S_TAG) $(AWS_TAG)
	@echo "=== Running Integration Tests ==="
ifeq ($(FLAVOUR), jupyter)
	/bin/bash ./tests/integration/integration-tests-jupyter.sh
else
	/bin/bash ./tests/integration/integration-tests.sh
endif

clean:
	@echo "=== Cleaning environment ==="
	rockcraft clean
	rm -rf $(_MAKE_DIR) *.rock *.tar
