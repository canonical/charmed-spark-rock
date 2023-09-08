#!/bin/bash

FLAVOUR=$1

echo "Running script with ${FLAVOUR} flavour"

case "${FLAVOUR}" in
  driver|executor)
    pushd /opt/spark
    ./entrypoint.sh "$@"
    ;;
  jupyter)
    shift
    spark-client.pyspark "$@"
    ;;
  history-server)
    /opt/pebble/charmed-spark-history-server.sh
    ;;
  "")
    # Infinite sleep to allow pebble to be running indefinitely
    sleep inf
    ;;
  *)
    echo "Component \"${FLAVOUR}\" unknown"
    exit 1
    ;;
esac