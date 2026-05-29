#!/bin/bash

# Load variables from env.sh
if [ -f "./env.sh" ]; then
    source ./env.sh
else
    echo "env.sh file not found. Please ensure it exists."
    exit 1
fi

SERVICE_NAME="semantic-cache"

echo "Checking required APIs..."
ENABLED_APIS=$(gcloud services list --enabled --project="$PROJECT_ID" --format="value(config.name)")

APIS=(
  "run.googleapis.com"
  "cloudbuild.googleapis.com"
  "artifactregistry.googleapis.com"
  "iam.googleapis.com"
)

for api in "${APIS[@]}"; do
  if ! echo "$ENABLED_APIS" | grep -q "$api"; then
    echo "Enabling $api..."
    gcloud services enable "$api" --project="$PROJECT_ID"
  fi
done


SA_NAME="semantic-cache-svc-acct"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

echo "Checking if Service Account exists: $SA_EMAIL"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" &>/dev/null; then
  echo "Creating Service Account: $SA_NAME"
  gcloud iam service-accounts create "$SA_NAME" --display-name "Semantic Cache Service Account" --project "$PROJECT_ID"
  echo "Granting roles..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member "serviceAccount:$SA_EMAIL" --role "roles/aiplatform.user" --condition=None &>/dev/null
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member "serviceAccount:$SA_EMAIL" --role "roles/run.invoker" --condition=None &>/dev/null
fi

# --- Firewall Rule Setup ---
echo "Getting subnet CIDR range for region $REGION..."
SUBNET_CIDR=$(gcloud compute networks subnets describe "$VPC_SUBNET" --region="$REGION" --project="$PROJECT_ID" --format="value(ipCidrRange)")

echo "Checking if firewall rule exists: allow-cloudrun-to-redis"
if ! gcloud compute firewall-rules describe allow-cloudrun-to-redis --project "$PROJECT_ID" &>/dev/null; then
  echo "Creating firewall rule: allow-cloudrun-to-redis"
  gcloud compute firewall-rules create allow-cloudrun-to-redis \
      --network="$VPC_NETWORK" \
      --action=ALLOW \
      --direction=INGRESS \
      --source-ranges="$SUBNET_CIDR" \
      --rules=tcp:6379 \
      --project="$PROJECT_ID"
fi

# Build and deploy to Cloud Run
# Note: You need to replace <REDIS_IP> with the actual IP of your Memorystore instance.
# Note: If your Redis is in a VPC, you may need to add --vpc-connector or --network flags.
echo "============================================================"
echo "Deploying semantic-cache to Cloud Run"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "============================================================"

gcloud run deploy $SERVICE_NAME \
    --source semantic-cache \
    --region=$REGION \
    --project=$PROJECT_ID \
    --network=$VPC_NETWORK \
    --subnet=$VPC_SUBNET \
    --vpc-egress=private-ranges-only \
    --set-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
    --set-env-vars REDIS_URL="redis://$REDIS_IP:6379" \
    --set-env-vars SCORE_THRESHOLD=$SCORE_THRESHOLD \
    --set-env-vars CACHE_TTL=$CACHE_TTL \
    --set-env-vars PYTHONUNBUFFERED=1 \
    --ingress=all \
    --service-account=$SA_EMAIL \
    --no-allow-unauthenticated

# Get the Cloud Run service URL
echo "Fetching Cloud Run service URL..."
CLOUD_RUN_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID --format="value(status.url)")

echo "Updating Apigee target endpoint with Cloud Run URL: $CLOUD_RUN_URL"
sed -i "s|https://CLOUD_RUN_URL|$CLOUD_RUN_URL|g" apiproxy/targets/semanticCache.xml

echo "============================================================"
echo "Deployment completed successfully!"
echo "============================================================"