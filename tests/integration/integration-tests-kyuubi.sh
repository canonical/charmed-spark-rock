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


# Global Variables
NAMESPACE=tests
SERVICE_ACCOUNT=spark
ADMIN_POD_NAME=testpod-admin
USER_POD_NAME=kyuubi-test
S3_BUCKET=kyuubi


get_spark_version(){
  # Fetch Spark version from rockcraft.yaml
  yq '(.version)' rockcraft.yaml
}


get_kyuubi_version(){
  # Fetch Kyuubi version from rockcraft.yaml
  grep "version:kyuubi" rockcraft.yaml | sed "s/^#//" | cut -d ":" -f3
}


kyuubi_image(){
  # The Kyuubi image that is going to be used for test
  echo "ghcr.io/canonical/test-charmed-spark-kyuubi:$(get_spark_version)"
}


setup_kyuubi_pod() {
  # Setup Kyuubi pod for testing
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
  kubectl -n $NAMESPACE exec kyuubi-test -- env UU="$USERNAME"              /bin/bash -c 'echo spark.kubernetes.authenticate.driver.serviceAccountName=$UU >> /etc/spark8t/conf/spark-defaults.conf'
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
  delete_s3_bucket kyuubi

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
echo -e "START KYUUBI POD AND BEGIN TESTING"
echo -e "##################################"

(setup_kyuubi_pod && test_jdbc_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "TEARDOWN ADMIN POD"
echo -e "##################################"

teardown_test_pods
kubectl delete namespace $NAMESPACE

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
