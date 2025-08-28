# Set variables (adjust if needed, but should match your deploy script)
PROJECT_ID="your-gcp-project-id-here" # <-- REPLACE with your Project ID
REGION="us-central1"
TRANSACTION_SERVICE_NAME="a2a-dispute-transaction-agent"
POLICY_SERVICE_NAME="a2a-dispute-policy-agent"
PROXY_SERVICE_NAME="a2a-dispute-proxy"

echo "Granting public access to Transaction Agent..."
gcloud run services add-iam-policy-binding "$TRANSACTION_SERVICE_NAME" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform="managed"

echo "Granting public access to Policy Agent..."
gcloud run services add-iam-policy-binding "$POLICY_SERVICE_NAME" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform="managed"

echo "Granting public access to Proxy..."
gcloud run services add-iam-policy-binding "$PROXY_SERVICE_NAME" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform="managed"

echo "IAM policies updated. It might take a minute for changes to propagate."
