#!/bin/bash

export PROJECT_ID="apac-na-apigee-x-demo1"
export REGION="us-central1"

export REDIS_SIZE=1
export REDIS_TIER="basic"
export VPC_NETWORK="default"
export VPC_SUBNET="default"
export REDIS_IP="10.212.154.171"
export SCORE_THRESHOLD=0.2
export APIGEE_ORG="$PROJECT_ID"
export APIGEE_ENV="eval"
export CACHE_TTL=3600
export APIGEE_HOST_NAME="eval-group.35-186-195-41.nip.io"
