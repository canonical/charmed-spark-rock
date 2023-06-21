# Makefile macros (or variables) are defined a little bit differently than traditional bash, keep in mind that in the Makefile there's top-level Makefile-only syntax, and everything else is bash script syntax.

# .PHONY defines parts of the makefile that are not dependant on any specific file
# This is most often used to store functions
# .PHONY = help clean

# ======================
# EXTERNAL VARIABLES
# ======================

REPOSITORY :=
PREFIX :=
TARGET := microk8s

# ======================
# INTERNAL VARIABLES
# ======================

_MAKE_DIR := .make_cache
$(shell mkdir -p $(_MAKE_DIR))

K8S_TAG := $(_MAKE_DIR)/.k8s_tag

PLATFORM=amd64
IMAGE_NAME := $(shell yq .name rockcraft.yaml)
VERSION := $(shell yq .version rockcraft.yaml)

_ROCK_OCI=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).rock
_JOB_OCI_NAME := spark

CHARMED_OCI_FULL_NAME=$(REPOSITORY)$(PREFIX)$(IMAGE_NAME)
JOB_OCI_FULL_NAME=$(REPOSITORY)$(PREFIX)$(_JOB_OCI_NAME)

CHARMED_OCI_TAG := $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(VERSION).tag
JOB_OCI_TAG := $(_MAKE_DIR)/$(JOB_OCI_FULL_NAME)/$(VERSION).tag

help:
	@echo "$(JOB_OCI_FULL_NAME)"
	@echo "---------------HELP-----------------"
	@echo "Image: $(IMAGE_NAME)"
	@echo "Version: $(VERSION)"
	@echo " "
	@echo "Type 'make' followed by one of these keywords:"
	@echo " "
	@echo "  - build for creating the OCI Images"
	@echo "  - deploy for uploading the images to a container registry"
	@echo "  - integration-test for running integration tests"
	@echo "  - clean for removing cache file"
	@echo "------------------------------------"

$(_ROCK_OCI): rockcraft.yaml
	@echo "=== Building Charmed Image ==="
	rockcraft pack

$(CHARMED_OCI_TAG): $(_ROCK_OCI)
	skopeo --insecure-policy \
          copy \
          oci-archive:"$(_ROCK_OCI)" \
          docker-daemon:"$(CHARMED_OCI_FULL_NAME):$(VERSION)"
	if [ ! -d "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)"; fi
	touch $(CHARMED_OCI_TAG)

$(JOB_OCI_TAG): $(CHARMED_OCI_TAG)
	docker build - -t "$(JOB_OCI_FULL_NAME):$(VERSION)" --build-arg BASE_IMAGE="$(CHARMED_OCI_FULL_NAME):$(VERSION)" < Dockerfile
	if [ ! -d "$(_MAKE_DIR)/$(JOB_OCI_FULL_NAME)" ]; then mkdir -p "$(_MAKE_DIR)/$(JOB_OCI_FULL_NAME)"; fi
	touch $(JOB_OCI_TAG)

build: $(JOB_OCI_TAG) $(CHARMED_OCI_TAG)

$(K8S_TAG):
	/bin/bash ./tests/integration/setup-microk8s.sh
	sg microk8s ./tests/integration/config-microk8s.sh
	@touch $(K8S_TAG)

microk8s: $(K8S_TAG)

$(_MAKE_DIR)/%/$(VERSION).tar: $(_MAKE_DIR)/%/$(VERSION).tag
	docker save $*:$(VERSION) > $(_MAKE_DIR)/$*/$(VERSION).tar

ifeq ($(TARGET), registry)
deploy: build
	docker push $(CHARMED_OCI_FULL_NAME):$(VERSION)
	docker push $(JOB_OCI_FULL_NAME):$(VERSION)
endif

ifeq ($(TARGET), microk8s)
deploy: $(K8S_TAG) $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(VERSION).tar $(_MAKE_DIR)/$(JOB_OCI_FULL_NAME)/$(VERSION).tar
	microk8s ctr image import - --base-name $(CHARMED_OCI_FULL_NAME):$(VERSION) < $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(VERSION).tar
	microk8s ctr image import - --base-name $(JOB_OCI_FULL_NAME):$(VERSION) < $(_MAKE_DIR)/$(JOB_OCI_FULL_NAME)/$(VERSION).tar
endif

integration-tests: deploy
	@echo "=== Running Integration Tests ==="
	sg microk8s tests/integration/ie-tests.sh

clean:
	@echo "=== Cleaning environment ==="
	rm -rf $(_MAKE_DIR) $(_ROCK_OCI)
