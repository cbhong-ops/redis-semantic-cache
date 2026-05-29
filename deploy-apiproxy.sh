#!/bin/bash

# Exit on error
set -e

# Source environment variables
if [ -f "./env.sh" ]; then
  source ./env.sh
else
  echo "Error: env.sh file not found."
  exit 1
fi

PROXY_NAME="llm-redis-cache-v1"
SA_NAME="semantic-cache-svc-acct"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

if [ -z "$APIGEE_ORG" ] || [ -z "$APIGEE_ENV" ]; then
  echo "Error: Please set APIGEE_ORG and APIGEE_ENV in env.sh."
  exit 1
fi

echo "============================================================"
echo "Deploying API Proxy: $PROXY_NAME"
echo "Org: $APIGEE_ORG"
echo "Env: $APIGEE_ENV"
echo "Service Account: $SA_EMAIL"
echo "============================================================"

# Check if apigeecli is installed
if ! command -v apigeecli &> /dev/null; then
    echo "apigeecli not found. Please install it or add to PATH."
    exit 1
fi

echo "Creating and Deploying API Proxy bundle..."
apigeecli apis create bundle \
    -f apiproxy \
    -n "$PROXY_NAME" \
    --org "$APIGEE_ORG" \
    -e "$APIGEE_ENV" \
    -s "$SA_EMAIL" \
    --ovr \
    --wait \
    --default-token

echo "============================================================"
echo "API Proxy deployment completed successfully!"
echo "============================================================"
