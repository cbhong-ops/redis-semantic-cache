#!/bin/bash

# Load variables from env.sh
if [ -f "./env.sh" ]; then
    source ./env.sh
else
    echo "env.sh file not found. Please ensure it exists."
    exit 1
fi

SERVICE_NAME="semantic-cache"
SA_NAME="semantic-cache-svc-acct"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
PROXY_NAME="llm-redis-cache-v1"

echo "============================================================"
echo "Cleaning up resources for $SERVICE_NAME"
echo "Project: $PROJECT_ID"
echo "============================================================"

# 0. Delete Apigee API Proxy
echo "Checking if Apigee proxy exists: $PROXY_NAME"
if apigeecli apis get -n "$PROXY_NAME" -o "$APIGEE_ORG" --default-token &>/dev/null; then
    echo "Undeploying Apigee proxy: $PROXY_NAME"
    # Try to undeploy, ignore error if not deployed
    apigeecli apis undeploy -n "$PROXY_NAME" -o "$APIGEE_ORG" -e "$APIGEE_ENV" --default-token || true
    
    echo "Deleting Apigee proxy: $PROXY_NAME"
    yes | apigeecli apis delete -n "$PROXY_NAME" -o "$APIGEE_ORG" --default-token
else
    echo "Apigee proxy does not exist. Skipping."
fi

# 1. Delete Cloud Run Service
echo "Checking if Cloud Run service exists: $SERVICE_NAME"
if gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "Deleting Cloud Run service: $SERVICE_NAME"
    gcloud run services delete $SERVICE_NAME --region=$REGION --project=$PROJECT_ID --quiet
else
    echo "Cloud Run service does not exist. Skipping."
fi

# 2. Delete Firewall Rule
echo "Checking if firewall rule exists: allow-cloudrun-to-redis"
if gcloud compute firewall-rules describe allow-cloudrun-to-redis --project=$PROJECT_ID &>/dev/null; then
    echo "Deleting firewall rule: allow-cloudrun-to-redis"
    gcloud compute firewall-rules delete allow-cloudrun-to-redis --project=$PROJECT_ID --quiet
else
    echo "Firewall rule does not exist. Skipping."
fi

# 3. Delete Service Account
echo "Checking if Service Account exists: $SA_EMAIL"
if gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" &>/dev/null; then
    echo "Deleting Service Account: $SA_NAME"
    gcloud iam service-accounts delete "$SA_EMAIL" --project "$PROJECT_ID" --quiet
else
    echo "Service Account does not exist. Skipping."
fi

# 4. Delete Redis Instance
echo "Checking if Redis instance exists: redis-semantic-cache"
if gcloud redis instances describe redis-semantic-cache --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "Deleting Redis instance: redis-semantic-cache (This may take a few minutes)..."
    gcloud redis instances delete redis-semantic-cache --region=$REGION --project=$PROJECT_ID --quiet
else
    echo "Redis instance does not exist. Skipping."
fi

echo "============================================================"
echo "Cleanup completed!"
echo "============================================================"
