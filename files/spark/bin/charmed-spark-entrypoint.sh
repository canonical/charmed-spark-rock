#!/bin/bash

TYPE=$1

echo "Running script with ${TYPE} flavour"

case "${TYPE}" in
  driver|executor)
    cd /opt/spark
    ./entrypoint.sh $*
    ;;
  history-server)
    cd /opt/spark
    ./sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}
    ;;
  "")
    # Infinite loop to allow pebble to be running indefinitely
    while true; do sleep 5; done
    ;;
  *)
    echo "Component \"${TYPE}\" unknown"
    exit 1
    ;;
esac