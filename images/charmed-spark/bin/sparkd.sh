#!/bin/bash

function get_loki_url {
  if [ ! -z "$LOKI_URL" ]; then
    echo "$(<<< "$LOKI_URL" sed -e 's`[][\\/.*^$]`\\&`g')"
  elif [ -f "$SPARK_CONF_DIR/spark.properties" ]; then
    loki_url="$(grep -oP '(?<=spark.executorEnv.LOKI_URL=).*' $SPARK_CONF_DIR/spark.properties)"
    echo "$(<<< "$loki_url" sed -e 's/\\:/:/g' -e 's`[][\\/.*^$]`\\&`g')"
  fi
}

function get_log_layer {
  local loki_url=$1
  local log_layer_file=${2-"/opt/pebble/log-layer.yaml"}
  sed -e "s/\$LOKI_URL/$loki_url/g" \
      -e "s/\$FLAVOUR/$FLAVOUR/g" \
      -e "s/\$SPARK_APPLICATION_ID/$SPARK_APPLICATION_ID/g" \
      -e "s/\$SPARK_USER/$SPARK_USER/g" \
      -e "s/\$HOSTNAME/$HOSTNAME/g" \
      $log_layer_file
}

function log_forwarding {
  local loki_url=$(get_loki_url)
  if [ ! -z "$loki_url" ]; then
      echo "Log-forwarding to Loki is enabled"
      local rendered_log_layer=$(get_log_layer $loki_url)
      echo "$rendered_log_layer" | tee /tmp/rendered_log_layer.yaml
      pebble add logging /tmp/rendered_log_layer.yaml
  else
      echo "Log-forwarding to Loki is disabled."
  fi
}

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
    log_forwarding
    pushd /opt/spark
    ./entrypoint.sh "$@"
    ;;
  "")
    log_forwarding
    # Infinite sleep to allow pebble to be running indefinitely
    sleep inf
    ;;
  *)
    echo "Component \"${FLAVOUR}\" unknown"
    exit 1
    ;;
esac
