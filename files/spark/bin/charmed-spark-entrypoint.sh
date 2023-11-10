#!/bin/bash

function finish {
  if [ $? -ne 0 ]
  then
    kill -1 1
    sleep 1
  fi
}
trap finish EXIT


FLAVOUR=$1

echo "Running script with ${FLAVOUR} flavour"

case "${FLAVOUR}" in
  driver|executor)
    pushd /opt/spark
    ./entrypoint.sh "$@"
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
