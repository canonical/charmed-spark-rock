#!/bin/bash

function get_log_layer {
  LOG_LAYER_FILE="/opt/pebble/log-layer.yaml"
  ESCAPED_LOKI_URL="$(<<< "$LOKI_URL" sed -e 's`[][\\/.*^$]`\\&`g')"
  sed -e "s/\$LOKI_URL/$ESCAPED_LOKI_URL/g" \
      -e "s/\$SPARK_APPLICATION_ID/$SPARK_APPLICATION_ID/g" \
      -e "s/\$SPARK_USER/$SPARK_USER/g" \
      -e "s/\$SPARK_EXECUTOR_POD_NAME/$SPARK_EXECUTOR_POD_NAME/g" \
      $LOG_LAYER_FILE
}

function finish {
  if [ $? -ne 0 ]
  then
    kill -1 1
    sleep 1
  fi
}
trap finish EXIT

if [ ! -z "${LOKI_URL}" ]
then
    echo "Configuring log-forwarding to Loki."
    RENDERED_LOG_LAYER=$(get_log_layer)
    echo "$RENDERED_LOG_LAYER" | tee /tmp/rendered_log_layer.yaml
    pebble add logging /tmp/rendered_log_layer.yaml
else
    echo "Log-forwarding to Loki is disabled."
fi

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
