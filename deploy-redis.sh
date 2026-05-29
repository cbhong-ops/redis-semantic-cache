#!/bin/bash

# Load env.sh file
if [ -f "./env.sh" ]; then
    source ./env.sh
else
    echo "env.sh file does not exist. Please create env.sh file first."
    exit 1
fi

# 1. Enable Redis API
echo "Activating Redis API..."
gcloud services enable redis.googleapis.com --project=$PROJECT_ID

# 2. Create Redis instance
echo "Creating Memorystore for Redis instance (this may take a few minutes)..."
gcloud redis instances create redis-semantic-cache \
    --size=$REDIS_SIZE \
    --region=$REGION \
    --tier=$REDIS_TIER \
    --network=$VPC_NETWORK \
    --project=$PROJECT_ID \
    --redis-version=redis_7_2

# 3. Guidance for checking results
echo "--------------------------------------------------"
echo "Instance creation request completed."
echo "To check the IP address after creation is complete, run the following command:"
echo "gcloud redis instances describe redis-semantic-cache --region=$REGION --project=$PROJECT_ID"
echo "--------------------------------------------------"
