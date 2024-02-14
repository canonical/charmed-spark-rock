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

NAMESPACE=tests

get_spark_version(){
  SPARK_VERSION=$(yq '(.version)' rockcraft.yaml)
  echo "$SPARK_VERSION"
}

spark_image(){
  echo "ghcr.io/canonical/test-charmed-spark-jupyterlab:$(get_spark_version)"
}

setup_jupyter() {
  echo "setup_jupyter() ${1} ${2}"

  USERNAME=$1
  NAMESPACE=$2

  kubectl -n $NAMESPACE exec testpod-admin -- env UU="$USERNAME" NN="$NAMESPACE" \
                /bin/bash -c 'spark-client.service-account-registry create --username $UU --namespace $NN'

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

wait_for_pod() {

  POD=$1
  NAMESPACE=$2

  SLEEP_TIME=1
  for i in {1..5}
  do
    pod_status=$(kubectl -n ${NAMESPACE} get pod ${POD} | awk '{ print $3 }' | tail -n 1)
    echo $pod_status
    if [[ "${pod_status}" == "Running" ]]
    then
        echo "testpod is Running now!"
        break
    elif [[ "${i}" -le "5" ]]
    then
        echo "Waiting for the pod to come online..."
        sleep $SLEEP_TIME
    else
        echo "testpod did not come up. Test Failed!"
        exit 3
    fi
    SLEEP_TIME=$(expr $SLEEP_TIME \* 2);
  done
}

setup_admin_test_pod() {
  kubectl create ns $NAMESPACE

  echo "Creating admin test-pod"

  # Create a pod with admin service account
  yq ea '.spec.containers[0].env[0].name = "KUBECONFIG" | .spec.containers[0].env[0].value = "/var/lib/spark/.kube/config" | .metadata.name = "testpod-admin"' \
    ./tests/integration/resources/testpod.yaml | \
    kubectl -n tests apply -f -

  wait_for_pod testpod-admin $NAMESPACE

  MY_KUBE_CONFIG=$(cat /home/${USER}/.kube/config)

  kubectl -n $NAMESPACE exec testpod-admin -- /bin/bash -c 'mkdir -p ~/.kube'
  kubectl -n $NAMESPACE exec testpod-admin -- env KCONFIG="$MY_KUBE_CONFIG" /bin/bash -c 'echo "$KCONFIG" > ~/.kube/config'
}

teardown_test_pod() {
  kubectl -n $NAMESPACE delete pod testpod-admin
  kubectl delete namespace $NAMESPACE
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

setup_admin_test_pod

echo -e "##################################"
echo -e "START JUPYTER SERVICE"
echo -e "##################################"

(setup_jupyter spark tests && test_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "TEARDOWN ADMIN POD"
echo -e "##################################"

teardown_test_pod

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
