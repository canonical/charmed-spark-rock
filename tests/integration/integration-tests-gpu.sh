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

# Global variables
NAMESPACE=tests
SERVICE_ACCOUNT=spark
ADMIN_POD_NAME=testpod-admin
S3_BUCKET=spark-$(uuidgen)

get_spark_version(){
  # Fetch Spark version from rockcraft.yaml
  SPARK_VERSION=$(cat images/charmed-spark/rockcraft.yaml | yq '(.version)')

  GPU_VERSION=$(cat images/metadata.yaml | yq .flavours.gpu.version)

  echo "${SPARK_VERSION}-${GPU_VERSION}"
}


spark_image(){
  echo "ghcr.io/canonical/test-charmed-spark-gpu:$(get_spark_version)"
}


setup_user() {
  echo "setup_user() ${1} ${2}"


  USERNAME=$1
  NAMESPACE=$2

  create_serviceaccount_using_pod $USERNAME $NAMESPACE $ADMIN_POD_NAME

  IMAGE=$(spark_image)

  # Create the pod with the Spark service account
  cat ./tests/integration/resources/testpod.yaml | yq ea '.spec.serviceAccountName = '\"${USERNAME}\"' | .spec.containers[0].image='\"${IMAGE}\" | \
    kubectl -n tests apply -f -

  wait_for_pod testpod $NAMESPACE

  TEST_POD_TEMPLATE=$(cat tests/integration/resources/podTemplate.yaml)
  TEST_GPU_TEMPLATE=$(cat tests/integration/resources/gpu_executor_template.yaml)

  kubectl -n $NAMESPACE exec testpod -- /bin/bash -c 'cp -r /opt/spark/python /var/lib/spark/'
  kubectl -n $NAMESPACE exec testpod -- env PTEMPLATE="$TEST_POD_TEMPLATE" /bin/bash -c 'echo "$PTEMPLATE" > /etc/spark/conf/podTemplate.yaml'
  kubectl -n $NAMESPACE exec testpod -- env PTEMPLATE="$TEST_GPU_TEMPLATE" /bin/bash -c 'echo "$PTEMPLATE" > /etc/spark/conf/gpu_executor_template.yaml'
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
  kubectl -n $NAMESPACE delete pod testpod
  kubectl -n $NAMESPACE delete pod testpod-admin

  kubectl delete namespace $NAMESPACE
}


run_test_gpu_example_in_pod(){
  # Test Spark-rapids integration in Charmed Spark Rock

  # First create S3 bucket named 'spark'
  create_s3_bucket $S3_BUCKET

  # Copy 'test-iceberg.py' script to 'spark' bucket
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/test-gpu-simple.py

#  IMAGE="test-image"
  # Number of driver pods that exist in the namespace already.
  PREVIOUS_DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # Submit the job from inside 'testpod'
  kubectl -n $NAMESPACE exec testpod -- \
      env \
        UU="$SERVICE_ACCOUNT" \
        NN="$NAMESPACE" \
        ACCESS_KEY="$(get_s3_access_key)" \
        SECRET_KEY="$(get_s3_secret_key)" \
        S3_ENDPOINT="$(get_s3_endpoint)" \
        BUCKET="$S3_BUCKET" \
        IM="$(spark_image)" \
      /bin/bash -c '\
        spark-client.spark-submit \
        --username $UU \
        --namespace $NN \
        --conf spark.kubernetes.driver.request.cores=100m \
        --conf spark.kubernetes.executor.request.cores=100m \
        --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
        --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
        --conf spark.hadoop.fs.s3a.path.style.access=true \
        --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
        --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
        --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
        --conf spark.executor.instances=1 \
        --conf spark.executor.resource.gpu.amount=1 \
        --conf spark.executor.memory=4G \
        --conf spark.executor.cores=1 \
        --conf spark.task.cpus=1 \
        --conf spark.task.resource.gpu.amount=1 \
        --conf spark.rapids.memory.pinnedPool.size=1G \
        --conf spark.executor.memoryOverhead=1G \
        --conf spark.sql.files.maxPartitionBytes=512m \
        --conf spark.sql.shuffle.partitions=10 \
        --conf spark.plugins=com.nvidia.spark.SQLPlugin \
        --conf spark.executor.resource.gpu.discoveryScript=/opt/getGpusResources.sh \
        --conf spark.executor.resource.gpu.vendor=nvidia.com \
        --conf spark.kubernetes.container.image=$IM \
        --driver-memory 2G \
        --conf spark.kubernetes.executor.podTemplateFile=/etc/spark/conf/gpu_executor_template.yaml \
        --conf spark.kubernetes.executor.deleteOnTermination=false \
          s3a://$BUCKET/test-gpu-simple.py'

  # Delete 'spark' bucket
  delete_s3_bucket $S3_BUCKET

  # Number of driver pods after the job is completed.
  DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # If the number of driver pods is same as before, job has not been run at all!
  if [[ "${PREVIOUS_DRIVER_PODS_COUNT}" == "${DRIVER_PODS_COUNT}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Find the ID of the driver pod that ran the job.
  # tail -n 1       => Filter out the last line
  # cut -d' ' -f1   => Split by spaces and pick the first part
  DRIVER_POD_ID=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  # Filter out the output log line
  OUTPUT_LOG_LINE=$(kubectl logs ${DRIVER_POD_ID} -n ${NAMESPACE} | grep 'GpuFilter' )
  echo "output log line: $OUTPUT_LOG_LINE"
  # Fetch out the number of rows with the desired keyword
  NUM_ROWS=$(echo $OUTPUT_LOG_LINE | wc -l)
  echo "number of rows: $NUM_ROWS"
  if [ "${NUM_ROWS}" == 0 ]; then
      echo "ERROR: No GPU enable workflow found. Aborting with exit code 1."
      exit 1
  fi

}

test_gpu_example_in_pod() {
  run_test_gpu_example_in_pod $NAMESPACE spark
}


teardown_test_pod() {
  kubectl logs testpod-admin -n $NAMESPACE 
  kubectl logs testpod -n $NAMESPACE 
  kubectl logs -l spark-version=3.4.2 -n $NAMESPACE 
  kubectl -n $NAMESPACE delete pod testpod
  kubectl -n $NAMESPACE delete pod testpod-admin

  kubectl delete namespace $NAMESPACE
}


run_test_sql_gpu_example_in_pod(){
  # Test Spark-rapids integration in Charmed Spark Rock

  # First create S3 bucket named 'spark'
  create_s3_bucket $S3_BUCKET

  # Copy 'test-iceberg.py' script to 'spark' bucket
  copy_file_to_s3_bucket $S3_BUCKET ./tests/integration/resources/test-gpu-sql.py

  # create data bucket

  create_s3_bucket "data"

  # copy test data
  aws s3 cp ./tests/integration/resources/tpcds/catalog_sales/catalog_sales.parquet s3://data/tpcds/catalog_sales/catalog_sales.parquet
  aws s3 cp ./tests/integration/resources/tpcds/date_dim/date_dim.parquet s3://data/tpcds/date_dim/date_dim.parquet
  aws s3 cp ./tests/integration/resources/tpcds/item/item.parquet s3://data/tpcds/item/item.parquet
  aws s3 cp ./tests/integration/resources/tpcds/store_sales/store_sales.parquet s3://data/tpcds/store_sales/store_sales.parquet
  aws s3 cp ./tests/integration/resources/tpcds/web_sales/web_sales.parquet s3://data/tpcds/web_sales/web_sales.parquet
  aws s3 cp ./tests/integration/resources/tpcds/customer/customer.parquet s3://data/tpcds/customer/customer.parquet

  # Number of driver pods that exist in the namespace already.
  PREVIOUS_DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # Submit the job from inside 'testpod'
  kubectl -n $NAMESPACE exec testpod -- \
      env \
        UU="$SERVICE_ACCOUNT" \
        NN="$NAMESPACE" \
        ACCESS_KEY="$(get_s3_access_key)" \
        SECRET_KEY="$(get_s3_secret_key)" \
        S3_ENDPOINT="$(get_s3_endpoint)" \
        BUCKET="$S3_BUCKET" \
        IM="$(spark_image)" \
      /bin/bash -c '\
        spark-client.spark-submit \
        --username $UU \
        --namespace $NN \
        --conf spark.kubernetes.driver.request.cores=100m \
        --conf spark.kubernetes.executor.request.cores=100m \
        --conf spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider \
        --conf spark.hadoop.fs.s3a.connection.ssl.enabled=false \
        --conf spark.hadoop.fs.s3a.path.style.access=true \
        --conf spark.hadoop.fs.s3a.endpoint=$S3_ENDPOINT \
        --conf spark.hadoop.fs.s3a.access.key=$ACCESS_KEY \
        --conf spark.hadoop.fs.s3a.secret.key=$SECRET_KEY \
        --conf spark.executor.instances=1 \
        --conf spark.executor.resource.gpu.amount=1 \
        --conf spark.executor.memory=4G \
        --conf spark.executor.cores=1 \
        --conf spark.task.cpus=1 \
        --conf spark.task.resource.gpu.amount=1 \
        --conf spark.rapids.memory.pinnedPool.size=1G \
        --conf spark.executor.memoryOverhead=1G \
        --conf spark.sql.files.maxPartitionBytes=512m \
        --conf spark.sql.shuffle.partitions=10 \
        --conf spark.plugins=com.nvidia.spark.SQLPlugin \
        --conf spark.executor.resource.gpu.discoveryScript=/opt/getGpusResources.sh \
        --conf spark.executor.resource.gpu.vendor=nvidia.com \
        --conf spark.kubernetes.container.image=$IM \
        --driver-memory 2G \
        --conf spark.kubernetes.executor.podTemplateFile=/etc/spark/conf/gpu_executor_template.yaml \
        --conf spark.kubernetes.executor.deleteOnTermination=false \
          s3a://$BUCKET/test-gpu-sql.py'

  # Delete 'spark' bucket
  delete_s3_bucket $S3_BUCKET

  # Delete 'data' bucket
  delete_s3_bucket "data"

  # Number of driver pods after the job is completed.
  DRIVER_PODS_COUNT=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | wc -l)

  # If the number of driver pods is same as before, job has not been run at all!
  if [[ "${PREVIOUS_DRIVER_PODS_COUNT}" == "${DRIVER_PODS_COUNT}" ]]
  then
    echo "ERROR: Sample job has not run!"
    exit 1
  fi

  # Find the ID of the driver pod that ran the job.
  # tail -n 1       => Filter out the last line
  # cut -d' ' -f1   => Split by spaces and pick the first part
  DRIVER_POD_ID=$(kubectl get pods --sort-by=.metadata.creationTimestamp -n ${NAMESPACE} | grep driver | tail -n 1 | cut -d' ' -f1)

  # Filter out the output log line
  OUTPUT_LOG_LINE=$(kubectl logs ${DRIVER_POD_ID} -n ${NAMESPACE} | grep "average")
  echo "output log line: $OUTPUT_LOG_LINE"
  # Fetch out the number of rows with the desired keyword
  NUM_ROWS=$(echo $OUTPUT_LOG_LINE | wc -l)
  echo "number of rows: $NUM_ROWS"
  if [ "${NUM_ROWS}" == 0 ]; then
      echo "ERROR: No GPU enable workflow found. Aborting with exit code 1."
      exit 1
  fi

}

test_sql_gpu_example_in_pod() {
  run_test_sql_gpu_example_in_pod $NAMESPACE spark
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
echo -e "RUN EXAMPLE THAT USES GPU"
echo -e "##################################"

(setup_user_context && test_gpu_example_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod


echo -e "##################################"
echo -e "RUN SQL EXAMPLE THAT USES GPU"
echo -e "##################################"

(setup_user_context && test_sql_gpu_example_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod


echo -e "##################################"
echo -e "TEARDOWN TEST POD"
echo -e "##################################"

teardown_test_pod

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
