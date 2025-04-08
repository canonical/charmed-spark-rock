#!/usr/bin/env bash

SPARK_JARS=/opt/spark/jars
KYUUBI_JARS=/opt/kyuubi/jars


check_jar() {
  local jar_glob=$1

  if ! compgen -G "${SPARK_JARS}/${jar_glob}" > /dev/null && \
     ! compgen -G "${KYUUBI_JARS}/${jar_glob}" > /dev/null; then
    echo "Missing Jar: ${jar_glob}"
    exit 1
  fi
}

# Ensure necessary jars needed for execution
check_jar "hive-exec-*.jar"
check_jar "hive-metastore-*.jar"
check_jar "hive-cli-*.jar"

export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=$SPARK_CONF_DIR
CLASSPATH="${SPARK_JARS}/*:${KYUUBI_JARS}/*"

CLASS=org.apache.hive.beeline.HiveSchemaTool
exec java -cp $CLASSPATH $CLASS "$@"