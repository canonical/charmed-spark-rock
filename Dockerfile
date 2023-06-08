FROM charmed-spark:pre
RUN sed -e "s/on_success/on-success/" -e "s/on_failure/on-failure/" /var/lib/pebble/default/layers/001-charmed-spark.yaml > /var/lib/pebble/default/layers/002-charmed-spark.yaml
RUN rm /var/lib/pebble/default/layers/001-charmed-spark.yaml && mv /var/lib/pebble/default/layers/002-charmed-spark.yaml /var/lib/pebble/default/layers/001-charmed-spark.yaml 