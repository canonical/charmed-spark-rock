#!/bin/bash

# This script still exists because passing of working directory to services has not yet landed
# in Pebble (https://github.com/canonical/pebble/issues/158) and being in the write directory
# is important for the entrypoint script

cd /opt/spark

TYPE=$1
shift

if [ "$TYPE" == "jobs" ];
then
  ./entrypoint.sh $*
fi

if [ "$TYPE" == "history-server" ];
then
  echo ./sbin/start-history-server.sh --properties-file ${SPARK_PROPERTIES_FILE}
fi