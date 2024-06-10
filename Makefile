# Copyright 2023 Canonical Ltd.
# See LICENSE file for licensing details.

# Makefile macros (or variables) are defined a little bit differently than traditional bash, keep in mind that in the Makefile there's top-level Makefile-only syntax, and everything else is bash script syntax.

# .PHONY defines parts of the makefile that are not dependant on any specific file
# This is most often used to store functions
.PHONY: help clean build import tests

# ======================
# EXTERNAL VARIABLES
# ======================

# The repository where the image is going to be hosted.
# eg, ghcr.io/canonical [To be passed when you 'make' the recipe]
REPOSITORY := 

# The prefix to be pre-pended to image name
# eg, test- [To be passed when you 'make' the recipe]
PREFIX := 

TARGET := docker
PLATFORM := amd64
FLAVOUR := "spark"
MICROK8S_CHANNEL := "1.28/stable"

# ======================
# INTERNAL VARIABLES
# ======================

# The directory to be used as cache, where intermediate tag files will be stored.
_MAKE_DIR := .make_cache
$(shell mkdir -p $(_MAKE_DIR))


# Fetch name of image and it's version from rockcraft.yaml
# eg, charmed-spark
ROCK_NAME := $(shell yq .name rockcraft.yaml)

SPARK_VERSION := $(shell yq .version rockcraft.yaml)
KYUUBI_VERSION=$(shell grep "version:kyuubi" rockcraft.yaml | sed "s/^#//" | cut -d ":" -f3)
JUPYTER_VERSION=$(shell grep "version:jupyter" rockcraft.yaml | sed "s/^#//" | cut -d ":" -f3)

# The filename of the Rock file built during the build process.
# eg, charmed-spark_3.4.2_amd64.rock
ROCK_FILE=$(ROCK_NAME)_$(SPARK_VERSION)_$(PLATFORM).rock


SPARK_ARTIFACT=$(ROCK_NAME)_$(SPARK_VERSION)_$(PLATFORM).tar
JUPYTER_ARTIFACT=$(ROCK_NAME)-jupyterlab_$(SPARK_VERSION)_$(PLATFORM).tar
KYUUBI_ARTIFACT=$(ROCK_NAME)-kyuubi_$(SPARK_VERSION)_$(PLATFORM).tar


# Decide on what the base name, display name and tag for the image will be.
# 
# ARTIFACT: The name of the tarfile that will be generated after building the image
# DISPLAY_NAME: The fully qualified name of the image without OCI tags
# TAG: The tag for the image
#
# For eg,
# ARTIFACT = "charmed-spark_3.4.2_amd64.tar" 			TAG = "3.4.2"			DISPLAY_NAME = "ghcr.io/canonical/charmed-spark"
# or,
# ARTIFACT = "charmed-spark-jupyterlab_3.4.2_amd64.tar"	TAG = "3.4.2-4.0.11"	DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-jupyterlab"
# or,
# ARTIFACT = "charmed-spark-kyuubi_3.4.2_amd64.tar"		TAG = "3.4.2-1.9.0"		DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-kyuubi"
#
ifeq ($(FLAVOUR), jupyter)
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)-jupyterlab
	TAG=$(SPARK_VERSION)-$(JUPYTER_VERSION)
	ARTIFACT=$(JUPYTER_ARTIFACT)
else ifeq ($(FLAVOUR), kyuubi)
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)-kyuubi
	TAG=$(SPARK_VERSION)-$(KYUUBI_VERSION)
	ARTIFACT=$(KYUUBI_ARTIFACT)
else
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)
	TAG=$(SPARK_VERSION)
	ARTIFACT=$(SPARK_ARTIFACT)
endif


SPARK_MARKER=$(_MAKE_DIR)/spark-$(SPARK_VERSION).tag
JUPYTER_MARKER=$(_MAKE_DIR)/jupyter-$(JUPYTER_VERSION).tag
KYUUBI_MARKER=$(_MAKE_DIR)/kyuubi-$(KYUUBI_VERSION).tag
K8s_MARKER=$(_MAKE_DIR)/k8s.tag
AWS_MARKER=$(_MAKE_DIR)/aws.tag


STAGED_IMAGE_DOCKER_ALIAS=staged-charmed-spark:$(SPARK_VERSION)
SPARK_DOCKER_ALIAS=charmed-spark:$(SPARK_VERSION)
JUPYTER_DOCKER_ALIAS=charmed-spark-jupyter:$(SPARK_VERSION)-$(JUPYTER_VERSION)
KYUUBI_DOCKER_ALIAS=charmed-spark-kyuubi:$(SPARK_VERSION)-$(KYUUBI_VERSION)



# ======================
# RECIPES
# ======================


# Display the help message that includes the available recipes provided by this Makefile,
# the name of the artifacts, instructions, etc.
help:
	@echo "---------------HELP-----------------"
	@echo "Name: $(ROCK_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Platform: $(PLATFORM)"
	@echo " "
	@echo "Flavour: $(FLAVOUR)"
	@echo " "
	@echo "Image: $(DISPLAY_NAME)"
	@echo "Tag: $(TAG)"
	@echo "Artifact: $(ARTIFACT)"
	@echo " "
	@echo "Type 'make' followed by one of these keywords:"
	@echo " "
	@echo "  - build for creating the OCI Images"
	@echo "  - import for importing the images to a container registry"
	@echo "  - microk8s setup a local Microk8s cluster for running integration tests"
	@echo "  - tests for running integration tests"
	@echo "  - clean for removing cache file"
	@echo "------------------------------------"



# Recipe for creating a rock image from the current repository.
# 
# ROCK_FILE => charmed-spark_3.4.2_amd64.rock 
#
$(ROCK_FILE): rockcraft.yaml $(wildcard files/spark/*/*)
	@echo "=== Building Charmed Image ==="
	rockcraft pack


rock: $(ROCK_FILE)


$(SPARK_MARKER): $(ROCK_FILE) build/Dockerfile
	skopeo --insecure-policy \
          copy \
          oci-archive:"$(ROCK_FILE)" \
          docker-daemon:"staged-charmed-spark:$(SPARK_VERSION)"

	docker build -t $(SPARK_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE="staged-charmed-spark:$(SPARK_VERSION)" \
		-f build/Dockerfile .

	docker save $(SPARK_DOCKER_ALIAS) -o $(SPARK_ARTIFACT)

	touch $(SPARK_MARKER)


spark: $(SPARK_MARKER)


$(JUPYTER_MARKER): $(SPARK_MARKER) build/Dockerfile.jupyter files/jupyter/bin/jupyterlab-server.sh files/jupyter/pebble/layers.yaml
	docker build -t $(JUPYTER_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE=$(SPARK_DOCKER_ALIAS) \
		--build-arg JUPYTERLAB_VERSION="$(JUPYTER_VERSION)" \
		-f build/Dockerfile.jupyter .

	docker save $(JUPYTER_DOCKER_ALIAS) -o $(JUPYTER_ARTIFACT)

	touch $(JUPYTER_MARKER)


jupyter: $(JUPYTER_MARKER)


$(KYUUBI_MARKER): $(SPARK_MARKER) build/Dockerfile.kyuubi files/kyuubi/bin/kyuubi.sh files/kyuubi/pebble/layers.yaml
	docker build -t $(KYUUBI_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE=$(SPARK_DOCKER_ALIAS) \
		-f build/Dockerfile.kyuubi .

	docker save $(KYUUBI_DOCKER_ALIAS) -o $(KYUUBI_ARTIFACT)

	touch $(KYUUBI_MARKER)


kyuubi: $(KYUUBI_MARKER)



$(ARTIFACT):
ifeq ($(FLAVOUR), jupyter)
	make jupyter
else ifeq ($(FLAVOUR), kyuubi)
	make kyuubi
else
	make spark
endif



# Shorthand recipe to build the image
#
# ARTIFACT => charmed-spark_3.4.2_amd64.tar
build: $(ARTIFACT)


# Recipe for cleaning up the build files and environment
# Cleans the make cache directory along with .rock and .tar files
clean:
	@echo "=== Cleaning environment ==="
	rm -rf $(_MAKE_DIR) *.rock *.tar


# Recipe that imports the image into docker container registry
docker-import: $(ARTIFACT)
	$(eval IMAGE := $(shell docker load -i $(ARTIFACT)))
	docker tag $(lastword $(IMAGE)) $(DISPLAY_NAME):$(TAG)


# Recipe that imports the image into microk8s container registry
microk8s-import: $(ARTIFACT) $(K8s_MARKER)
	$(eval IMAGE := $(shell microk8s ctr images import $(ARTIFACT) | cut -d' ' -f2))
	microk8s ctr images tag $(IMAGE) $(DISPLAY_NAME):$(TAG)


# Recipe that runs the integration tests
tests: $(K8s_MARKER) $(AWS_MARKER)
	@echo "=== Running Integration Tests ==="
ifeq ($(FLAVOUR), jupyter)
	/bin/bash ./tests/integration/integration-tests-jupyter.sh
else ifeq ($(FLAVOUR), kyuubi)
	/bin/bash ./tests/integration/integration-tests-kyuubi.sh
else
	/bin/bash ./tests/integration/integration-tests.sh
endif


# Shorthand recipe for setup and configuration of K8s cluster.
microk8s-setup: $(K8s_MARKER)

# Shorthand recipe for setup and configuration of AWS CLI.
aws-cli-setup: $(AWS_MARKER)

# Recipe for setting up and configuring the K8s cluster. 
# At the end of the process, a file marker is created to signify that this process is complete. 
#
# K8S_MARKER => .make_cache/k8s.tag
#
$(K8s_MARKER):
	@echo "=== Setting up and configuring local Microk8s cluster ==="
	/bin/bash ./tests/integration/setup-microk8s.sh $(MICROK8S_CHANNEL)
	sg microk8s ./tests/integration/config-microk8s.sh
	touch $(K8s_MARKER)

# Recipe for setting up and configuring the AWS CLI and credentials. 
# At the end of the process, a file marker is created to signify that this process is complete. 
# Depends upon K8S_MARKER because the S3 credentials to AWS CLI is provided by MinIO, which is a MicroK8s plugin

# AWS_MARKER => .make_cache/aws.tag
#
$(AWS_MARKER): $(K8s_MARKER)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(AWS_MARKER)
