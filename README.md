# spark-rock
ROCK for Spark on Kubernetes. It provides a direct port of this Spark provided [Dockerfile](https://github.com/apache/spark/blob/master/resource-managers/kubernetes/docker/src/main/dockerfiles/spark/Dockerfile).

## Build the image yourself

After cloning the repo, run the following commands.

- Build the Spark ROCK.
```bash
sudo snap install rockcraft --classic --edge
rockcraft pack --verbose
```

- Publish the built Spark ROCK to private registry running at ```localhost:32000```
```bash
sudo snap install skopeo --edge --devmode
skopeo --insecure-policy copy oci-archive:spark_0.1_amd64.rock docker-daemon:localhost:32000/sparkrock:latest
docker push localhost:32000/sparkrock:latest
```
Skopeo is a tool for manipulating, inspecting, signing, and transferring container images and image repositories on Linux® systems, Windows and MacOS. 
Skopeo is an open source community-driven project that does not require running a container daemon.
With Skopeo, you can inspect images on a remote registry without having to download the entire image with all its layers, 
making it a lightweight and modular solution for working with container images across different formats, including Open Container Initiative (OCI) and Docker images.

## Use Spark client snap to validate the Image

- With the spark client snap installed, run the following command to launch a Spark job using the above created image for validation.
```bash
spark-client.spark-submit --deploy-mode cluster --conf spark.kubernetes.container.image=localhost:32000/sparkrock:latest --class org.apache.spark.examples.SparkPi local:///opt/spark/examples/jars/spark-examples_2.12-3.3.0.jar 100
```

- Play with a pyspark script placed in S3.
```bash
spark-client.spark-submit  --deploy-mode cluster --name pyspark-s3a --properties-file <path to spark-defaults.conf> --conf spark.kubernetes.container.image='localhost:32000/sparkrock:latest' <S3 location of pyspark script>
```

## Use Spark from within a Container!

The Canonical spark-client scripts are bundled within the OCI rock image as well. 
To be able to launch Spark jobs in the Kubernetes cluster from within a container, only following additional resources are needed.

- Kubernetes Configuration File at ```$HOME/.kube/config```.
- Spark and S3 etc. Configuration.

Follow these steps to 

1. launch the container. 

```bash
export SPARK_DRIVER_PORT=20002
export SPARK_BLOCKMANAGER_PORT=6060
export SPARK_UID=185
export SPARK_GID=185
export SPARK_USER_HOME=/var/lib/spark
export SPARK_DRIVER_HOST=$(hostname -I | cut -d' ' -f1)
docker run -it -p $SPARK_DRIVER_PORT:$SPARK_DRIVER_PORT -p $SPARK_BLOCKMANAGER_PORT:$SPARK_BLOCKMANAGER_PORT -u $SPARK_GID:$SPARK_UID -w $SPARK_USER_HOME --entrypoint /bin/bash ghcr.io/canonical/charmed-spark:3.4.1-22.04_edge
```

2. From within the container, setup and launch the Spark job
```bash
# create kubeconfig
mkdir .kube
cat > .kube/config << EOF
KUBECONFIG_CONTENTS
EOF

# create spark configuration
mkdir conf
cat > ./conf/spark-defaults.conf << EOF
SPARK_CONF_CONTENTS
EOF

# create user in registry for launching Spark jobs
python3 -m spark_client.cli.service-account-registry create --username hello --properties-file ./conf/spark-defaults.conf --conf spark.driver.host=$SPARK_DRIVER_HOST --conf spark.driver.port=$SPARK_DRIVER_PORT --conf spark.blockManager.port=$SPARK_BLOCKMANAGER_PORT

# launch Spark job
python3 -m spark_client.cli.spark-submit --username hello --deploy-mode cluster --class org.apache.spark.examples.SparkPi local:///opt/spark/examples/jars/spark-examples_2.12-3.4.1.jar 100
```




