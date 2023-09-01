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

  kubectl exec testpod -- /bin/bash -c 'mkdir -p ~/.kube'
  kubectl exec testpod -- env KCONFIG="$MY_KUBE_CONFIG" /bin/bash -c 'echo "$KCONFIG" > ~/.kube/config'
  kubectl exec testpod -- /bin/bash -c 'cat ~/.kube/config'
  kubectl exec testpod -- /bin/bash -c 'cp -r /opt/spark/python /var/lib/spark/'
}

teardown_test_pod() {
  kubectl delete pod testpod
}

run_example_job_in_pod() {
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
                  local:///opt/spark/examples/jars/$JJ 100'

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

test_example_job_in_pod() {
  run_example_job_in_pod tests spark
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


setup_test_pod

(setup_user_admin_context && test_example_job_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

(setup_user_admin_context && test_spark_shell_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

(setup_user_admin_context && test_pyspark_in_pod && cleanup_user_success) || cleanup_user_failure_in_pod

teardown_test_pod