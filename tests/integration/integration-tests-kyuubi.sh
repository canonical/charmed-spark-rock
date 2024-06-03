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

kyuubi_image(){
  echo "ghcr.io/canonical/test-charmed-spark-kyuubi:$(get_spark_version)"
}

setup_kyuubi() {
  echo "setup_kyuubi() ${1} ${2}"

  USERNAME=$1
  NAMESPACE=$2

  kubectl -n $NAMESPACE exec testpod-admin -- env UU="$USERNAME" NN="$NAMESPACE" \
                /bin/bash -c 'spark-client.service-account-registry create --username $UU --namespace $NN'

  IMAGE=$(kyuubi_image)
  echo $IMAGE

  # Create the pod with the Spark service account
  sed -e "s%<IMAGE>%${IMAGE}%g" \
      -e "s/<SERVICE_ACCOUNT>/${USERNAME}/g" \
      -e "s/<NAMESPACE>/${NAMESPACE}/g" \
      ./tests/integration/resources/kyuubi.yaml | \
    kubectl -n tests apply -f -

  wait_for_pod kyuubi-test $NAMESPACE

  # WAIT FOR SERVER TO BE UP AND RUNNING
  sleep 10
}

cleanup_user() {
  EXIT_CODE=$1
  USERNAME=$2
  NAMESPACE=$3

  kubectl -n $NAMESPACE delete pod kyuubi-test --wait=true

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

teardown_test_pods() {
  kubectl -n $NAMESPACE delete pod testpod-admin
  kubectl delete namespace $NAMESPACE
}


test_jdbc_connection(){
  jdbc_endpoint=$(kubectl -n $NAMESPACE exec kyuubi-test -- pebble logs kyuubi | grep 'Starting and exposing JDBC connection at:' | rev | cut -d' ' -f1 | rev)
  commands=$(cat ./tests/integration/resources/test-kyuubi.sql)

  echo -e "$(kubectl exec kyuubi-test -- \
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

setup_admin_test_pod

echo -e "##################################"
echo -e "START KYUUBI POD AND BEGIN TESTING"
echo -e "##################################"

(setup_kyuubi spark tests && test_jdbc_connection && cleanup_user_success) || cleanup_user_failure

echo -e "##################################"
echo -e "TEARDOWN ADMIN POD"
echo -e "##################################"

teardown_test_pods

echo -e "##################################"
echo -e "END OF THE TEST"
echo -e "##################################"
