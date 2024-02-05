## Introduction to Charmed Spark ROCK  (OCI Image)

[![Container Registry](https://img.shields.io/badge/Container%20Registry-published-blue)](https://github.com/canonical/charmed-spark-rock/pkgs/container/charmed-spark)
[![Release](https://github.com/canonical/charmed-spark-rock/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/charmed-spark-rock/actions/workflows/publish.yaml)

Charmed Spark is a set of Canonical supported artifacts (including charms, ROCK OCI images and SNAPs) that makes operating Spark workloads on Kubernetes seamless, secure and production-ready. 

The solution helps to simplify user interaction with Spark applications and the underlying Kubernetes cluster whilst retaining the traditional semantics and command line tooling that users already know. Operators benefit from straightforward, automated deployment of Spark components (e.g. Spark History Server) to the Kubernetes cluster, using [Juju](https://juju.is/). 

Deploying Spark applications to Kubernetes has several benefits over other cluster resource managers such as Apache YARN, as it greatly simplifies deployment, operation, authentication while allowing for flexibility and scaling. However, it requires knowledge on Kubernetes, networking and coordination between the different components of the Spark ecosystem in order to provide a scalable, secure and production-ready environment. As a consequence, this can significantly increase complexity for the end user and administrators, as a number of parameters need to be configured and prerequisites must be met for the application to deploy correctly or for using the Spark CLI interface (e.g. pyspark and spark-shell). 

Charmed Spark helps to address these usability concerns and provides a consistent management interface for operations engineers and cluster administrators who need to manage enablers like Spark History Server.

### Features 

The Charmed Spark Rock comes with some built-in tooling embedded:

* Canonical-supported Spark binaries 
* [`spark8t`](https://github.com/canonical/spark-k8s-toolkit-py) CLI for managing Spark service accounts
* [Pebble](https://github.com/canonical/pebble) managed services:
  * [Spark History Server](https://spark.apache.org/docs/latest/monitoring.html) for monitoring your Spark jobs

## Version

ROCKs will be named as `<version>-<series>_<risk>`.

`<version>` is the software version; `<series>` is the Ubuntu LTS series that ROCKs supports; and the <risk> is the type of release, if it is edge, candidate or stable. Example versioning will be 3.4-22.04_stable which means Charmed Spark is a version 3.4.x of the software, supporting the 22.04 Ubuntu release and currently a 'stable' version of the software. See  versioning details [here](https://snapcraft.io/docs/channels).

Channel can also be represented by combining `<version>_<risk>`

## Release

Charmed Spark ROCK are available at

https://github.com/canonical/charmed-spark-rock/pkgs/container/charmed-spark

## ROCKS Usage

### Using Charmed Spark OCI Image in K8s Job Execution

The image can be used straight away when running Spark on Kubernetes by setting the appropriate configuration property:

```shell
spark.kubernetes.container.image=ghcr.io/canonical/charmed-spark:3.4-22.04_edge
```

### Using `spark8t` CLI 

The `spark8t` CLI tooling interacts with the K8s API to create, manage and delete K8s resources representing the Spark service account. 
Make sure that the kube config file is correctly loaded into the container, e.g.
```shell
docker run --name chamed-spark -v /path/to/kube/config:/var/lib/spark/.kube/config ghcr.io/canonical/charmed-spark:3.4-22.04_edge
```

Note that this will start the image and a long-living service, allowing you to exec commands:
```shell
docker exec charmed-spark spark-client.service-account-registry list
```

If you prefer to run one-shot commands, without having the Charmed Spark image running, use `\; exec` prefix, e.g.
```shell
docker run -v ... ghcr.io/canonical/charmed-spark:3.4-22.04_edge \; exec spark-client.service-account-registry list
```

For more information about spark-client API and `spark8t` tooling, please refer to [here](https://discourse.charmhub.io/t/spark-client-snap-how-to-manage-spark-accounts/8959).

### Starting Pebble services

Charmed Spark Rock Image is delivered with Pebble already included in order to manage services. If you want to start a service, use the `\; start <service-name>` prefix.

#### Starting History Server

```shell
docker run ghcr.io/canonical/charmed-spark:3.4-22.04_edge \; start history-server
```

### Running Jupyter Lab

In the Charmed Spark bundle we also provide the `charmed-spark-jupyter` image, 
specifically built for running JupterLab server integrated with Spark where any notebook will also 
start dedicated executors and inject a SparkSession and/or SparkContext within the notebook.

To start a JupyterLab server using the `charmed-spark-jupyter` image, use

```shell
docker run \
  -v /path/to/kube/config:/var/lib/spark/.kube/config \
  -p <port>:8888
  ghcr.io/canonical/charmed-spark-jupyter:3.4-22.04_edge \
  --username <spark-service-account> --namespace <spark-namespace>
```

Make sure to have created the `<spark-service-account>` in the `<spark-namespace>` with the `spark8t` CLI beforehand.
You should be able to access the jupyter server at `http://0.0.0.0:<port>`.

You can provide extra-arguments to further configure the spark-executors by providing more `spark8t`
commands. The mount of the local `kubeconfig` file is necessary to provide the ability to the 
JupyterLab server to act as a Spark driver and request resources on the K8s cluster. 

## Developers and Contributing

Please see the [CONTRIBUTING.md](https://github.com/canonical/charmed-spark-rock/blob/3.4-22.04/edge/CONTRIBUTING.md) for guidelines and for developer guidance.

## Bugs and feature request

If you find a bug in this ROCK or want to request a specific feature, here are the useful links:

-   Raise the issue or feature request in the [Canonical Github](https://github.com/canonical/charmed-spark-rock/issues)

-   Meet the community and chat with us if there are issues and feature requests in our [Mattermost Channel](https://chat.charmhub.io/charmhub/channels/data-platform).

## Licence statement

Charmed Spark is free software, distributed under the [Apache Software License, version 2.0](https://github.com/canonical/charmed-spark-rock/blob/3.4-22.04/edge/LICENSE). 

## Trademark Notice

Apache®, Apache Spark, Spark®, and the Spark logo are either registered trademarks or trademarks of the Apache Software Foundation in the United States and/or other countries.
