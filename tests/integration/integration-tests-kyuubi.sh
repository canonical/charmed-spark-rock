#!/bin/bash

# The integration tests are designed to tests that SQL queries can be submitted to Kyuubi and/or shell processes are
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
source ./tests/integration/utils/azure-utils.sh
source ./tests/integration/utils/k8s-utils.sh


# Global Variables
RANDOM_HASH=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
NAMESPACE=tests
SERVICE_ACCOUNT=spark
ADMIN_POD_NAME=testpod-admin
USER_POD_NAME=kyuubi-test
S3_BUCKET=kyuubi-$RANDOM_HASH
AZURE_CONTAINER=$S3_BUCKET

get_spark_version(){
  # Fetch Spark version from images/charmed-spark/rockcraft.yaml
  yq '(.version)' images/charmed-spark/rockcraft.yaml
}


kyuubi_image(){
  # The Kyuubi image that is going to be used for test
  echo "ghcr.io/canonical/test-charmed-spark-kyuubi:$(get_spark_version)"
}


setup_kyuubi_pod_with_s3() {
  # Setup Kyuubi pod for testing, using S3 as object storage
  #
  # Arguments:
  # $1: The service account to be used for creating Kyuubi pod
  # $1: The namespace to be used for creating Kyuubi pod

  # Create service account using the admin pod
  create_serviceaccount_using_pod $SERVICE_ACCOUNT $NAMESPACE $ADMIN_POD_NAME

  image=$(kyuubi_image)

  # Create the pod with the newly created service account
  sed -e "s%<IMAGE>%${image}%g" \
      -e "s/<SERVICE_ACCOUNT>/${SERVICE_ACCOUNT}/g" \
      -e "s/<NAMESPACE>/${NAMESPACE}/g" \
      -e "s/<POD_NAME>/${USER_POD_NAME}/g" \
      ./tests/integration/resources/kyuubi.yaml | \
    kubectl -n tests apply -f -
  
  wait_for_pod $USER_POD_NAME $NAMESPACE

  # Prepare S3 bucket
  create_s3_bucket $S3_BUCKET

  s3_endpoint=$(get_s3_endpoint)
  s3_access_key=$(get_s3_access_key)
  s3_secret_key=$(get_s3_secret_key)

  # Write Spark configs inside the Kyuubi container
  kubectl -n $NAMESPACE exec kyuubi-test -- env IMG="$image"                /bin/bash -c 'echo spark.kubernetes.container.image=$IMG  > /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env NN="$NAMESPACE"             /bin/bash -c 'echo spark.kubernetes.namespace=$NN         >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env UU="$SERVICE_ACCOUNT"       /bin/bash -c 'echo spark.kubernetes.authenticate.driver.serviceAccountName=$UU >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env ENDPOINT="$s3_endpoint"     /bin/bash -c 'echo spark.hadoop.fs.s3a.endpoint=$ENDPOINT >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env ACCESS_KEY="$s3_access_key" /bin/bash -c 'echo spark.hadoop.fs.s3a.access.key=$ACCESS_KEY >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env SECRET_KEY="$s3_secret_key" /bin/bash -c 'echo spark.hadoop.fs.s3a.secret.key=$SECRET_KEY >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test --                                 /bin/bash -c 'echo spark.hadoop.fs.s3a.aws.credentials.provider=org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test --                                 /bin/bash -c 'echo spark.hadoop.fs.s3a.connection.ssl.enabled=false >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test --                                 /bin/bash -c 'echo spark.hadoop.fs.s3a.path.style.access=true       >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env BUCKET="$S3_BUCKET"         /bin/bash -c 'echo spark.sql.warehouse.dir=s3a://$BUCKET/warehouse  >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- env BUCKET="$S3_BUCKET"         /bin/bash -c 'echo spark.kubernetes.file.upload.path=s3a://$BUCKET  >> /etc/spark8t/conf/spark-defaults.conf'

  # Wait some time for the server to be up and running
  sleep 10
}


setup_kyuubi_pod_with_azure_abfss() {
  # Setup Kyuubi pod for testing, using Azure blob storage as object storage and ABFSS as protocol
  #
  # Arguments:
  # $1: The service account to be used for creating Kyuubi pod
  # $1: The namespace to be used for creating Kyuubi pod

  # Create service account using the admin pod
  create_serviceaccount_using_pod $SERVICE_ACCOUNT $NAMESPACE $ADMIN_POD_NAME

  image=$(kyuubi_image)

  # Create the pod with the newly created service account
  sed -e "s%<IMAGE>%${image}%g" \
      -e "s/<SERVICE_ACCOUNT>/${SERVICE_ACCOUNT}/g" \
      -e "s/<NAMESPACE>/${NAMESPACE}/g" \
      -e "s/<POD_NAME>/${USER_POD_NAME}/g" \
      ./tests/integration/resources/kyuubi.yaml | \
    kubectl -n tests apply -f -
  
  wait_for_pod $USER_POD_NAME $NAMESPACE

  # Create Azure storage container
  create_azure_container $AZURE_CONTAINER

  storage_account_name=$(get_storage_account)
  storage_account_key=$(get_azure_secret_key)
  warehouse_path=$(construct_resource_uri $AZURE_CONTAINER warehouse abfss)
  file_upload_path=$(construct_resource_uri $AZURE_CONTAINER "" abfss)

  # Write Spark configs inside the Kyuubi container
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env IMG="$image" \
          /bin/bash -c 'echo spark.kubernetes.container.image=$IMG  > /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env NN="$NAMESPACE" \
          /bin/bash -c 'echo spark.kubernetes.namespace=$NN >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env UU="$SERVICE_ACCOUNT" \
          /bin/bash -c 'echo spark.kubernetes.authenticate.driver.serviceAccountName=$UU >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env ACCOUNT_NAME="$storage_account_name" SECRET_KEY="$storage_account_key"\
          /bin/bash -c 'echo spark.hadoop.fs.azure.account.key.$ACCOUNT_NAME.dfs.core.windows.net=$SECRET_KEY >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env WAREHOUSE="$warehouse_path" \
          /bin/bash -c 'echo spark.sql.warehouse.dir=$WAREHOUSE >> /etc/spark8t/conf/spark-defaults.conf'
  kubectl -n $NAMESPACE exec kyuubi-test -- \
      env UPLOAD_PATH="$file_upload_path" \
          /bin/bash -c 'echo spark.kubernetes.file.upload.path=$UPLOAD_PATH >> /etc/spark8t/conf/spark-defaults.conf'

  # Wait some time for the server to be up and running
  sleep 10
}


cleanup_user() {
  # Cleanup user resources.
  # 
  # Arguments:
  # $1: Exit code of the accompanying process (used to decide how to clean up)
  # $2: Service account name
  # $3: Namespace 

  exit_code=$1
  username=$2
  namespace=$3

  # Delete user pod and service account
  kubectl -n $NAMESPACE delete pod $USER_POD_NAME --wait=true
  kubectl -n $NAMESPACE exec $ADMIN_POD_NAME -- env UU="$username" NN="$namespace" \
                  /bin/bash -c 'spark-client.service-account-registry delete --username $UU --namespace $NN'  

  # Delete S3 bucket
  delete_s3_bucket $S3_BUCKET || true

  # Delete Azure container
  delete_azure_container $AZURE_CONTAINER || true

  # Verify deletion of service account
  output=$(kubectl -n $NAMESPACE exec $ADMIN_POD_NAME -- /bin/bash -c 'spark-client.service-account-registry list')
  exists=$(echo -e "$output" | grep "$namespace:$username" | wc -l)
  if [ "${exists}" -ne "0" ]; then
      exit 2
  fi

  if [ "${exit_code}" -ne "0" ]; then
      kubectl delete ns $NAMESPACE
      exit 1
  fi
}


cleanup_user_success() {
  echo "cleanup_user_success()......"
  cleanup_user 0 $SERVICE_ACCOUNT $NAMESPACE
}


cleanup_user_failure() {
  echo "cleanup_user_failure()......"
  cleanup_user 1 $SERVICE_ACCOUNT $NAMESPACE
}


teardown_test_pods() {
  kubectl -n $NAMESPACE delete pod $ADMIN_POD_NAME $USER_POD_NAME
}


test_jdbc_connection(){
  # Test the JDBC endpoint exposed by Kyuubi by running a few SQL queries
  jdbc_endpoint=$(kubectl -n $NAMESPACE exec kyuubi-test -- pebble logs kyuubi | grep 'Starting and exposing JDBC connection at:' | rev | cut -d' ' -f1 | rev)
  echo "Testing JDBC endpoint '$jdbc_endpoint'..."
 
  commands=$(cat ./tests/integration/resources/test-kyuubi.sql)

  echo -e "$(kubectl exec kyuubi-test -n $NAMESPACE -- \
          env CMDS="$commands" ENDPOINT="$jdbc_endpoint" \
          /bin/bash -c 'echo "$CMDS" | /opt/kyuubi/bin/beeline -u $ENDPOINT'
      )" > /tmp/test_beeline.out

  num_rows_inserted=$(cat /tmp/test_beeline.out | grep "Inserted Rows:" | sed 's/|/ /g' | tail -n 1 | xargs | rev | cut -d' ' -f1 | rev )
  echo -e "${num_rows_inserted} rows were inserted."

  if [ "${num_rows_inserted}" != "3" ]; then
      echo "ERROR: Test failed. ${num_rows_inserted} out of 3 rows were inserted. Aborting with exit code 1."
      exit 1
  fi

  rm /tmp/test_beeline.out
}



echo -e "##################################"
echo -e "SETUP ADMIN TEST POD"
echo -e "##################################"

kubectl create namespace $NAMESPACE
setup_admin_pod $ADMIN_POD_NAME $(kyuubi_image) $NAMESPACE

echo -e "##################################"
echo -e "START KYUUBI POD AND BEGIN TESTING (USING S3)"
echo -e "##################################"

(setup_kyuubi_pod_with_s3 && test_jdbc_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "START KYUUBI POD AND BEGIN TESTING (USING Azure Storage)"
echo -e "##################################"

(setup_kyuubi_pod_with_azure_abfss && test_jdbc_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "TEARDOWN ADMIN POD"
echo -e "##################################"

teardown_test_pods
kubectl delete namespace $NAMESPACE

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
