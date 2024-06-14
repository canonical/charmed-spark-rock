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
source ./tests/integration/utils/k8s-utils.sh

# Global Variables
NAMESPACE=tests
ADMIN_POD_NAME=testpod-admin

get_spark_version(){
  yq '(.version)' images/charmed-spark/rockcraft.yaml
}


spark_image(){
  echo "ghcr.io/canonical/test-charmed-spark-jupyterlab:$(get_spark_version)"
}


setup_jupyter() {
  echo "setup_jupyter() ${1} ${2}"

  USERNAME=$1
  NAMESPACE=$2

  # Create service account using the admin pod
  create_serviceaccount_using_pod $USERNAME $NAMESPACE $ADMIN_POD_NAME

  IMAGE=$(spark_image)
  echo $IMAGE

  # Create the pod with the Spark service account
  sed -e "s%<IMAGE>%${IMAGE}%g" \
      -e "s/<SERVICE_ACCOUNT>/${USERNAME}/g" \
      -e "s/<NAMESPACE>/${NAMESPACE}/g" \
      ./tests/integration/resources/jupyter.yaml | \
    kubectl -n tests apply -f -

  wait_for_pod charmed-spark-jupyter $NAMESPACE

  # WAIT FOR SERVER TO BE UP AND RUNNING
  sleep 10
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  kubectl -n $NAMESPACE delete pod charmed-spark-jupyter --wait=true

  kubectl -n $NAMESPACE exec testpod-admin -- env UU="$USERNAME" NN="$NAMESPACE" \
                  /bin/bash -c 'spark-client.service-account-registry delete --username $UU --namespace $NN'  

  OUTPUT=$(kubectl -n $NAMESPACE exec testpod-admin -- /bin/bash -c 'spark-client.service-account-registry list')

  EXISTS=$(echo -e "$OUTPUT" | grep "$NAMESPACE:$USERNAME" | wc -l)

  if [ "${EXISTS}" -ne "0" ]; then
      exit 2
  fi

  if [ "${EXIT_CODE}" -ne "0" ]; then
      kubectl delete ns $NAMESPACE
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
  kubectl -n $NAMESPACE delete pod testpod-admin
}

get_status_code() {
  URL=$1

  STATUS_CODE=$(curl -X GET -o /dev/null --silent --head --write-out '%{http_code}\n' "${URL}")

  echo $STATUS_CODE
}

test_connection(){
  SERVICE_IP=$(kubectl get svc jupyter-service -n $NAMESPACE -o yaml | yq .spec.clusterIP)

  echo "Jupyter service IP: ${SERVICE_IP}"

  STATUS_CODE=$(get_status_code "http://${SERVICE_IP}:8888/jupyter-test/lab")

  if [[ "${STATUS_CODE}" -ne "200" ]]; then
    echo "200 exit code NOT returned"
    exit 1
  fi

  STATUS_CODE=$(get_status_code "http://${SERVICE_IP}:8888/jupyter-test")

  if [[ "${STATUS_CODE}" -ne "302" ]]; then
    echo "302 exit code NOT returned"
    exit 1
  fi

  STATUS_CODE=$(get_status_code "http://${SERVICE_IP}:8888")

  if [[ "${STATUS_CODE}" -ne "404" ]]; then
    echo "404 exit code NOT returned"
    exit 1
  fi

}

echo -e "##################################"
echo -e "SETUP TEST POD"
echo -e "##################################"

kubectl create namespace $NAMESPACE
setup_admin_pod $ADMIN_POD_NAME $(spark_image) $NAMESPACE

echo -e "##################################"
echo -e "START JUPYTER SERVICE"
echo -e "##################################"

(setup_jupyter spark tests && test_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "TEARDOWN ADMIN POD"
echo -e "##################################"

teardown_test_pod
kubectl delete namespace $NAMESPACE

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
