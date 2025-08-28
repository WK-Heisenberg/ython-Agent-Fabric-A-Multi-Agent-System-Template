#!/bin/bash

# deploy_gcloud.sh - Deploys A2A services to Google Cloud Run

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

# --- Configuration - SET THESE VALUES ---
export PROJECT_ID="your-gcp-project-id-here" # <-- REPLACE with your Project ID
export REGION="us-central1"             # <-- REPLACE with your desired GCP Region
export SERVICE_PREFIX="a2a-dispute"
# --- End Configuration ---

# Derived names
export AR_REPO_NAME="${SERVICE_PREFIX}-repo" # Artifact Registry repo name
export AR_LOCATION="$REGION" # Often same as REGION for Artifact Registry

export GCR_HOSTNAME="${AR_LOCATION}-docker.pkg.dev"
export AR_URL="${GCR_HOSTNAME}/${PROJECT_ID}/${AR_REPO_NAME}"

export TRANSACTION_SERVICE_NAME="${SERVICE_PREFIX}-transaction-agent"
export POLICY_SERVICE_NAME="${SERVICE_PREFIX}-policy-agent"
export PROXY_SERVICE_NAME="${SERVICE_PREFIX}-proxy"
# Orchestrator is run as a script, not deployed as a service here.

echo "--- Configuration ---"
echo "PROJECT_ID:           $PROJECT_ID"
echo "REGION:               $REGION"
echo "SERVICE_PREFIX:       $SERVICE_PREFIX"
echo "AR_REPO_NAME:         $AR_REPO_NAME (Artifact Registry)"
echo "AR_URL:               $AR_URL"
echo "TRANSACTION_AGENT:    $TRANSACTION_SERVICE_NAME"
echo "POLICY_AGENT:         $POLICY_SERVICE_NAME"
echo "PROXY:                $PROXY_SERVICE_NAME"
echo "---------------------"
read -p "Proceed with deployment? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || { echo "Deployment cancelled."; exit 1; }

echo "--- Enabling GCP APIs ---"
gcloud services enable run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    --project="$PROJECT_ID"

echo "--- Setting default project ---"
gcloud config set project "$PROJECT_ID"
gcloud config set run/region "$REGION"
gcloud config set run/platform managed

echo "--- Creating Artifact Registry Repository (if it doesn't exist) ---"
# Use --quiet to suppress output on success, rely on set -e for failure
if ! gcloud artifacts repositories describe "$AR_REPO_NAME" --location="$AR_LOCATION" --project="$PROJECT_ID" --quiet > /dev/null 2>&1; then
    echo "Creating Artifact Registry repository: $AR_REPO_NAME in $AR_LOCATION"
    gcloud artifacts repositories create "$AR_REPO_NAME" \
        --repository-format=docker \
        --location="$AR_LOCATION" \
        --description="A2A Dispute Project Images" \
        --project="$PROJECT_ID" \
        --quiet
else
    echo "Artifact Registry repository '$AR_REPO_NAME' already exists in $AR_LOCATION."
fi

# Function to build and push image, then deploy to Cloud Run
deploy_service() {
    local service_dir=$1
    local service_name=$2
    local port=$3
    local env_vars=$4 # Comma-separated KEY=VALUE pairs, potentially prefixed with delimiter like ^~^
    # Optional: Add a 5th argument for a specific service account if needed
    # local service_account=$5

    # Use Git commit hash for unique tagging (or timestamp if not in git repo)
    local git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "ts-$(date +%s)")
    local image_tag="${AR_URL}/${service_name}:${git_hash}"
    echo "Using image tag: $image_tag"

    echo "--- Building and Pushing $service_name image from $service_dir ---"
    # Use --quiet to reduce build log noise in this script's output
    # Path to service_dir is now relative to the scripts/ directory
    gcloud builds submit "../$service_dir" --tag "$image_tag" --project="$PROJECT_ID" --quiet

    # No need for explicit error check here, 'set -e' handles it
    echo "Image pushed: $image_tag"

    echo "--- Deploying $service_name to Cloud Run ---"
    # Note: --allow-unauthenticated has been REMOVED.
    # Services are now PRIVATE by default. You will need to grant specific
    # users, service accounts, or groups the 'roles/run.invoker' IAM role
    # to allow them to access these services.
    # Example: gcloud run services add-iam-policy-binding $service_name --member='user:your-email@example.com' --role='roles/run.invoker' --region=$REGION
    gcloud run deploy "$service_name" \
        --image "$image_tag" \
        --port "$port" \
        --platform managed \
        --region "$REGION" \
        --project="$PROJECT_ID" \
        --quiet \
        ${env_vars:+--set-env-vars="$env_vars"} # Add env vars only if $env_vars is not empty
        # Optional: Add service account if provided
        # ${service_account:+--service-account="$service_account"}

    # No need for explicit error check here, 'set -e' handles it
    echo "$service_name deployed successfully."
    # The URL is fetched outside the function now, so this describe call is removed
}

# 1. Deploy Transaction Detail Agent
echo ""
# Use ../agent_transaction_detail as the source directory relative to the script's new location
deploy_service "agent_transaction_detail" "$TRANSACTION_SERVICE_NAME" 8001 ""
TRANSACTION_AGENT_URL=$(gcloud run services describe "$TRANSACTION_SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)' --project="$PROJECT_ID")
# Check if URL is empty (gcloud command might succeed but return no URL if service failed provisioning)
if [ -z "$TRANSACTION_AGENT_URL" ]; then echo "ERROR: Could not get URL for $TRANSACTION_SERVICE_NAME"; exit 1; fi
echo "$TRANSACTION_SERVICE_NAME URL: $TRANSACTION_AGENT_URL"

# 2. Deploy Dispute Policy Agent
echo ""
# Use ../agent_dispute_policy as the source directory relative to the script's new location
deploy_service "agent_dispute_policy" "$POLICY_SERVICE_NAME" 8002 ""
POLICY_AGENT_URL=$(gcloud run services describe "$POLICY_SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)' --project="$PROJECT_ID")
if [ -z "$POLICY_AGENT_URL" ]; then echo "ERROR: Could not get URL for $POLICY_SERVICE_NAME"; exit 1; fi
echo "$POLICY_SERVICE_NAME URL: $POLICY_AGENT_URL"

# 3. Deploy Proxy Server with Agent URLs
echo ""
AGENT_URLS_FOR_PROXY="${TRANSACTION_AGENT_URL},${POLICY_AGENT_URL}"
echo "Proxy will poll: $AGENT_URLS_FOR_PROXY"
# Use ../proxy_server as the source directory relative to the script's new location
# Use ^~^ delimiter for env vars because the value contains a comma
deploy_service "proxy_server" "$PROXY_SERVICE_NAME" 8000 "^~^AGENT_URLS=$AGENT_URLS_FOR_PROXY"
PROXY_URL=$(gcloud run services describe "$PROXY_SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)' --project="$PROJECT_ID")
if [ -z "$PROXY_URL" ]; then echo "ERROR: Could not get URL for $PROXY_SERVICE_NAME"; exit 1; fi
echo "$PROXY_SERVICE_NAME URL: $PROXY_URL"

echo ""
echo "--- Deployment Summary ---"
echo "Transaction Agent URL: $TRANSACTION_AGENT_URL"
echo "Policy Agent URL:      $POLICY_AGENT_URL"
echo "Proxy URL:             $PROXY_URL"
echo ""
echo "--- IMPORTANT: Services are now PRIVATE ---"
echo "The '--allow-unauthenticated' flag has been removed. To access these services:"
echo "1. Grant Invoker Role: You (or the service account running the client) need the 'roles/run.invoker' IAM role for each service."
echo "   Example for your user: "
echo "   gcloud run services add-iam-policy-binding $PROXY_SERVICE_NAME --member=\"user:$(gcloud config get-value account)\" --role='roles/run.invoker' --region=$REGION --project=$PROJECT_ID"
echo "2. Proxy Permissions: The Proxy service ($PROXY_SERVICE_NAME) needs permission to invoke the Agent services."
echo "   Grant its runtime service account (usually default Compute Engine SA: PROJECT_NUMBER-compute@developer.gserviceaccount.com) the 'roles/run.invoker' role on $TRANSACTION_SERVICE_NAME and $POLICY_SERVICE_NAME."
echo "3. Authentication: Clients (like the orchestrator) must send authenticated requests (e.g., using 'gcloud auth print-identity-token')."
echo ""
echo "You can now run the orchestrator locally against the Cloud Run Proxy:"
echo "cd ../orchestrator" # Adjusted path
echo "export PROXY_URL=\"$PROXY_URL\"" # Added quotes for safety
echo "# Ensure you are authenticated (gcloud auth login) and have invoker permissions on the proxy!"
echo "# You might need to modify the orchestrator to include an Authorization: Bearer ID_TOKEN header."
echo "python app/main.py --txid TX12345 --reason \"Test from cloud deployment\""
echo "cd .." # Go back to root
echo ""
echo "Or build and run orchestrator via Cloud Build:"
echo "# Ensure the Cloud Build service account has invoker permissions on the proxy!"
echo "cd ../orchestrator && gcloud builds submit --config cloudbuild.yaml --project=\"$PROJECT_ID\" --substitutions=_PROXY_URL=\"$PROXY_URL\",_TX_ID=TX67890,_REASON='Another Cloud Test' && cd .." # Adjusted path and added cd ..
echo "--- Deployment Complete ---"

# Create orchestrator directory if it doesn't exist before writing the file
# Path is relative to the scripts/ directory
mkdir -p ../orchestrator

echo "Creating sample ../orchestrator/cloudbuild.yaml (if it doesn't exist)" # Adjusted path
# Use standard indentation for heredoc content
# Path is relative to the scripts/ directory
cat << EOF > ../orchestrator/cloudbuild.yaml
steps:
  - name: 'python:3.10-slim'
    entrypoint: 'bash'
    args:
      - -c
      - |
        pip install --no-cache-dir -r requirements.txt && \\
        export PROXY_URL="\${_PROXY_URL}" && \\
        # IMPORTANT: This sample build does NOT include authentication. Modify if needed.
        echo "Running orchestrator with PROXY_URL=\${PROXY_URL} TX_ID=\${_TX_ID} REASON='\${_REASON}'" && \\
        python app/main.py --txid "\${_TX_ID}" --reason "\${_REASON}"

substitutions:
  _PROXY_URL: '' # To be provided at build time
  _TX_ID: 'TX12345'
  _REASON: 'Default dispute from Cloud Build'
timeout: '600s'
EOF
echo "Sample ../orchestrator/cloudbuild.yaml created."
