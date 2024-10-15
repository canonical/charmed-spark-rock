#!/bin/bash

# The integration tests are designed to tests that Spark Jobs can be submitted and/or shell processes are
# working properly with restricted permission of the service account starting the process. For this reason,
# in the tests we spawn two pods:
#
# 1. Admin pod, that is used to create and delete service accounts
# 2. User pod, that is used to start and execute Spark Jobs
#
# The Admin pod is created once at the beginning of the tests and it is used to manage Spark service accounts
# throughtout the integration tests. On the other hand, the User pod(s) are created together with the creation
# of the Spark user (service accounts and secrets) at the beginning of each test, and they are destroyed at the
# end of the test.


# Import reusable utilities
source ./tests/integration/utils/s3-utils.sh
source ./tests/integration/utils/k8s-utils.sh
source ./tests/integration/utils/azure-utils.sh


# Global Variables
NAMESPACE=tests
SERVICE_ACCOUNT=spark
ADMIN_POD_NAME=testpod-admin
S3_BUCKET=spark-$(uuidgen)
AZURE_CONTAINER=$S3_BUCKET

get_spark_version(){
  # Fetch Spark version from rockcraft.yaml
  yq '(.version)' images/charmed-spark/rockcraft.yaml
}


spark_image(){
  echo "ghcr.io/canonical/test-charmed-spark:$(get_spark_version)"
}


validate_pi_value() {
  pi=$1

  if [ "${pi}" != "3.1" ]; then
      echo "ERROR: Computed Value of pi is $pi, Expected Value: 3.1. Aborting with exit code 1."
      exit 1
  fi
}

validate_metrics() {
  log=$1
  if [ $(grep -Ri "spark" $log | wc -l) -lt 2 ]; then
      exit 1
  fi
}

validate_logs() {
  log=$1
  if [ $(grep -Ri "Log-forwarding to Loki is enabled." $log | wc -l) -lt 3 ]; then
    echo "ERROR: Could not validate logs."
    echo "DEBUG: Log file:\n$(cat $log)"
    exit 1
  fi
  if [ $(grep -Ri 'Layer \\\\"logging\\\\" added successfully from \\\\"/tmp/rendered_log_layer.yaml\\\\"' $log | wc -l) -lt 3 ]; then
    echo "ERROR: Could not validate logs."
    echo "DEBUG: Log file:\n$(cat $log)"
    exit 1
  fi
}

setup_user() {
  echo "setup_user() ${1} ${2}"

  USERNAME=$1
  NAMESPACE=$2

  create_serviceaccount_using_pod $USERNAME $NAMESPACE $ADMIN_POD_NAME

  # Create the pod with the Spark service account
  yq ea ".spec.serviceAccountName = \"${USERNAME}\"" \
    ./tests/integration/resources/testpod.yaml | \
    kubectl -n tests apply -f -

  wait_for_pod testpod $NAMESPACE

  TEST_POD_TEMPLATE=$(cat tests/integration/resources/podTemplate.yaml)

  kubectl -n $NAMESPACE exec testpod -- /bin/bash -c 'cp -r /opt/spark/python /var/lib/spark/'
  kubectl -n $NAMESPACE exec testpod -- env PTEMPLATE="$TEST_POD_TEMPLATE" /bin/bash -c 'echo "$PTEMPLATE" > /etc/spark/conf/podTemplate.yaml'
}

setup_user_context() {
  setup_user spark $NAMESPACE
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  kubectl -n $NAMESPACE delete pod testpod --wait=true

  kubectl -n $NAMESPACE exec testpod-admin -- env UU="$USERNAME" NN="$NAMESPACE" \
                  /bin/bash -c 'spark-client.service-account-registry delete --username $UU --namespace $NN'  

  OUTPUT=$(kubectl -n $NAMESPACE exec testpod-admin -- /bin/bash -c 'spark-client.service-account-registry list')

  EXISTS=$(echo -e "$OUTPUT" | grep "$NAMESPACE:$USERNAME" | wc -l)

  if [ "${EXISTS}" -ne "0" ]; then
      exit 2
  fi

  if [ "${EXIT_CODE}" -ne "0" ]; then
      exit 1
  fi
}

cleanup_user_success() {
  echo "cleanup_user_success()......"
  cleanup_user 0 spark $NAMESPACE
}

cleanup_user_failure() {
  echo "cleanup_user_failure()......"
  cleanup_user 1 spark $NAMESPACE
}



teardown_test_pod() {
  kubectl logs testpod-admin -n $NAMESPACE 
  kubectl logs testpod -n $NAMESPACE 
  kubectl logs -l spark-version=3.4.2 -n $NAMESPACE 
  kubectl -n $NAMESPACE delete pod $ADMIN_POD_NAME
}

run_example_job_in_pod() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl -n $NAMESPACE get pods --sort-by=.metadata.creationTimestamp | grep driver | tail -n 1 | cut -d' ' -f1)
  NAMESPACE=$1
  USERNAME=$2

  kubectl -n $NAMESPACE exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ 1000'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_PODS=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver )
  DRIVER_JOB=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  logs=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE})
  echo "logs: $logs"

  lines=$(echo $logs | grep 'task 0.0' | wc -l)
  echo "Number of lines $lines"
  if [ "$lines" -eq 0 ]; then
    echo "Zero lines in the logs... something wrong"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
}

setup_s3_properties_in_pod(){
  # Setup S3 related Spark properties in the service account inside the pod

  kubectl -n $NAMESPACE exec testpod -- \
      env \
        UU="$SERVICE_ACCOUNT" \
        NN="$NAMESPACE" \
        ACCESS_KEY="$(get_s3_access_key)" \
        SECRET_KEY="$(get_s3_secret_key)" \
        S3_ENDPOINT="$(get_s3_endpoint)" \
        BUCKET="$S3_BUCKET" \
      /bin/bash -c '\
        spark-client.service-account-registry add-config \
        --username $UU --namespace $NN \
        --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
        --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
        --conf spark.hadoop.fs.s3a.path.style.access=true \
        --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
        --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
        --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
        --conf spark.sql.warehouse.dir=s3a://$BUCKET/warehouse \
        --conf spark.sql.catalog.local.warehouse=s3a://$BUCKET/warehouse'
}

setup_azure_storage_properties_in_pod(){
  # Setup Azure Storage related Spark properties in the service account inside the pod

  warehouse_path=$(construct_resource_uri $AZURE_CONTAINER warehouse abfss)

  kubectl -n $NAMESPACE exec testpod -- \
      env \
        UU="$SERVICE_ACCOUNT" \
        NN="$NAMESPACE" \
        ACCOUNT_NAME="$(get_azure_storage_account_name)" \
        SECRET_KEY="$(get_azure_storage_secret_key)" \
        WAREHOUSE="$warehouse_path" \
      /bin/bash -c '\
        spark-client.service-account-registry add-config \
        --username $UU --namespace $NN \
        --conf spark.hadoop.fs.azure.account.key.$ACCOUNT_NAME.dfs.core.windows.net=$SECRET_KEY \
        --conf spark.sql.warehouse.dir=$WAREHOUSE \
        --conf spark.sql.catalog.local.warehouse=$WAREHOUSE'
}


test_iceberg_example_in_pod(){
  # Test Iceberg integration in Charmed Spark Rock
  #
  # Arguments:
  # $1: The path of the script in the cloud

  # Number of rows that are to be inserted during the test.
  NUM_ROWS_TO_INSERT="4"
  script_path=$1

  # Number of driver pods that exist in the namespace already.
  PREVIOUS_DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # Submit the job from inside 'testpod'
  kubectl -n $NAMESPACE exec testpod -- \
      env \
        UU="$USERNAME" \
        NN="$NAMESPACE" \
        IM="$(spark_image)" \
        NUM_ROWS="$NUM_ROWS_TO_INSERT" \
        SCRIPT="$script_path" \
      /bin/bash -c '\
        spark-client.spark-submit \
        --username $UU --namespace $NN \
        --conf spark.kubernetes.driver.request.cores=100m \
        --conf spark.kubernetes.executor.request.cores=100m \
        --conf spark.kubernetes.container.image=$IM \
        --conf spark.jars.ivy=/tmp \
        --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
        --conf spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog \
        --conf spark.sql.catalog.spark_catalog.type=hive \
        --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
        --conf spark.sql.catalog.local.type=hadoop \
        --conf spark.sql.defaultCatalog=local \
        $SCRIPT -n $NUM_ROWS'

  # Number of driver pods after the job is completed.
  DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # If the number of driver pods is same as before, job has not been run at all!
  if [[ "${PREVIOUS_DRIVER_PODS_COUNT}" == "${DRIVER_PODS_COUNT}" ]]
  then
    echo "ERROR: Sample job has not run!"
    return 1
  fi

  # Find the ID of the driver pod that ran the job.
  # tail -n 1       => Filter out the last line
  # cut -d' ' -f1   => Split by spaces and pick the first part
  DRIVER_POD_ID=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep test-iceberg-.*-driver | tail -n 1 | cut -d' ' -f1)

  # Filter out the output log line
  OUTPUT_LOG_LINE=$(kubectl logs ${DRIVER_POD_ID} -n ${NAMESPACE} | grep 'Number of rows inserted:' )

  # Fetch out the number of rows inserted
  # rev             => Reverse the string
  # cut -d' ' -f1   => Split by spaces and pick the first part
  # rev             => Reverse the string back
  NUM_ROWS_INSERTED=$(echo $OUTPUT_LOG_LINE | rev | cut -d' ' -f1 | rev)

  if [ "${NUM_ROWS_INSERTED}" != "${NUM_ROWS_TO_INSERT}" ]; then
      echo "ERROR: ${NUM_ROWS_TO_INSERT} were supposed to be inserted. Found ${NUM_ROWS_INSERTED} rows. Aborting with exit code 1."
      return 1
  fi

  return 0
}


test_iceberg_example_in_pod_using_s3(){
  # Test Iceberg integration in Charmed Spark Rock using S3

  # First create S3 bucket named 'spark'
  create_s3_bucket $S3_BUCKET

  # Now, setup S3 properties in service account inside the pod
  setup_s3_properties_in_pod 

  # Copy 'test-iceberg.py' script to 'spark' bucket
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/test-iceberg.py
  script_path="s3a://$S3_BUCKET/test-iceberg.py"

  test_iceberg_example_in_pod $script_path 
  return_value=$?

  delete_s3_bucket $S3_BUCKET

  if [ $return_value -eq 1 ]; then
    exit 1
  fi
}


test_iceberg_example_in_pod_using_abfss(){
  # Test Iceberg integration in Charmed Spark Rock with Azure Storage

  # First create an Azure Storage container
  create_azure_container $AZURE_CONTAINER

  # Now, setup Azure Storage properties in service account inside the pod
  setup_azure_storage_properties_in_pod 

  # Copy 'test-iceberg.py' script to the Azure Storage container
  copy_file_to_azure_container $AZURE_CONTAINER ./tests/integration/resources/test-iceberg.py
  script_path=$(construct_resource_uri $AZURE_CONTAINER test-iceberg.py abfss)

  test_iceberg_example_in_pod $script_path
  return_value=$?

  delete_azure_container $AZURE_CONTAINER

  if [ $return_value -eq 1 ]; then
    exit 1
  fi
}


run_example_job_in_pod_with_pod_templates() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl -n $NAMESPACE get pods --sort-by=.metadata.creationTimestamp | grep driver | tail -n 1 | cut -d' ' -f1)

  NAMESPACE=$1
  USERNAME=$2
  kubectl -n $NAMESPACE exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --conf spark.kubernetes.driver.podTemplateFile=/etc/spark/conf/podTemplate.yaml \
                  --conf spark.kubernetes.executor.podTemplateFile=/etc/spark/conf/podTemplate.yaml \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ 100'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_PODS=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver )
  DRIVER_JOB=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)
  echo "DRIVER JOB: $DRIVER_JOB"

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi
  DRIVER_JOB_LABEL=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} -lproduct=charmed-spark | grep driver | tail -n 1 | cut -d' ' -f1)
  echo "DRIVER JOB_LABEL: $DRIVER_JOB_LABEL"
  if [[ "${DRIVER_JOB}" != "${DRIVER_JOB_LABEL}" ]]
  then
    echo "ERROR: Label not present... Error in the application of the template!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
}


run_example_job_in_pod_with_metrics() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"
  LOG_FILE="/tmp/server.log"
  SERVER_PORT=9091
  PREVIOUS_JOB=$(kubectl -n $NAMESPACE get pods --sort-by=.metadata.creationTimestamp | grep driver | tail -n 1 | cut -d' ' -f1)
  # start simple http server
  python3 tests/integration/resources/test_web_server.py $SERVER_PORT > $LOG_FILE &
  HTTP_SERVER_PID=$!
  # get ip address
  IP_ADDRESS=$(hostname -I | cut -d ' ' -f 1)
  echo "IP: $IP_ADDRESS"
  NAMESPACE=$1
  USERNAME=$2
  kubectl -n $NAMESPACE exec testpod -- env PORT="$SERVER_PORT" IP="$IP_ADDRESS" UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --conf spark.metrics.conf.*.sink.prometheus.pushgateway-address="$IP:$PORT" \
                  --conf spark.metrics.conf.*.sink.prometheus.class=org.apache.spark.banzaicloud.metrics.sink.PrometheusSink \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ 1000'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_PODS=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver )
  DRIVER_JOB=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
  # check that metrics are sent and stop the http server
  echo "Number of POST done: $(wc -l $LOG_FILE)"
  # kill http server
  kill $HTTP_SERVER_PID
  validate_metrics $LOG_FILE
}


run_example_job_in_pod_with_log_forwarding() {
  NAMESPACE=${1-$NAMESPACE}
  USERNAME=${2-spark}
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl -n $NAMESPACE get pods --sort-by=.metadata.creationTimestamp | grep driver | tail -n 1 | cut -d' ' -f1)
  # start simple http server
  LOG_FILE="/tmp/server-loki.log"
  SERVER_PORT=9091
  python3 tests/integration/resources/test_web_server.py $SERVER_PORT > $LOG_FILE &
  HTTP_SERVER_PID=$!
  # get ip address
  IP_ADDRESS=$(hostname -I | cut -d ' ' -f 1)
  echo "IP: $IP_ADDRESS"

  kubectl -n $NAMESPACE exec testpod -- env PORT="$SERVER_PORT" IP="$IP_ADDRESS" UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --conf spark.executorEnv.LOKI_URL="http://$IP:$PORT" \
                  --conf spark.kubernetes.driverEnv.LOKI_URL="http://$IP:$PORT" \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ 1000'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_PODS=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver )
  DRIVER_JOB=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
  validate_logs $LOG_FILE

  # kill http server
  kill $HTTP_SERVER_PID
}


run_example_job_with_error_in_pod() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl -n $NAMESPACE get pods --sort-by=.metadata.creationTimestamp | grep driver | tail -n 1 | cut -d' ' -f1)
  NAMESPACE=$1
  USERNAME=$2

  kubectl -n $NAMESPACE exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ -1'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_PODS=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver )
  DRIVER_JOB=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  res=$(kubectl logs $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1) -n ${NAMESPACE} | grep 'Exception in thread' | wc -l)
  echo -e "Number of errors: \n ${res}"
  if [ "${res}" != "1" ]; then
      echo "ERROR: Error is not captured."
      exit 1
  fi
  status=$(kubectl get pod $(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1) -n ${NAMESPACE} | tail -1 | cut -d " " -f 9)
  if [ "${status}" = "Completed" ]; then
      echo "ERROR: Status should not be set to Completed."
      exit 1
  fi
  if [ "${status}" = "Error" ]; then
      echo "Status is correctly set to ERROR!"
  fi

}

test_example_job_in_pod_with_errors() {
  run_example_job_with_error_in_pod $NAMESPACE spark
}


test_example_job_in_pod_with_templates() {
  run_example_job_in_pod_with_pod_templates $NAMESPACE spark
}


test_example_job_in_pod() {
  run_example_job_in_pod $NAMESPACE spark
}

test_example_job_in_pod_with_metrics() {
  run_example_job_in_pod_with_metrics $NAMESPACE spark
}



run_spark_shell_in_pod() {
  echo "run_spark_shell_in_pod ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  SPARK_SHELL_COMMANDS=$(cat ./tests/integration/resources/test-spark-shell.scala)

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"

  echo -e "$(kubectl -n $NAMESPACE exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" CMDS="$SPARK_SHELL_COMMANDS" IM="$(spark_image)" /bin/bash -c 'echo "$CMDS" | spark-client.spark-shell --username $UU --namespace $NN --conf spark.kubernetes.container.image=$IM')" > spark-shell.out

  pi=$(cat spark-shell.out  | grep "^Pi is roughly" | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark-shell Pi Job Output: \n ${pi}"
  rm spark-shell.out
  validate_pi_value $pi
}

test_spark_shell_in_pod() {
  run_spark_shell_in_pod $NAMESPACE spark
}

run_spark_sql_in_pod(){
  # Test Spark SQL inside a pod that runs charmed spark rock.
  #
  # Arguments:
  # $1: The path to the file that contains the lines to be passed to Spark SQL

  sql_script_file=$1

  SPARK_SQL_COMMANDS=$(cat $sql_script_file)
  echo -e "$(kubectl -n $NAMESPACE exec testpod -- \
    env \
      UU="$SERVICE_ACCOUNT" \
      NN="$NAMESPACE" \
      CMDS="$SPARK_SQL_COMMANDS" \
      IM=$(spark_image) \
      ACCESS_KEY=$(get_s3_access_key) \
      SECRET_KEY=$(get_s3_secret_key) \
      S3_ENDPOINT=$(get_s3_endpoint) \
      BUCKET="$S3_BUCKET" \
    /bin/bash -c 'echo "$CMDS" | spark-client.spark-sql \
      --username $UU --namespace $NN \
      --conf spark.kubernetes.container.image=$IM \
      --conf spark.driver.extraJavaOptions='-Dderby.system.home=/tmp/derby' \
    ')" > spark-sql.out

  num_rows_inserted=$(cat spark-sql.out  | grep "^Inserted Rows:" | rev | cut -d' ' -f1 | rev )
  echo -e "${num_rows_inserted} rows were inserted."
  rm spark-sql.out
  if [ "${num_rows_inserted}" != "3" ]; then
      echo "ERROR: Testing spark-sql failed. ${num_rows_inserted} out of 3 rows were inserted. Aborting with exit code 1."
      return 1
  fi

  return 0
}

test_spark_sql_in_pod_using_s3() {
  # Test Spark SQL with S3 as object storage

  create_s3_bucket $S3_BUCKET
  setup_s3_properties_in_pod

  run_spark_sql_in_pod ./tests/integration/resources/test-spark-sql.sql
  return_value=$?

  delete_s3_bucket $S3_BUCKET

  if [ $return_value -eq 1 ]; then
    exit 1
  fi
}

test_spark_sql_in_pod_using_abfss() {
  # Test Spark SQL with Azure Blob as object storage (using abfss protocol)
  create_azure_container $AZURE_CONTAINER
  setup_azure_storage_properties_in_pod

  run_spark_sql_in_pod ./tests/integration/resources/test-spark-sql.sql
  return_value=$?

  delete_azure_container $S3_BUCKET

  if [ $return_value -eq 1 ]; then
    exit 1
  fi
}


run_pyspark_in_pod() {
  echo "run_pyspark_in_pod ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  PYSPARK_COMMANDS=$(cat ./tests/integration/resources/compute_pi.py)

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"

  echo -e "$(kubectl -n $NAMESPACE exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" CMDS="$PYSPARK_COMMANDS" IM="$(spark_image)" /bin/bash -c 'echo "$CMDS" | spark-client.pyspark --username $UU --namespace $NN --conf spark.kubernetes.container.image=$IM')" > pyspark.out

  cat pyspark.out
  pi=$(cat pyspark.out  | grep "Pi is roughly" | tail -n 1 | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Pyspark Pi Job Output: \n ${pi}"
  rm pyspark.out
  validate_pi_value $pi
}

test_pyspark_in_pod() {
  run_pyspark_in_pod $NAMESPACE spark
}

cleanup_user_failure_in_pod() {
  teardown_test_pod
  cleanup_user_failure
}


echo -e "##################################"
echo -e "SETUP TEST POD"
echo -e "##################################"
kubectl create namespace $NAMESPACE
setup_admin_pod $ADMIN_POD_NAME $(spark_image) $NAMESPACE

echo -e "##################################"
echo -e "RUN EXAMPLE JOB"
echo -e "##################################"

(setup_user_context && test_example_job_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN SPARK SHELL IN POD"
echo -e "##################################"

(setup_user_context && test_spark_shell_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN PYSPARK IN POD"
echo -e "##################################"

(setup_user_context && test_pyspark_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN SPARK SQL IN POD (Using S3 Object Storage)"
echo -e "##################################"

(setup_user_context && test_spark_sql_in_pod_using_s3 && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN SPARK SQL IN POD (Using Azure Storage ABFSS)"
echo -e "##################################"

(setup_user_context && test_spark_sql_in_pod_using_abfss && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN EXAMPLE JOB WITH POD TEMPLATE"
echo -e "##################################"

(setup_user_context && test_example_job_in_pod_with_templates && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "########################################"
echo -e "RUN EXAMPLE JOB WITH PROMETHEUS METRICS"
echo -e "########################################"

(setup_user_context && test_example_job_in_pod_with_metrics && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "########################################"
echo -e "RUN EXAMPLE JOB WITH LOG FORWARDING"
echo -e "########################################"

(setup_user_context && run_example_job_in_pod_with_log_forwarding && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "########################################"
echo -e "RUN EXAMPLE JOB WITH ERRORS"
echo -e "########################################"

(setup_user_context && test_example_job_in_pod_with_errors && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN EXAMPLE THAT USES ICEBERG LIBRARIES"
echo -e "##################################"

(setup_user_context && test_iceberg_example_in_pod_using_s3 && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN EXAMPLE THAT USES AZURE STORAGE"
echo -e "##################################"

(setup_user_context && test_iceberg_example_in_pod_using_abfss && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "TEARDOWN TEST POD"
echo -e "##################################"

teardown_test_pod
kubectl delete namespace $NAMESPACE

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
