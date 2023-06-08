#!/bin/bash

# This script still exists because passing of working directory to services has not yet landed
# in Pebble (https://github.com/canonical/pebble/issues/158) and being in the write directory
# is important for the entrypoint script

# Feed Env Variables to Pebble Command
ENV_LIST=""
for ENV_VAR in $(env);
do
  ENV_LIST="$ENV_LIST --env $ENV_VAR"
done

# Exec entrypoint via Pebble
/bin/pebble exec --user spark --group spark -w /opt/spark $ENV_LIST -- /bin/bash /opt/spark/entrypoint.sh $*
