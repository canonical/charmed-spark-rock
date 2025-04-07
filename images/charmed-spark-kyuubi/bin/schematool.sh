#!/usr/bin/env bash

SPARK_JARS=/opt/spark/jars
KYUUBI_JARS=/opt/kyuubi/jars

check_jar() {
  local jar_name=$1

  if [ ! -e "${SPARK_JARS}/${jar_name}" ] && [ ! -e "${KYUUBI_JARS}/${jar_name}" ]; then
    echo "Missing Jar: ${jar_name}"
    exit 1
  fi
}

# Ensure necessary jars needed for execution
check_jar "hive-exec-*.jar"
check_jar "hive-metastore-*.jar"
check_jar "hive-cli-*.jar"

export HIVE_HOME=/opt/hive
CLASSPATH="${SPARK_JARS}/*:${KYUUBI_JARS}/*"

CLASS=org.apache.hive.beeline.HiveSchemaTool
exec java -cp $CLASSPATH $CLASS "$@"