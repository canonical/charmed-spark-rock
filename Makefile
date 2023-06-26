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

# ======================
# INTERNAL VARIABLES
# ======================

_MAKE_DIR := .make_cache
$(shell mkdir -p $(_MAKE_DIR))

K8S_TAG := $(_MAKE_DIR)/.k8s_tag

IMAGE_NAME := $(shell yq .name rockcraft.yaml)
VERSION := $(shell yq .version rockcraft.yaml)

TAG := $(VERSION)

BASE_NAME=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).tar

_ROCK_OCI=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).rock

_TMP_OCI_NAME := stage-$(IMAGE_NAME)
_TMP_OCI_TAG := $(_MAKE_DIR)/$(_TMP_OCI_NAME)/$(TAG).tag

CHARMED_OCI_FULL_NAME=$(REPOSITORY)$(PREFIX)$(IMAGE_NAME)
CHARMED_OCI_TAG := $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(TAG).tag

help:
	@echo "---------------HELP-----------------"
	@echo "Image: $(IMAGE_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Platform: $(PLATFORM)"
	@echo " "
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

$(_TMP_OCI_TAG): $(_ROCK_OCI)
	skopeo --insecure-policy \
          copy \
          oci-archive:"$(_ROCK_OCI)" \
          docker-daemon:"$(_TMP_OCI_NAME):$(TAG)"
	if [ ! -d "$(_MAKE_DIR)/$(_TMP_OCI_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(_TMP_OCI_NAME)"; fi
	touch $(_TMP_OCI_TAG)

$(CHARMED_OCI_TAG): $(_TMP_OCI_TAG)
	docker build - -t "$(CHARMED_OCI_FULL_NAME):$(TAG)" --build-arg BASE_IMAGE="$(_TMP_OCI_NAME):$(TAG)" < Dockerfile
	if [ ! -d "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)"; fi
	touch $(CHARMED_OCI_TAG)

$(K8S_TAG):
	@echo "=== Setting up and configure local Microk8s cluster ==="
	/bin/bash ./tests/integration/setup-microk8s.sh
	sg microk8s ./tests/integration/config-microk8s.sh
	@touch $(K8S_TAG)

microk8s: $(K8S_TAG)

$(_MAKE_DIR)/%/$(TAG).tar: $(_MAKE_DIR)/%/$(TAG).tag
	docker save $*:$(TAG) > $(_MAKE_DIR)/$*/$(TAG).tar

$(BASE_NAME): $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(TAG).tar
	@echo "=== Creating $(BASE_NAME) OCI archive ==="
	cp $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(TAG).tar $(BASE_NAME)

build: $(BASE_NAME)

ifeq ($(TARGET), docker)
import: build
	@echo "=== Importing image $(CHARMED_OCI_FULL_NAME):$(TAG) into docker ==="
	$(eval IMAGE := $(shell docker load -i $(BASE_NAME)))
	docker tag $(lastword $(IMAGE)) $(CHARMED_OCI_FULL_NAME):$(TAG)
	if [ ! -d "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)"; fi
	touch $(CHARMED_OCI_TAG)
endif

ifeq ($(TARGET), microk8s)
import: $(K8S_TAG) build
	@echo "=== Importing image $(CHARMED_OCI_FULL_NAME):$(TAG) into Microk8s container registry ==="
	microk8s ctr images import --base-name $(CHARMED_OCI_FULL_NAME):$(TAG) $(BASE_NAME)
endif

tests:
	@echo "=== Running Integration Tests ==="
	/bin/bash ./tests/integration/integration-tests.sh

clean:
	@echo "=== Cleaning environment ==="
	rockcraft clean
	rm -rf $(_MAKE_DIR) *.rock *.tar
