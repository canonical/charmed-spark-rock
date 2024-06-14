#!/bin/bash

sleep 5

export PYSPARK_DRIVER_PYTHON=jupyter

# This variable is injected when running a notebook from Kubeflow.
if [ ! -z "${NB_PREFIX}" ]; then
  NB_PREFIX_ARG="--NotebookApp.base_url '${NB_PREFIX}'"
fi

export PYSPARK_DRIVER_PYTHON_OPTS="lab --no-browser --port=8888 ${NB_PREFIX_ARG} --ip=0.0.0.0 --NotebookApp.token='' --notebook-dir=/var/lib/spark/notebook"

echo "PYSPARK_DRIVER_PYTHON_OPTS: ${PYSPARK_DRIVER_PYTHON_OPTS}"

spark-client.pyspark $*
