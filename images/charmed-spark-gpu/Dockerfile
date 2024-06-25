ARG BASE_IMAGE=staged-charmed-spark:latest
FROM $BASE_IMAGE
# Provide Default Entrypoint for Pebble
ENTRYPOINT [ "/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]