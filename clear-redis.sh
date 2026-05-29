#!/bin/bash

# Load variables from env.sh
if [ -f "./env.sh" ]; then
  source ./env.sh
else
  echo "Error: env.sh file not found."
  exit 1
fi

if [ -z "$APIGEE_HOST_NAME" ] || [ "$APIGEE_HOST_NAME" == "your-apigee-host.com" ]; then
  echo "Error: Please set APIGEE_HOST_NAME in env.sh."
  exit 1
fi

echo "============================================================"
echo "Clearing Redis cache via Apigee Proxy"
echo "============================================================"

API_ENDPOINT="https://$APIGEE_HOST_NAME/v1/samples/llm-redis-cache/clear"

echo "Calling clear endpoint: $API_ENDPOINT"
curl -X GET "$API_ENDPOINT"

echo ""
echo "============================================================"
