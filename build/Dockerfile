ARG BASE_IMAGE=staged-charmed-spark:3.4.2
FROM $BASE_IMAGE
# Provide Default Entrypoint for Pebble
ENTRYPOINT [ "/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]