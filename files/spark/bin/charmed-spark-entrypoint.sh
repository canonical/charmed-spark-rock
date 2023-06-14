#!/bin/bash

# This script still exists because passing of working directory to services has not yet landed
# in Pebble (https://github.com/canonical/pebble/issues/158) and being in the write directory
# is important for the entrypoint script

cd /opt/spark

./entrypoint.sh $*