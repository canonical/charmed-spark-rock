#!/bin/bash

TYPE=$1
shift

if [ "${TYPE}" == "history-server" ];
then
  cd /opt/spark
  echo ./sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}
else
  echo "Component \"${TYPE}\" unknown"
  exit 1
fi