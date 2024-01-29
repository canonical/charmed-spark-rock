#!/bin/bash

get_spark_version(){
  SPARK_VERSION=$(yq '(.version)' rockcraft.yaml)
  echo "$SPARK_VERSION"
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

test_restricted_account() {

  kubectl config set-context spark-context --namespace=tests --cluster=prod --user=spark

  run_example_job tests spark
}

setup_user() {
  echo "setup_user() ${1} ${2} ${3}"

  USERNAME=$1
  NAMESPACE=$2

  kubectl create namespace ${NAMESPACE}

  if [ "$#" -gt 2 ]
  then
    CONTEXT=$3 
    kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" CX="$CONTEXT" \
                  /bin/bash -c 'spark-client.service-account-registry create --context $CX --username $UU --namespace $NN' 
  else
    kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" \
                  /bin/bash -c 'spark-client.service-account-registry create --username $UU --namespace $NN' 
  fi

}

setup_user_admin_context() {
  setup_user spark tests
}

setup_user_restricted_context() {
  setup_user spark tests microk8s
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" \
                  /bin/bash -c 'spark-client.service-account-registry delete --username $UU --namespace $NN'  

  OUTPUT=$(kubectl exec testpod -- /bin/bash -c 'spark-client.service-account-registry list')

  EXISTS=$(echo -e "$OUTPUT" | grep "$NAMESPACE:$USERNAME" | wc -l)

  if [ "${EXISTS}" -ne "0" ]; then
      exit 2
  fi

  kubectl delete namespace ${NAMESPACE}

  if [ "${EXIT_CODE}" -ne "0" ]; then
      exit 1
  fi
}

cleanup_user_success() {
  echo "cleanup_user_success()......"
  cleanup_user 0 spark tests
}

cleanup_user_failure() {
  echo "cleanup_user_failure()......"
  cleanup_user 1 spark tests
}

setup_test_pod() {
  kubectl apply -f ./tests/integration/resources/testpod.yaml

  SLEEP_TIME=1
  for i in {1..5}
  do
    pod_status=$(kubectl get pod testpod | awk '{ print $3 }' | tail -n 1)
    echo $pod_status
    if [ "${pod_status}" == "Running" ]
    then
        echo "testpod is Running now!"
        break
    elif [ "${i}" -le "5" ]
    then
        echo "Waiting for the pod to come online..."
        sleep $SLEEP_TIME
    else
        echo "testpod did not come up. Test Failed!"
        exit 3
    fi
    SLEEP_TIME=$(expr $SLEEP_TIME \* 2);
  done

  MY_KUBE_CONFIG=$(cat /home/${USER}/.kube/config)
  TEST_POD_TEMPLATE=$(cat tests/integration/resources/podTemplate.yaml)

  kubectl exec testpod -- /bin/bash -c 'mkdir -p ~/.kube'
  kubectl exec testpod -- env KCONFIG="$MY_KUBE_CONFIG" /bin/bash -c 'echo "$KCONFIG" > ~/.kube/config'
  kubectl exec testpod -- /bin/bash -c 'cat ~/.kube/config'
  kubectl exec testpod -- /bin/bash -c 'cp -r /opt/spark/python /var/lib/spark/'
  kubectl exec testpod -- env PTEMPLATE="$TEST_POD_TEMPLATE" /bin/bash -c 'echo "$PTEMPLATE" > /etc/spark/conf/podTemplate.yaml'
}

teardown_test_pod() {
  kubectl delete pod testpod
}

run_example_job_in_pod() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl get pods -n ${NAMESPACE}| grep driver | tail -n 1 | cut -d' ' -f1)
  NAMESPACE=$1
  USERNAME=$2

  kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ 1000'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_JOB=$(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
}

get_s3_access_key(){
  kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d
}

get_s3_secret_key(){
  kubectl get secret -n minio-operator microk8s-user-1 -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d
}

get_s3_endpoint(){
  kubectl get service minio -n minio-operator -o jsonpath='{.spec.clusterIP}'
}

create_s3_bucket(){
  S3_ENDPOINT=$(get_s3_endpoint)
  BUCKET_NAME=$1
  aws --endpoint-url "http://$S3_ENDPOINT" s3api create-bucket --bucket "$BUCKET_NAME"
  echo "Created S3 bucket ${BUCKET_NAME}"
}

delete_s3_bucket(){
  S3_ENDPOINT=$(get_s3_endpoint)
  BUCKET_NAME=$1
  aws --endpoint-url "http://$S3_ENDPOINT" s3 rb "s3://$BUCKET_NAME" --force
  echo "Deleted S3 bucket ${BUCKET_NAME}"
}

copy_file_to_s3_bucket(){
  BUCKET_NAME=$1
  FILE_PATH=$2
  BASE_NAME=$(basename "$FILE_PATH")
  aws --endpoint-url "http://$S3_ENDPOINT" s3 cp $FILE_PATH s3://"$BUCKET_NAME"/"$BASE_NAME"
  echo "Copied file ${FILE_PATH} to S3 bucket ${BUCKET_NAME}"
}

test_iceberg_example_in_pod(){
  create_s3_bucket spark
  copy_file_to_s3_bucket spark ./tests/integration/resources/test-iceberg.py

  NAMESPACE="tests"
  USERNAME="spark"
  NUM_ROWS_TO_INSERT="4"
  PREVIOUS_DRIVER_PODS_COUNT=$(kubectl get pods -n ${NAMESPACE} | grep driver | wc -l)

  kubectl exec testpod -- \
      env \
        UU="$USERNAME" \
        NN="$NAMESPACE" \
        IM="$(spark_image)" \
        NUM_ROWS="$NUM_ROWS_TO_INSERT" \
        ACCESS_KEY="$(get_s3_access_key)" \
        SECRET_KEY="$(get_s3_secret_key)" \
        S3_ENDPOINT="$(get_s3_endpoint)" \
      /bin/bash -c '\
        spark-client.spark-submit \
        --username $UU --namespace $NN \
        --conf spark.kubernetes.driver.request.cores=100m \
        --conf spark.kubernetes.executor.request.cores=100m \
        --conf spark.kubernetes.container.image=$IM \
        --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
        --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
        --conf spark.hadoop.fs.s3a.path.style.access=true \
        --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
        --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
        --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
        --conf spark.jars.ivy=/tmp \
        --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
        --conf spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog \
        --conf spark.sql.catalog.spark_catalog.type=hive \
        --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
        --conf spark.sql.catalog.local.type=hadoop \
        --conf spark.sql.catalog.local.warehouse=s3a://spark/warehouse \
        --conf spark.sql.defaultCatalog=local \
        s3a://spark/test-iceberg.py -n $NUM_ROWS'
  
  delete_s3_bucket spark
  DRIVER_PODS_COUNT=$(kubectl get pods -n ${NAMESPACE} | grep driver | wc -l)

  if [[ "${PREVIOUS_DRIVER_PODS_COUNT}" == "${DRIVER_PODS_COUNT}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  DRIVER_POD_ID=$(kubectl get pods -n ${NAMESPACE} | grep test-iceberg-.*-driver | tail -n 1 | cut -d' ' -f1)
  OUTPUT_LOG_LINE=$(kubectl logs ${DRIVER_POD_ID} -n ${NAMESPACE} | grep 'Number of rows inserted:' )
  NUM_ROWS_INSERTED=$(echo $OUTPUT_LOG_LINE | rev | cut -d' ' -f1 | rev)

  if [ "${NUM_ROWS_INSERTED}" != "${NUM_ROWS_TO_INSERT}" ]; then
      echo "ERROR: ${NUM_ROWS_TO_INSERT} were supposed to be inserted. Found ${NUM_ROWS_INSERTED} rows. Aborting with exit code 1."
      exit 1
  fi

}

run_example_job_in_pod_with_pod_templates() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl get pods | grep driver | tail -n 1 | cut -d' ' -f1)

  NAMESPACE=$1
  USERNAME=$2
  kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
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
  DRIVER_JOB=$(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)
  echo "DRIVER JOB: $DRIVER_JOB"

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi
  DRIVER_JOB_LABEL=$(kubectl get pods -n ${NAMESPACE} -lproduct=charmed-spark | grep driver | tail -n 1 | cut -d' ' -f1)
  echo "DRIVER JOB_LABEL: $DRIVER_JOB_LABEL"
  if [[ "${DRIVER_JOB}" != "${DRIVER_JOB_LABEL}" ]]
  then
    echo "ERROR: Label not present... Error in the application of the template!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
}


run_example_job_in_pod_with_metrics() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"
  LOG_FILE="/tmp/server.log"
  SERVER_PORT=9091
  PREVIOUS_JOB=$(kubectl get pods | grep driver | tail -n 1 | cut -d' ' -f1)
  # start simple http server
  python3 tests/integration/resources/test_web_server.py $SERVER_PORT > $LOG_FILE &
  HTTP_SERVER_PID=$!
  # get ip address
  IP_ADDRESS=$(hostname -I | cut -d ' ' -f 1)
  echo "IP: $IP_ADDRESS"
  NAMESPACE=$1
  USERNAME=$2
  kubectl exec testpod -- env PORT="$SERVER_PORT" IP="$IP_ADDRESS" UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
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
  DRIVER_JOB=$(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"
  pi=$(kubectl logs $(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)  -n ${NAMESPACE} | grep 'Pi is roughly' | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark Pi Job Output: \n ${pi}"

  validate_pi_value $pi
  # check that metrics are sent and stop the http server
  echo "Number of POST done: $(wc -l $LOG_FILE)"
  # kill http server
  kill $HTTP_SERVER_PID
  validate_metrics $LOG_FILE
}


run_example_job_with_error_in_pod() {
  SPARK_EXAMPLES_JAR_NAME="spark-examples_2.12-$(get_spark_version).jar"

  PREVIOUS_JOB=$(kubectl get pods | grep driver | tail -n 1 | cut -d' ' -f1)
  NAMESPACE=$1
  USERNAME=$2

  kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" JJ="$SPARK_EXAMPLES_JAR_NAME" IM="$(spark_image)" \
                  /bin/bash -c 'spark-client.spark-submit \
                  --username $UU --namespace $NN \
                  --conf spark.kubernetes.driver.request.cores=100m \
                  --conf spark.kubernetes.executor.request.cores=100m \
                  --conf spark.kubernetes.container.image=$IM \
                  --class org.apache.spark.examples.SparkPi \
                  local:///opt/spark/examples/jars/$JJ -1'

  # kubectl --kubeconfig=${KUBE_CONFIG} get pods
  DRIVER_JOB=$(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  if [[ "${DRIVER_JOB}" == "${PREVIOUS_JOB}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Check job output
  res=$(kubectl logs $(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1) -n ${NAMESPACE} | grep 'Exception in thread' | wc -l)
  echo -e "Number of errors: \n ${res}"
  if [ "${res}" != "1" ]; then
      echo "ERROR: Error is not captured."
      exit 1
  fi
  status=$(kubectl get pod $(kubectl get pods -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1) -n ${NAMESPACE} | tail -1 | cut -d " " -f 9)
  if [ "${status}" = "Completed" ]; then
      echo "ERROR: Status should not be set to Completed."
      exit 1
  fi
  if [ "${status}" = "Error" ]; then
      echo "Status is correctly set to ERROR!"
  fi

}

test_example_job_in_pod_with_errors() {
  run_example_job_with_error_in_pod tests spark
}


test_example_job_in_pod_with_templates() {
  run_example_job_in_pod_with_pod_templates tests spark
}


test_example_job_in_pod() {
  run_example_job_in_pod tests spark
}

test_example_job_in_pod_with_metrics() {
  run_example_job_in_pod_with_metrics tests spark
}



run_spark_shell_in_pod() {
  echo "run_spark_shell_in_pod ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  SPARK_SHELL_COMMANDS=$(cat ./tests/integration/resources/test-spark-shell.scala)

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"

  echo -e "$(kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" CMDS="$SPARK_SHELL_COMMANDS" IM="$(spark_image)" /bin/bash -c 'echo "$CMDS" | spark-client.spark-shell --username $UU --namespace $NN --conf spark.kubernetes.container.image=$IM')" > spark-shell.out

  pi=$(cat spark-shell.out  | grep "^Pi is roughly" | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Spark-shell Pi Job Output: \n ${pi}"
  rm spark-shell.out
  validate_pi_value $pi
}

test_spark_shell_in_pod() {
  run_spark_shell_in_pod tests spark
}

run_pyspark_in_pod() {
  echo "run_pyspark_in_pod ${1} ${2}"

  NAMESPACE=$1
  USERNAME=$2

  PYSPARK_COMMANDS=$(cat ./tests/integration/resources/test-pyspark.py)

  # Check job output
  # Sample output
  # "Pi is roughly 3.13956232343"

  echo -e "$(kubectl exec testpod -- env UU="$USERNAME" NN="$NAMESPACE" CMDS="$PYSPARK_COMMANDS" IM="$(spark_image)" /bin/bash -c 'echo "$CMDS" | spark-client.pyspark --username $UU --namespace $NN --conf spark.kubernetes.container.image=$IM')" > pyspark.out

  cat pyspark.out
  pi=$(cat pyspark.out  | grep "Pi is roughly" | tail -n 1 | rev | cut -d' ' -f1 | rev | cut -c 1-3)
  echo -e "Pyspark Pi Job Output: \n ${pi}"
  rm pyspark.out
  validate_pi_value $pi
}

test_pyspark_in_pod() {
  run_pyspark_in_pod tests spark
}

test_restricted_account_in_pod() {

  kubectl config set-context spark-context --namespace=tests --cluster=prod --user=spark

  run_example_job_in_pod tests spark
}

cleanup_user_failure_in_pod() {
  teardown_test_pod
  cleanup_user_failure
}

echo -e "##################################"
echo -e "SETUP TEST POD"
echo -e "##################################"

setup_test_pod

# echo -e "##################################"
# echo -e "RUN EXAMPLE JOB"
# echo -e "##################################"

# (setup_user_admin_context && test_example_job_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

# echo -e "##################################"
# echo -e "RUN SPARK SHELL IN POD"
# echo -e "##################################"

# (setup_user_admin_context && test_spark_shell_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

# echo -e "##################################"
# echo -e "RUN PYSPARK IN POD"
# echo -e "##################################"

# (setup_user_admin_context && test_pyspark_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

# echo -e "##################################"
# echo -e "RUN EXAMPLE JOB WITH POD TEMPLATE"
# echo -e "##################################"

# (setup_user_admin_context && test_example_job_in_pod_with_templates && cleanup_user_success) || cleanup_user_failure_in_pod

# echo -e "########################################"
# echo -e "RUN EXAMPLE JOB WITH PROMETHEUS METRICS"
# echo -e "########################################"

# (setup_user_admin_context && test_example_job_in_pod_with_metrics && cleanup_user_success) || cleanup_user_failure_in_pod


# echo -e "########################################"
# echo -e "RUN EXAMPLE JOB WITH ERRORS"
# echo -e "########################################"

# (setup_user_admin_context && test_example_job_in_pod_with_errors && cleanup_user_success) || cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "RUN EXAMPLE THAT USES ICEBERG LIBRARIES"
echo -e "##################################"

(setup_user_admin_context && test_iceberg_example_in_pod && cleanup_user_success) #|| cleanup_user_failure_in_pod

echo -e "##################################"
echo -e "TEARDOWN TEST POD"
echo -e "##################################"

# teardown_test_pod

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"

sleep 10000