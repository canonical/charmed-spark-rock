#!/bin/bash

pushd /opt/spark
mkdir -p /tmp/spark-events
export SPARK_NO_DAEMONIZE="true"
/opt/spark/sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}