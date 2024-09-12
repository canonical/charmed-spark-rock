#!/bin/bash

# Install AWS CLI
sudo snap install aws-cli --classic



source ./utils/s3-utils.sh

wait_and_retry(){
    # Retry a command for a number of times by waiting a few seconds.

    command="$@"
    retries=0
    max_retries=50
    until [ "$retries" -ge $max_retries ]
    do
        $command &> /dev/null && break
        retries=$((retries+1)) 
        echo "Trying to execute command ${command}..."
        sleep 5
    done

    # If the command was not successful even on maximum retries
    if [ "$retries" -ge $max_retries ]; then
        echo "Maximum number of retries ($max_retries) reached. ${command} returned with non zero status."
        exit 1
    fi
}


# Wait for `minio` service to be ready and S3 endpoint to be available
wait_and_retry get_s3_endpoint

S3_ENDPOINT=$(get_s3_endpoint)
DEFAULT_REGION="us-east-2"
ACCESS_KEY=$(get_s3_access_key)
SECRET_KEY=$(get_s3_secret_key)

# Configure AWS CLI credentials
aws configure set aws_access_key_id $ACCESS_KEY
aws configure set aws_secret_access_key $SECRET_KEY
aws configure set default.region $DEFAULT_REGION
aws configure set endpoint_url "http://$S3_ENDPOINT"

wait_and_retry aws s3 ls
echo "AWS CLI credentials set successfully"