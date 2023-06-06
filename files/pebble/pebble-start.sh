#!/bin/bash

# Start  Pebble
/bin/pebble run --hold &

# Wait Pebble to be up and running...
sleep 1

# Feed Env Variables to Pebble Command
ENV_LIST=""
for ENV_VAR in $(env);
do
  ENV_LIST="$ENV_LIST --env $ENV_VAR"
done

# Exec entrypoint via Pebble
/bin/pebble exec --user spark --group spark -w /opt/spark $ENV_LIST -- /bin/bash /opt/spark/entrypoint.sh $*
