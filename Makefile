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

# A file marker that signifies that K8s cluster has been properly setup and configured.
# eg, .make_cache/k8s.tag
K8S_TAG_FILE := $(_MAKE_DIR)/k8s.tag

# A file marker that signifies that AWS CLI and credentials have been properly setup and configured.
# eg, .make_cache/aws.tag
AWS_TAG_FILE := $(_MAKE_DIR)/aws.tag

# Fetch name of image and it's version from rockcraft.yaml
# eg, charmed-spark
IMAGE_NAME := $(shell yq .name rockcraft.yaml)
# eg, 3.4.2 
VERSION := $(shell yq .version rockcraft.yaml)

# Picks up the version of the flavor, from rockcraft.yaml. For this, there are comments in
# rockcraft.yaml in the pattern 'version:spark:x.x.x' and 'version:jupyter:x.x.x'.
# We pick the 'x.x.x' part from those comments.
# eg, 3.4.2 or 4.0.11
VERSION_FLAVOUR=$(shell grep "version:$(FLAVOUR)" rockcraft.yaml | sed "s/^#//" | cut -d ":" -f3)

# The filename of the Rock file built during the build process.
# eg, charmed-spark_3.4.2_amd64.rock
_ROCK_OCI=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).rock

# Display name for the Spark image, without tags.
# eg, ghcr.io/canonical/charmed-spark
CHARMED_OCI_FULL_NAME=$(REPOSITORY)$(PREFIX)$(IMAGE_NAME)

# Display name for the Jupyter Spark image, built on top of Spark image, without tags.
# eg, ghcr.io/canonical/charmed-spark-jupyterlab
CHARMED_OCI_JUPYTER=$(CHARMED_OCI_FULL_NAME)-jupyterlab

# Display name for the Kyuubi Spark image, built on top of Spark image, without tags.
# eg, ghcr.io/canonical/charmed-spark-kyuubi
CHARMED_OCI_KYUUBI=$(CHARMED_OCI_FULL_NAME)-kyuubi


# Decide on what the base name, display name and tag for the image will be.
# 
# BASE_NAME: The name of the tarfile that will be generated after building the image
# DISPLAY_NAME: The name of the image without OCI tags
# TAG: The tag for the image
#
# For eg,
# BASE_NAME = "charmed-spark_3.4.2_amd64.tar" 				TAG = "3.4.2"			DISPLAY_NAME = "ghcr.io/canonical/charmed-spark"
# or,
# BASE_NAME = "charmed-spark-jupyterlab_3.4.2_amd64.tar"	TAG = "3.4.2-4.0.11"	DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-jupyterlab"
# or,
# BASE_NAME = "charmed-spark-kyuubi_3.4.2_amd64.tar"		TAG = "3.4.2-1.9.0"		DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-kyuubi"
#
ifeq ($(FLAVOUR), jupyter)
	DISPLAY_NAME=$(CHARMED_OCI_JUPYTER)
	TAG=$(VERSION)-$(VERSION_FLAVOUR)
	BASE_NAME=$(IMAGE_NAME)-jupyterlab_$(VERSION)_$(PLATFORM).tar
else ifeq ($(FLAVOUR), kyuubi)
	DISPLAY_NAME=$(CHARMED_OCI_KYUUBI)
	TAG=$(VERSION)-$(VERSION_FLAVOUR)
	BASE_NAME=$(IMAGE_NAME)-kyuubi_$(VERSION)_$(PLATFORM).tar
else
	DISPLAY_NAME=$(CHARMED_OCI_FULL_NAME)
	TAG=$(VERSION)
	BASE_NAME=$(IMAGE_NAME)_$(VERSION)_$(PLATFORM).tar
endif

# The file marker that signifies the final tar build has been created.
# eg, .make_cache/charmed-spark/3.4.2.tag
FINAL_BUILD_TAG_FILE=$(_MAKE_DIR)/$(DISPLAY_NAME)/$(TAG).tag

# The path of the tar file that is created at the end of the build step
# eg, .make_cache/charmed-spark/3.4.2.tag
FINAL_BUILD_TAR_FILEPATH=$(_MAKE_DIR)/$(DISPLAY_NAME)/$(TAG).tar

# A file marker, whose existence signifies that base Spark image has been built.
# eg, .make_cache/ghcr.io/canonical/charmed-spark/3.4.2.tag
CHARMED_OCI_TAG_FILE := $(_MAKE_DIR)/$(CHARMED_OCI_FULL_NAME)/$(TAG).tag

# A file marker, whose existence signifies that the Jupyter Spark image has been built.
# eg, .make_cache/ghcr.io/canonical/charmed-spark-jupyterlab/3.4.2.tag
CHARMED_OCI_JUPYTER_TAG_FILE := $(_MAKE_DIR)/$(CHARMED_OCI_JUPYTER)/$(TAG).tag

# A file marker, whose existence signifies that the Kyuubi Spark image has been built.
# eg, .make_cache/ghcr.io/canonical/charmed-spark-kyuubi/3.4.2.tag
CHARMED_OCI_KYUUBI_TAG_FILE := $(_MAKE_DIR)/$(CHARMED_OCI_KYUUBI)/$(TAG).tag

# Name and file marker for a intermediary image created temporarily during the build process
# eg, stage-charmed-spark and .make_cache/stage-charmed-spark/3.4.2.tag
_TMP_OCI_NAME := stage-$(IMAGE_NAME)
_TMP_OCI_TAG_FILE := $(_MAKE_DIR)/$(_TMP_OCI_NAME)/$(TAG).tag


# ======================
# RECIPES
# ======================


# Display the help message that includes the available recipes provided by this Makefile,
# the name of the artifacts, instructions, etc.
help:
	@echo "---------------HELP-----------------"
	@echo "Name: $(IMAGE_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Platform: $(PLATFORM)"
	@echo " "
	@echo "Flavour: $(FLAVOUR)"
	@echo " "
	@echo "Image: $(DISPLAY_NAME)"
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


# Recipe for creating a rock image from the current repository.
# 
# _ROCK_OCI => charmed-spark_3.4.2_amd64.rock 
#
$(_ROCK_OCI): rockcraft.yaml
	@echo "=== Building Charmed Image ==="
	rockcraft pack


# Recipe for copying the rock image in '.rock' format to a temporary and intermediary docker image.
#
# This will register an image with name similar to 'stage-charmed-spark:3.4.2' in local docker registry.
# This image in turn will later be used as base image to create Jupyter and other flavors.
#
# _TMP_OCI_TAG_FILE => .make_cache/stage-charmed-spark/3.4.2.tag
#
$(_TMP_OCI_TAG_FILE): $(_ROCK_OCI)
	skopeo --insecure-policy \
          copy \
          oci-archive:"$(_ROCK_OCI)" \
          docker-daemon:"$(_TMP_OCI_NAME):$(TAG)"
	
	mkdir -p $$(dirname $(_TMP_OCI_TAG_FILE)) && touch $(_TMP_OCI_TAG_FILE)


# Recipe for setting up and configuring the K8s cluster. 
# At the end of the process, a file marker is created to signify that this process is complete. 
#
# K8s_TAG_FILE => .make_cache/k8s.tag
#
$(K8S_TAG_FILE):
	@echo "=== Setting up and configuring local Microk8s cluster ==="
	/bin/bash ./tests/integration/setup-microk8s.sh $(MICROK8S_CHANNEL)
	sg microk8s ./tests/integration/config-microk8s.sh
	touch $(K8S_TAG_FILE)

# Recipe for setting up and configuring the AWS CLI and credentials. 
# At the end of the process, a file marker is created to signify that this process is complete. 
# Depends upon K8S_TAG_FILE because the S3 credentials to AWS CLI is provided by MinIO, which is a MicroK8s plugin

# AWS_TAG_FILE => .make_cache/aws.tag
#
$(AWS_TAG_FILE): $(K8S_TAG_FILE)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(AWS_TAG_FILE)


# Shorthand recipe for setup and configuration of K8s cluster.
microk8s: $(K8S_TAG_FILE)


# Recipe for building the Charmed Spark OCI image 
# At the end of the process, a file marker is created to signify that this process is complete. 
#
# CHARMED_OCI_TAG_FILE => .make_cache/ghcr.io/canonical/charmed-spark/3.4.2.tag
#
$(CHARMED_OCI_TAG_FILE): $(_TMP_OCI_TAG_FILE) build/Dockerfile
	docker build -t "$(CHARMED_OCI_FULL_NAME):$(TAG)" \
		--build-arg BASE_IMAGE="$(_TMP_OCI_NAME):$(TAG)" \
		-f build/Dockerfile .
	
	mkdir -p $$(dirname $(CHARMED_OCI_TAG_FILE)) && touch $(CHARMED_OCI_TAG_FILE)


# Recipe for building the Charmed Spark Jupyter OCI image 
# At the end of the process, a file marker is created to signify that this process is complete. 
#
# CHARMED_OCI_JUPYTER_TAG_FILE => .make_cache/ghcr.io/canonical/charmed-spark-jupyterlab/3.4.2.tag
#
$(CHARMED_OCI_JUPYTER_TAG_FILE): $(CHARMED_OCI_TAG_FILE) build/Dockerfile.jupyter files/jupyter/bin/jupyterlab-server.sh files/jupyter/pebble/layers.yaml
	docker build -t "$(CHARMED_OCI_JUPYTER):$(TAG)" \
		--build-arg BASE_IMAGE="$(CHARMED_OCI_FULL_NAME):$(TAG)" \
		--build-arg JUPYTERLAB_VERSION="$(VERSION_FLAVOUR)" \
		-f build/Dockerfile.jupyter .

	mkdir -p $$(dirname $(CHARMED_OCI_JUPYTER_TAG_FILE)) && touch $(CHARMED_OCI_JUPYTER_TAG_FILE)


# Recipe for building the Charmed Spark Kyuubi OCI image 
# At the end of the process, a file marker is created to signify that this process is complete. 
#
# CHARMED_OCI_KYUUBI_TAG_FILE => .make_cache/ghcr.io/canonical/charmed-spark-kyuubi/3.4.2.tag
#
$(CHARMED_OCI_KYUUBI_TAG_FILE): $(CHARMED_OCI_TAG_FILE) build/Dockerfile.kyuubi files/kyuubi/bin/kyuubi.sh files/kyuubi/pebble/layers.yaml
	docker build -t "$(CHARMED_OCI_KYUUBI):$(TAG)" \
		--build-arg BASE_IMAGE="$(CHARMED_OCI_FULL_NAME):$(TAG)" \
		-f build/Dockerfile.kyuubi .

	mkdir -p $$(dirname $(CHARMED_OCI_KYUUBI_TAG_FILE)) && touch $(CHARMED_OCI_KYUUBI_TAG_FILE)


# Recipe for creating a TAR file for the corresponding OCI image.
# Once it has been ensured that the appropriate file marker for OCI image is in place (thus ensuring
# that the image has been created successfully), this recipe just proceeds to `docker save` the
# image to a tarfile.
#
# At the end of the process, a tar file for the image is created at the path of tag marker file. 
#
# $(_MAKE_DIR)/%/$(TAG).tar => .make_cache/ghcr.io/canonical/charmed-spark/3.4.2.tar
# $(_MAKE_DIR)/%/$(TAG).tag => .make_cache/ghcr.io/canonical/charmed-spark/3.4.2.tag
#
$(_MAKE_DIR)/%/$(TAG).tar: $(_MAKE_DIR)/%/$(TAG).tag
	docker save $*:$(TAG) -o $(_MAKE_DIR)/$*/$(TAG).tar


# Recipe that copies the final build of the TAR artifact in TAR to current directory,
#
# BASE_NAME => charmed-spark_3.4.2_amd64.tar
$(BASE_NAME): $(FINAL_BUILD_TAR_FILEPATH)
	@echo "=== Creating $(BASE_NAME) OCI archive (flavour: $(FLAVOUR)) ==="
	cp $(FINAL_BUILD_TAR_FILEPATH) $(BASE_NAME)


# Shorthand recipe to build the image
# The following is the sample build process when called `make build PREFIX=test- REPOSITORY=ghcr.io/canonical`
#
# BASE_NAME => charmed-spark_3.4.2_amd64.tar
build: $(BASE_NAME)



# Recipe that imports the image into docker container registry
ifeq ($(TARGET), docker)
import: build
	@echo "=== Importing image $(DISPLAY_NAME):$(TAG) into docker ==="
	$(eval IMAGE := $(shell docker load -i $(BASE_NAME)))
	docker tag $(lastword $(IMAGE)) $(DISPLAY_NAME):$(TAG)

	mkdir -p $$(dirname $(FINAL_BUILD_TAG_FILE)) && touch $(FINAL_BUILD_TAG_FILE)
endif


# Recipe that imports the image into microk8s container registry
ifeq ($(TARGET), microk8s)
import: $(K8S_TAG_FILE) build
	@echo "=== Importing image $(DISPLAY_NAME):$(TAG) into Microk8s container registry ==="
	microk8s ctr images import --base-name $(DISPLAY_NAME):$(TAG) $(BASE_NAME)
endif


# Recipe that runs the integration tests
tests: $(K8S_TAG_FILE) $(AWS_TAG_FILE)
	@echo "=== Running Integration Tests ==="
ifeq ($(FLAVOUR), jupyter)
	/bin/bash ./tests/integration/integration-tests-jupyter.sh
else
	/bin/bash ./tests/integration/integration-tests.sh
endif


# Recipe for cleaning up the build files and environment
# Cleans the make cache directory along with .rock and .tar files
clean:
	@echo "=== Cleaning environment ==="
	rockcraft clean
	rm -rf $(_MAKE_DIR) *.rock *.tar
