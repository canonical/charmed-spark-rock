#!/bin/bash

# Copyright 2024 Canonical Ltd.

# This file contains several Bash utility functions related to K8s resource management.
# To use them, simply `source` this file in your bash script.


# Check if AWS CLI has been installed and the credentials have been configured. If not, exit.
if ! kubectl get ns >> /dev/null ; then
    echo "The K8s cluster has not been configured properly. Exiting..."
    exit 1
fi


wait_for_pod() {
    # Wait for the given pod in the given namespace to be ready.
    # 
    # Arguments:
    # $1: Name of the pod 
    # $2: Namespace that contains the pod

    pod_name=$1
    namespace=$2

    echo "Waiting for pod $1 to become ready..."
    kubectl wait --for condition=Ready pod/$pod_name -n $namespace --timeout 60s
}


create_serviceaccount_using_pod(){
    # Create a service account in the given namespace using a given pod.
    # 
    # Arguments:
    # $1: Name of the service account 
    # $2: Namespace which the service account should belong to
    # $3: Name of the pod to be used for creation

    username=$1
    namespace=$2
    pod_name=$3

    echo "Creating service account $username in namespace $namespace..."
    kubectl -n $namespace exec $pod_name -- env UU="$username" NN="$namespace" \
                    /bin/bash -c 'spark-client.service-account-registry create --username $UU --namespace $NN'
    echo "Service account $username in namespace $namespace created successfully."
}


delete_serviceaccount_using_pod(){
    # Delete a service account in the given namespace using a given pod.
    # 
    # Arguments:
    # $1: Name of the service account 
    # $2: Namespace which the service account belongs to
    # $3: Name of the pod to be used for deletion

    username=$1
    namespace=$2
    pod_name=$3

    echo "Deleting service account $username in namespace $namespace..."
    kubectl -n $namespace exec $pod_name -- env UU="$username" NN="$namespace" \
                    /bin/bash -c 'spark-client.service-account-registry delete --username $UU --namespace $NN'
    echo "Service account $username in namespace $namespace deleted successfully."
}



setup_admin_pod(){
    # Create a pod with admin service account.
    # 
    # Arguments:
    # $1: Name of the admin pod
    # $2: Image to be used when creating the admin pod
    # $3: Namespace where the pod is to be created

    pod_name=$1
    image=$2
    namespace=$3

    echo "Creating admin pod with name $pod_name"
    kubectl run $pod_name --image=$image --env="KUBECONFIG=/var/lib/spark/.kube/config" --namespace=${namespace}

    # Wait for pod to be ready
    wait_for_pod $pod_name $namespace

    user_kubeconfig=$(cat /home/${USER}/.kube/config)
    kubectl -n $namespace exec $pod_name -- /bin/bash -c 'mkdir -p ~/.kube'
    kubectl -n $namespace exec $pod_name -- env KCONFIG="$user_kubeconfig" /bin/bash -c 'echo "$KCONFIG" > ~/.kube/config'

    echo "Admin pod with name $pod_name created and configured successfully."
}