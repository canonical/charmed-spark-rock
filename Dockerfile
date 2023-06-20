ARG BASE_IMAGE=charmed-spark:latest
FROM $BASE_IMAGE
# Remove Pebble
RUN rm -rf /usr/bin/pebble /opt/pebble /var/lib/pebble
# Set environment variables
ENV SPARK_CONFS="/etc/spark8t/conf"
ENV SPARK_HOME="/opt/spark"
ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
ENV PYTHONPATH="/opt/spark/python:/opt/spark8t/python/dist:/usr/lib/python3/dist-packages"
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/spark:/opt/spark/bin:/opt/spark/python/bin:/opt/spark-client/python/bin"
ENV HOME="/home/spark"
ENV KUBECONFIG="/home/spark/.kube/config"
ENV SPARK_USER_DATA="/home/spark"
# Entrypoint specification
USER spark
WORKDIR $SPARK_HOME
ENTRYPOINT ["/bin/bash", "./entrypoint.sh"]