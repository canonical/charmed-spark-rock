#!/bin/bash

pushd /opt/spark
/opt/spark/sbin/start-thriftserver.sh --properties-file ${SPARK_PROPERTIES_FILE}