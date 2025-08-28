#!/bin/bash

# cleanup_gcloud.sh - Deletes resources created by deploy_gcloud.sh for A2A Dispute Project

# --- Configuration - SET THESE VALUES (must match deploy_gcloud.sh) ---
export PROJECT_ID="your-gcp-project-id-here" # <-- REPLACE with your Project ID
export REGION="us-central1"             # <-- REPLACE with your desired GCP Region
export SERVICE_PREFIX="a2a-dispute"
# --- End Configuration ---

# Derived names (should match deploy_gcloud.sh)
export AR_REPO_NAME="${SERVICE_PREFIX}-repo" # Artifact Registry repo name
export AR_LOCATION=$REGION # Often same as REGION for Artifact Registry

export GCR_HOSTNAME="${AR_LOCATION}-docker.pkg.dev"
export AR_URL="${GCR_HOSTNAME}/${PROJECT_ID}/${AR_REPO_NAME}"

export TRANSACTION_SERVICE_NAME="${SERVICE_PREFIX}-transaction-agent"
export POLICY_SERVICE_NAME="${SERVICE_PREFIX}-policy-agent"
export PROXY_SERVICE_NAME="${SERVICE_PREFIX}-proxy"

echo "--- Cleanup Configuration ---"
echo "PROJECT_ID:           $PROJECT_ID"
echo "REGION:               $REGION"
echo "SERVICE_PREFIX:       $SERVICE_PREFIX"
echo "AR_REPO_NAME:         $AR_REPO_NAME"
echo "AR_URL:               $AR_URL"
echo "Services to delete:   $TRANSACTION_SERVICE_NAME, $POLICY_SERVICE_NAME, $PROXY_SERVICE_NAME (in $REGION)"
echo "Repo to delete:       $AR_REPO_NAME in $AR_LOCATION"
echo "---------------------------"
echo "This will attempt to DELETE the Cloud Run services and Artifact Registry repository listed above."
read -p "Are you sure you want to proceed with cleanup? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

echo "--- Setting default project ---"
gcloud config set project $PROJECT_ID

# Function to delete Cloud Run service if it exists
delete_cloud_run_service() {
    local service_name=$1
    echo "--- Checking and deleting Cloud Run service: $service_name in $REGION ---"
    if gcloud run services describe $service_name --platform managed --region $REGION --project=$PROJECT_ID > /dev/null 2>&1; then
        gcloud run services delete $service_name \
            --platform managed \
            --region $REGION \
            --project=$PROJECT_ID \
            --quiet
        if [ $? -eq 0 ]; then
            echo "Successfully deleted Cloud Run service: $service_name"
        else
            echo "Warning: Failed to delete Cloud Run service $service_name."
        fi
    else
        echo "Cloud Run service $service_name not found or already deleted."
    fi
}

# 1. Delete Cloud Run Services (in reverse order of creation or any order if no dependency)
delete_cloud_run_service $PROXY_SERVICE_NAME
delete_cloud_run_service $POLICY_SERVICE_NAME
delete_cloud_run_service $TRANSACTION_SERVICE_NAME

# 2. Delete Images from Artifact Registry (if repository exists)
echo "--- Attempting to delete container images from Artifact Registry repository: $AR_REPO_NAME ---"
if gcloud artifacts repositories describe $AR_REPO_NAME --location=$AR_LOCATION --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "Repository $AR_REPO_NAME found. Deleting images within it..."

    for img_suffix in $PROXY_SERVICE_NAME $POLICY_SERVICE_NAME $TRANSACTION_SERVICE_NAME; do
        full_image_name="${AR_URL}/${img_suffix}"
        echo "Attempting deletion of image path: $full_image_name (all tags/digests within)"
        # This deletes the image and all its tags/digests if it exists
        gcloud artifacts docker images delete $full_image_name --delete-tags --quiet --project=$PROJECT_ID || echo "Info: No images found or could not delete for $full_image_name (might be empty or already deleted)."

        # Specifically target :latest if above doesn't catch it sometimes
        full_image_name_latest="${full_image_name}:latest"
        if gcloud artifacts docker images describe $full_image_name_latest --project=$PROJECT_ID > /dev/null 2>&1; then
             echo "Deleting image tag: $full_image_name_latest"
             gcloud artifacts docker images delete $full_image_name_latest --delete-tags --quiet --project=$PROJECT_ID || echo "Warning: Failed to delete image tag $full_image_name_latest."
        fi
    done

    # Give some time for image deletion to reflect before deleting repo
    echo "Waiting briefly before attempting repository deletion..."
    sleep 15

    # 3. Delete Artifact Registry Repository
    echo "--- Deleting Artifact Registry repository: $AR_REPO_NAME in $AR_LOCATION ---"
    gcloud artifacts repositories delete $AR_REPO_NAME \
        --location=$AR_LOCATION \
        --project=$PROJECT_ID \
        --quiet
    if [ $? -eq 0 ]; then
        echo "Successfully deleted Artifact Registry repository: $AR_REPO_NAME"
    else
        echo "Warning: Failed to delete Artifact Registry repository $AR_REPO_NAME. It might not exist or might still contain images (check manually in GCP console)."
        echo "You may need to manually delete images from ${GCR_HOSTNAME}/${PROJECT_ID}/${AR_REPO_NAME} in Artifact Registry."
    fi
else
    echo "Artifact Registry repository $AR_REPO_NAME not found in $AR_LOCATION."
fi

echo "--- Cleanup Script Finished ---"
echo "Please verify resource deletion in the Google Cloud Console for project $PROJECT_ID."