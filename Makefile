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

PLATFORM := amd64

# The flavor of the image, (one of spark, jupyter and kyuubi)
FLAVOUR := "spark"

# The channel of `microk8s` snap to be used for testing
MICROK8S_CHANNEL := "1.28/stable"

# The Azure credentials supplied as environment variables
AZURE_STORAGE_ACCOUNT := ${AZURE_STORAGE_ACCOUNT}
AZURE_STORAGE_KEY := ${AZURE_STORAGE_KEY}

# ======================
# INTERNAL VARIABLES
# ======================

# The directory to be used as cache, where intermediate tag files will be stored.
_MAKE_DIR := .make_cache
$(shell mkdir -p $(_MAKE_DIR))


# eg, charmed-spark
ROCK_NAME := $(shell cat images/charmed-spark/rockcraft.yaml | yq .name)

# eg, 3.4.2
SPARK_VERSION := $(shell cat images/charmed-spark/rockcraft.yaml | yq .version)

# eg, 1.9.0
KYUUBI_VERSION=$(shell cat images/metadata.yaml | yq .flavours.kyuubi.version)

# eg, 4.0.11
JUPYTER_VERSION=$(shell cat images/metadata.yaml | yq .flavours.jupyter.version)

# eg, charmed-spark-gpu
ROCK_NAME_GPU := $(shell cat images/charmed-spark-gpu/rockcraft.yaml | yq .name)

# The filename of the Rock file built during the build process.
# eg, charmed-spark_3.4.2_amd64.rock
ROCK_FILE=$(ROCK_NAME)_$(SPARK_VERSION)_$(PLATFORM).rock

# The filename of the final artifact built for Spark image
# eg, charmed-spark_3.4.2_amd64.tar
SPARK_ARTIFACT=$(ROCK_NAME)_$(SPARK_VERSION)_$(PLATFORM).tar

# The filename of the final artifact built for Jupyter image
# eg, charmed-spark-jupyterlab_3.4.2_amd64.tar
JUPYTER_ARTIFACT=$(ROCK_NAME)-jupyterlab_$(SPARK_VERSION)_$(PLATFORM).tar

# The filename of the final artifact built for Kyuubi image
# eg, charmed-spark-kyuubi_3.4.2_amd64.tar
KYUUBI_ARTIFACT=$(ROCK_NAME)-kyuubi_$(SPARK_VERSION)_$(PLATFORM).tar

# The filename of the Rock file built during the build process.
# eg, charmed-spark_gpu_3.4.2_amd64.rock
ROCK_FILE_GPU=$(ROCK_NAME_GPU)_$(SPARK_VERSION)_$(PLATFORM).rock

# The filename of the final artifact built for Spark GPU image
# eg, charmed-spark-gpu_3.4.2_amd64.tar
SPARK_GPU_ARTIFACT=$(ROCK_NAME_GPU)_$(SPARK_VERSION)_$(PLATFORM).tar


# Decide on what the  name of artifact, display name and tag for the image will be.
# 
# ARTIFACT: The name of the tarfile (artifact) that will be generated after building the image
# DISPLAY_NAME: The fully qualified name of the image without tags
# TAG: The tag for the image
#
# For eg,
# ARTIFACT = "charmed-spark_3.4.2_amd64.tar" 			TAG = "3.4.2"			DISPLAY_NAME = "ghcr.io/canonical/charmed-spark"
# or,
# ARTIFACT = "charmed-spark-jupyterlab_3.4.2_amd64.tar"	TAG = "3.4.2-4.0.11"	DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-jupyterlab"
# or,
# ARTIFACT = "charmed-spark-kyuubi_3.4.2_amd64.tar"		TAG = "3.4.2-1.9.0"		DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-kyuubi"
# or, 
# ARTIFACT = "charmed-spark_gpu_3.4.2_amd64.tar" 			TAG = "3.4.2"			DISPLAY_NAME = "ghcr.io/canonical/charmed-spark-gpu"

ifeq ($(FLAVOUR), jupyter)
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)-jupyterlab
	TAG=$(SPARK_VERSION)-$(JUPYTER_VERSION)
	ARTIFACT=$(JUPYTER_ARTIFACT)
else ifeq ($(FLAVOUR), kyuubi)
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)-kyuubi
	TAG=$(SPARK_VERSION)-$(KYUUBI_VERSION)
	ARTIFACT=$(KYUUBI_ARTIFACT)
else ifeq ($(FLAVOUR), spark-gpu)
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)-gpu
	TAG=$(SPARK_VERSION)
	ARTIFACT=$(SPARK_GPU_ARTIFACT)
else
	DISPLAY_NAME=$(REPOSITORY)$(PREFIX)$(ROCK_NAME)
	TAG=$(SPARK_VERSION)
	ARTIFACT=$(SPARK_ARTIFACT)
endif


# Marker files that are used to specify certain make targets have been rebuilt.
#
# SPARK_MARKER: The Spark image has been built and has been registered with docker registry
# JUPYTER_MARKER: The Jupyter image has been built and has been registered with docker registry
# KYUUBI_MARKER: The Kyuubi image has been built and has been registered with docker registry
# K8S_MARKER: The MicroK8s cluster has been installed and configured successfully
# AWS_MARKER: The AWS CLI has been installed and configured with valid S3 credentials from MinIO
SPARK_MARKER=$(_MAKE_DIR)/spark-$(SPARK_VERSION).tag
SPARK_GPU_MARKER=$(_MAKE_DIR)/spark-gpu-$(SPARK_VERSION).tag
JUPYTER_MARKER=$(_MAKE_DIR)/jupyter-$(JUPYTER_VERSION).tag
KYUUBI_MARKER=$(_MAKE_DIR)/kyuubi-$(KYUUBI_VERSION).tag
K8S_MARKER=$(_MAKE_DIR)/k8s.tag
AWS_MARKER=$(_MAKE_DIR)/aws.tag
AZURE_MARKER=$(_MAKE_DIR)/azure.tag


# The names of different flavours of the image in the docker container registry
STAGED_IMAGE_DOCKER_ALIAS=staged-charmed-spark:latest
SPARK_DOCKER_ALIAS=charmed-spark:$(SPARK_VERSION)
SPARK_GPU_DOCKER_ALIAS=charmed-spark-gpu:$(SPARK_VERSION)
JUPYTER_DOCKER_ALIAS=charmed-spark-jupyter:$(SPARK_VERSION)-$(JUPYTER_VERSION)
KYUUBI_DOCKER_ALIAS=charmed-spark-kyuubi:$(SPARK_VERSION)-$(KYUUBI_VERSION)



# ======================
# RECIPES
# ======================


# Display the help message that includes the available recipes provided by this Makefile,
# the name of the artifacts, instructions, etc.
help:
	@echo "-------------------------HELP---------------------------"
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
	@echo "  - rock                 for building the rock image to a rock file"
	@echo "  - build FLAVOUR=xxxx   for creating the OCI Images with flavour xxxx"
	@echo "  - docker-import        for importing the images to Docker container registry"
	@echo "  - microk8s-import      for importing the images to MicroK8s container registry"
	@echo "  - microk8s-setup       to setup a local Microk8s cluster for running integration tests"
	@echo "  - aws-cli-setup        to setup the AWS CLI and S3 credentials for running integration tests"
	@echo "  - tests FLAVOUR=xxxx   for running integration tests for flavour xxxx"
	@echo "  - clean                for removing cache files, artifact file and rock file"
	@echo "--------------------------------------------------------"



# Recipe for creating a rock image from the current repository.
# 
# ROCK_FILE => charmed-spark_3.4.2_amd64.rock 
#
$(ROCK_FILE): images/charmed-spark/rockcraft.yaml $(wildcard images/charmed-spark/*/*)
	@echo "=== Building Charmed Image ==="
	(cd images/charmed-spark && rockcraft pack)
	mv images/charmed-spark/$(ROCK_FILE) .


rock: $(ROCK_FILE)


# Recipe that builds Spark image and exports it to a tarfile in the current directory
$(SPARK_MARKER): $(ROCK_FILE) images/charmed-spark/Dockerfile
	rockcraft.skopeo --insecure-policy \
          copy \
          oci-archive:"$(ROCK_FILE)" \
          docker-daemon:"$(STAGED_IMAGE_DOCKER_ALIAS)"

	docker build -t $(SPARK_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE="$(STAGED_IMAGE_DOCKER_ALIAS)" \
		images/charmed-spark-gpu

	docker save $(SPARK_DOCKER_ALIAS) -o $(SPARK_ARTIFACT)

	touch $(SPARK_MARKER)


# Shorthand recipe for building Spark image
spark: $(SPARK_MARKER)


# Recipe that builds Jupyter image and exports it to a tarfile in the current directory
$(JUPYTER_MARKER): $(SPARK_MARKER) images/charmed-spark-jupyter/Dockerfile $(wildcard images/charmed-spark-jupyter/*/*)
	docker build -t $(JUPYTER_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE=$(SPARK_DOCKER_ALIAS) \
		--build-arg JUPYTERLAB_VERSION="$(JUPYTER_VERSION)" \
		images/charmed-spark-jupyter

	docker save $(JUPYTER_DOCKER_ALIAS) -o $(JUPYTER_ARTIFACT)

	touch $(JUPYTER_MARKER)


# Shorthand recipe for building Jupyter image
jupyter: $(JUPYTER_MARKER)


# Recipe that builds Kyuubi image and exports it to a tarfile in the current directory
$(KYUUBI_MARKER): $(SPARK_MARKER) images/charmed-spark-kyuubi/Dockerfile $(wildcard images/charmed-spark-kyuubi/*/*)
	docker build -t $(KYUUBI_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE=$(SPARK_DOCKER_ALIAS) \
		images/charmed-spark-kyuubi

	docker save $(KYUUBI_DOCKER_ALIAS) -o $(KYUUBI_ARTIFACT)

	touch $(KYUUBI_MARKER)


# Shorthand recipe for building Kyuubi image
kyuubi: $(KYUUBI_MARKER)

$(ROCK_FILE_GPU): images/charmed-spark-gpu/rockcraft.yaml $(wildcard images/charmed-spark-gpu/*/*)
	@echo "=== Building Charmed Image ==="
	(cd images/charmed-spark-gpu && cp ../charmed-spark/bin/* bin/ && rockcraft pack)
	mv images/charmed-spark-gpu/$(ROCK_FILE_GPU) .

rock-gpu: $(ROCK_FILE_GPU)


# Recipe that builds Spark GPU image and exports it to a tarfile in the current directory
$(SPARK_GPU_MARKER): $(ROCK_FILE_GPU) images/charmed-spark-gpu/Dockerfile
	rockcraft.skopeo --insecure-policy \
          copy \
          oci-archive:"$(ROCK_FILE_GPU)" \
          docker-daemon:"$(STAGED_IMAGE_DOCKER_ALIAS)"

	docker build -t $(SPARK_GPU_DOCKER_ALIAS) \
		--build-arg BASE_IMAGE="$(STAGED_IMAGE_DOCKER_ALIAS)" \
		images/charmed-spark-gpu

	docker save $(SPARK_GPU_DOCKER_ALIAS) -o $(SPARK_GPU_ARTIFACT)

	touch $(SPARK_GPU_MARKER)

# Shorthand recipe for building Spark-gpu image
spark-gpu: $(SPARK_GPU_MARKER)

$(ARTIFACT):
ifeq ($(FLAVOUR), jupyter)
	make jupyter
else ifeq ($(FLAVOUR), kyuubi)
	make kyuubi
else ifeq ($(FLAVOUR), spark-gpu)
	make spark-gpu
else
	make spark
endif


# Shorthand recipe to build the image. The flavour is picked from FLAVOUR variable to `make`.
#
# eg, ARTIFACT => charmed-spark_3.4.2_amd64.tar
build: $(ARTIFACT)


# Recipe for cleaning up the build files and environment
# Cleans the make cache directory along with .rock and .tar files
clean:
	@echo "=== Cleaning environment ==="
	rm -rf $(_MAKE_DIR) *.rock *.tar
	(cd images/charmed-spark && rockcraft clean)
	(cd images/charmed-spark-gpu && rockcraft clean)


# Recipe that imports the image into docker container registry
docker-import: $(ARTIFACT)
	$(eval IMAGE := $(shell docker load -i $(ARTIFACT)))
	docker tag $(lastword $(IMAGE)) $(DISPLAY_NAME):$(TAG)


# Recipe that imports the image into microk8s container registry
microk8s-import: $(ARTIFACT) $(K8S_MARKER)
	$(eval IMAGE := $(shell microk8s ctr images import $(ARTIFACT) | cut -d' ' -f2))
	microk8s ctr images tag $(IMAGE) $(DISPLAY_NAME):$(TAG)


# Recipe that runs the integration tests
tests: $(K8S_MARKER) $(AWS_MARKER) $(AZURE_MARKER)
	@echo "=== Running Integration Tests ==="
ifeq ($(FLAVOUR), jupyter)
	/bin/bash ./tests/integration/integration-tests-jupyter.sh
else ifeq ($(FLAVOUR), spark-gpu)
	/bin/bash ./tests/integration/integration-tests-gpu.sh
else ifeq ($(FLAVOUR), kyuubi)
	@export AZURE_STORAGE_ACCOUNT=$(AZURE_STORAGE_ACCOUNT) \
			AZURE_STORAGE_KEY=$(AZURE_STORAGE_KEY) \
	&& /bin/bash ./tests/integration/integration-tests-kyuubi.sh
else
	@export AZURE_STORAGE_ACCOUNT=$(AZURE_STORAGE_ACCOUNT) \
			AZURE_STORAGE_KEY=$(AZURE_STORAGE_KEY) \
	&& /bin/bash ./tests/integration/integration-tests.sh
endif


# Shorthand recipe for setup and configuration of K8s cluster.
microk8s-setup: $(K8S_MARKER)

# Shorthand recipe for setup and configuration of AWS CLI.
aws-cli-setup: $(AWS_MARKER)

# Shorthand recipe for setup and configuration of Azure CLI.
azure-cli-setup: $(AZURE_MARKER)

# Recipe for setting up and configuring the K8s cluster. 
$(K8S_MARKER):
	@echo "=== Setting up and configuring local Microk8s cluster ==="
	/bin/bash ./tests/integration/setup-microk8s.sh $(MICROK8S_CHANNEL)
	sg microk8s ./tests/integration/config-microk8s.sh
	touch $(K8S_MARKER)


# Recipe for setting up and configuring the AWS CLI and credentials. 
# Depends upon K8S_MARKER because the S3 credentials to AWS CLI is provided by MinIO, which is a MicroK8s plugin
$(AWS_MARKER): $(K8S_MARKER)
	@echo "=== Setting up and configure AWS CLI ==="
	/bin/bash ./tests/integration/setup-aws-cli.sh
	touch $(AWS_MARKER)


# Recipe for setting up and configuring the Azure CLI and credentials. 
$(AZURE_MARKER):
	@echo "=== Setup and configure Azure CLI ==="
	/bin/bash ./tests/integration/setup-azure-cli.sh
	touch $(AZURE_MARKER)
