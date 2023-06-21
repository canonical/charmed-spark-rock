#!/bin/bash

TYPE=$1
shift

echo "Running script with ${TYPE} flavour"

if [ "${TYPE}" == "history-server" ]; then
  cd /opt/spark
  ./sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}
elif [ "${TYPE}" == "jobs" ]; then
  cd /opt/spark
  ./entrypoint.sh "$*"
else
  echo "Component \"${TYPE}\" unknown"
  exit 1
fi
