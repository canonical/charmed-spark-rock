FROM history:latest
ENTRYPOINT ["/bin/bash", "/opt/pebble/charmed-spark-entrypoint.sh", "jobs"]