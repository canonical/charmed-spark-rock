ARG BASE_IMAGE=base-charmed-spark:latest
FROM $BASE_IMAGE
# Provide Default Entrypoint for Pebble
ENTRYPOINT [ "/opt/pebble/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]