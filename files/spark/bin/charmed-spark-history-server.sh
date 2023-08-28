#!/bin/bash

pushd /opt/spark
mkdir -p /tmp/spark-events
/opt/spark/sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}