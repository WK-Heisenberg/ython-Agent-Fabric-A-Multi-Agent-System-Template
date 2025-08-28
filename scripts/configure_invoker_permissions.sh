#!/bin/bash

# Script to grant Proxy's Service Account "Cloud Run Invoker" permissions on Agent services,
# and optionally remove 'allUsers' invoker permissions from agent services.
# Provides detailed output of changes.

# Exit on error, treat unset variables as an error.
set -e
set -u

# --- Initial Configuration Determination ---
# Project ID
GCLOUD_CONFIG_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
SCRIPT_DEFAULT_PROJECT_ID_PLACEHOLDER="your-gcp-project-id-here" # Placeholder from your deploy_gcloud.sh

# Determine initial effective project ID, prioritizing environment variable, then gcloud config, then script default
if [ -n "${PROJECT_ID:-}" ]; then # Check if PROJECT_ID env var is set and not empty
    EFFECTIVE_PROJECT_ID="${PROJECT_ID}"
    PROJECT_ID_SOURCE="environment variable (PROJECT_ID)"
elif [ -n "${GCLOUD_CONFIG_PROJECT_ID}" ]; then
    EFFECTIVE_PROJECT_ID="${GCLOUD_CONFIG_PROJECT_ID}"
    PROJECT_ID_SOURCE="gcloud config (project)"
else
    EFFECTIVE_PROJECT_ID="${SCRIPT_DEFAULT_PROJECT_ID_PLACEHOLDER}"
    PROJECT_ID_SOURCE="script default (placeholder)"
fi

# Region
GCLOUD_CONFIG_REGION=$(gcloud config get-value run/region 2>/dev/null || echo "")
SCRIPT_DEFAULT_REGION_PLACEHOLDER="us-central1" # Placeholder from your deploy_gcloud.sh

if [ -n "${REGION:-}" ]; then # Check if REGION env var is set and not empty
    EFFECTIVE_REGION="${REGION}"
    REGION_SOURCE="environment variable (REGION)"
elif [ -n "${GCLOUD_CONFIG_REGION}" ]; then
    EFFECTIVE_REGION="${GCLOUD_CONFIG_REGION}"
    REGION_SOURCE="gcloud config (run/region)"
else
    EFFECTIVE_REGION="${SCRIPT_DEFAULT_REGION_PLACEHOLDER}"
    REGION_SOURCE="script default (placeholder)"
fi

SERVICE_PREFIX_DEFAULT="a2a-dispute" # Default from your deploy_gcloud.sh
GCP_SERVICE_PREFIX="${SERVICE_PREFIX:-${SERVICE_PREFIX_DEFAULT}}" # Allow SERVICE_PREFIX env var override
# --- End Initial Configuration Determination ---

# Derived service names (consistent with deploy_gcloud.sh)
TRANSACTION_AGENT_SERVICE_NAME="${GCP_SERVICE_PREFIX}-transaction-agent"
POLICY_AGENT_SERVICE_NAME="${GCP_SERVICE_PREFIX}-policy-agent"
PROXY_SERVICE_NAME="${GCP_SERVICE_PREFIX}-proxy"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main logic
main() {
    echo "--- Script to Configure Cloud Run Invoker Permissions ---"
    echo ""
    echo "Detected initial settings (before prompting):"
    echo "  Project ID:       ${EFFECTIVE_PROJECT_ID} (Source: ${PROJECT_ID_SOURCE})"
    echo "  Region:           ${EFFECTIVE_REGION} (Source: ${REGION_SOURCE})"
    echo "  Service Prefix:   ${GCP_SERVICE_PREFIX}"
    echo "  Will affect:"
    echo "    Proxy Service:    ${PROXY_SERVICE_NAME}"
    echo "    Agent Services:   ${TRANSACTION_AGENT_SERVICE_NAME}, ${POLICY_AGENT_SERVICE_NAME}"
    echo "---------------------------------------------------------"

    # --- Determine Final Project ID and Region with User Input ---
    local FINAL_PROJECT_ID
    local FINAL_REGION

    # Project ID Prompting
    USER_INPUT_PROJECT_ID=""
    if [ "${EFFECTIVE_PROJECT_ID}" == "${SCRIPT_DEFAULT_PROJECT_ID_PLACEHOLDER}" ] && [[ "${PROJECT_ID_SOURCE}" == *"placeholder"* ]]; then
        echo "WARNING: The determined Project ID ('${EFFECTIVE_PROJECT_ID}') is a placeholder."
        read -p "Please enter your Google Cloud Project ID: " USER_INPUT_PROJECT_ID
        if [ -z "${USER_INPUT_PROJECT_ID}" ]; then
            echo "Error: A valid Project ID must be provided if the default is a placeholder." >&2
            exit 1
        fi
        FINAL_PROJECT_ID="${USER_INPUT_PROJECT_ID}"
    else
        read -p "Enter Google Cloud Project ID (or press Enter to use '${EFFECTIVE_PROJECT_ID}'): " USER_INPUT_PROJECT_ID
        if [ -n "${USER_INPUT_PROJECT_ID}" ]; then
            FINAL_PROJECT_ID="${USER_INPUT_PROJECT_ID}"
        else
            FINAL_PROJECT_ID="${EFFECTIVE_PROJECT_ID}" # Use effective default if user pressed Enter
        fi
    fi

    # Region Prompting
    USER_INPUT_REGION=""
    if [ "${EFFECTIVE_REGION}" == "${SCRIPT_DEFAULT_REGION_PLACEHOLDER}" ] && [[ "${REGION_SOURCE}" == *"placeholder"* ]]; then
        echo "WARNING: The determined Region ('${EFFECTIVE_REGION}') is a placeholder."
        read -p "Please enter the GCP Region for your services (e.g., us-central1): " USER_INPUT_REGION
        if [ -z "${USER_INPUT_REGION}" ]; then
            echo "Error: A valid Region must be provided if the default is a placeholder." >&2
            exit 1
        fi
        FINAL_REGION="${USER_INPUT_REGION}"
    else
        read -p "Enter GCP Region (or press Enter to use '${EFFECTIVE_REGION}'): " USER_INPUT_REGION
        if [ -n "${USER_INPUT_REGION}" ]; then
            FINAL_REGION="${USER_INPUT_REGION}"
        else
            FINAL_REGION="${EFFECTIVE_REGION}" # Use effective default if user pressed Enter
        fi
    fi

    echo ""
    echo "Will proceed with the following FINAL settings:"
    echo "  Project ID:       ${FINAL_PROJECT_ID}"
    echo "  Region:           ${FINAL_REGION}"
    echo "  Service Prefix:   ${GCP_SERVICE_PREFIX}"
    echo "  Proxy Service:    ${PROXY_SERVICE_NAME}"
    echo "  Agent Services:   ${TRANSACTION_AGENT_SERVICE_NAME}, ${POLICY_AGENT_SERVICE_NAME}"
    echo "---------------------------------------------------------"

    read -p "Proceed with applying IAM changes using these settings? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    # 1. Prerequisites check
    if ! command_exists gcloud; then
        echo "Error: gcloud CLI is not installed or not in PATH. Please install and configure it." >&2
        exit 1
    fi
    echo "✅ gcloud CLI found."

    JQ_EXISTS=false
    if command_exists jq; then
        JQ_EXISTS=true
        echo "✅ jq CLI found (for precise checking of 'allUsers' permissions)."
    else
        echo "⚠️  Warning: jq CLI is not installed. Checking existing 'allUsers' permissions will be less precise. It's recommended to install jq for optimal script function."
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" --quiet | grep -q "."; then
        echo "Error: Not authenticated with gcloud. Please run 'gcloud auth login' and consider 'gcloud auth application-default login'." >&2
        exit 1
    fi
    echo "✅ gcloud authentication active."

    # 2. Set gcloud project for this session
    echo "Setting gcloud project to '${FINAL_PROJECT_ID}' for this session..."
    gcloud config set project "${FINAL_PROJECT_ID}"

    # 3. Get Proxy's Service Account Email
    echo "Fetching service account for Proxy: '${PROXY_SERVICE_NAME}' in region '${FINAL_REGION}' (Project: ${FINAL_PROJECT_ID})..."
    PROXY_SERVICE_ACCOUNT_EMAIL=$(gcloud run services describe "${PROXY_SERVICE_NAME}" \
        --region "${FINAL_REGION}" \
        --project "${FINAL_PROJECT_ID}" \
        --format 'value(spec.template.spec.serviceAccountName)' 2>/dev/null)

    if [ -z "${PROXY_SERVICE_ACCOUNT_EMAIL}" ]; then
        echo "Error: Could not fetch service account for Proxy service '${PROXY_SERVICE_NAME}'." >&2
        echo "Please ensure the service is deployed and the name, region, and project ID are correct." >&2
        exit 1
    fi
    echo "✅ Proxy Service Account: ${PROXY_SERVICE_ACCOUNT_EMAIL}"

    # 4. Grant Invoker Permissions to Agent Services
    AGENT_SERVICES=("${TRANSACTION_AGENT_SERVICE_NAME}" "${POLICY_AGENT_SERVICE_NAME}")
    echo ""
    echo "--- Granting Invoker Permissions ---"
    for agent_service in "${AGENT_SERVICES[@]}"; do
        echo "Attempting to grant 'roles/run.invoker' to Principal '${PROXY_SERVICE_ACCOUNT_EMAIL}' for Cloud Run Service '${agent_service}'..."
        echo "  (Project: ${FINAL_PROJECT_ID}, Region: ${FINAL_REGION})"
        if gcloud run services add-iam-policy-binding "${agent_service}" \
            --member="serviceAccount:${PROXY_SERVICE_ACCOUNT_EMAIL}" \
            --role="roles/run.invoker" \
            --region "${FINAL_REGION}" \
            --project "${FINAL_PROJECT_ID}" \
            --quiet; then
            echo "✅ SUCCESS: Ensured 'roles/run.invoker' is granted to '${PROXY_SERVICE_ACCOUNT_EMAIL}' for service '${agent_service}'."
            echo "           Project: ${FINAL_PROJECT_ID}, Region: ${FINAL_REGION}."
        else
            # This block might not be reached if gcloud exits with 0 on "already exists" with --quiet.
            # However, keeping it for robustness in case gcloud behavior changes or other errors occur.
            echo "⚠️  WARNING: Command to grant invoker permission for '${agent_service}' completed, but an issue might have occurred or permission already existed. Review gcloud output if any, or check manually." >&2
        fi
    done

    # 5. Optional: Remove allUsers invoker permission from agent services
    echo ""
    read -p "Do you want to attempt to REMOVE 'allUsers' (public) invoker permissions from agent services? (Recommended for secure service-to-service auth) (y/N): " remove_all_users_confirm
    if [[ "$remove_all_users_confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        echo ""
        echo "--- Removing 'allUsers' (Public) Invoker Permissions ---"
        for agent_service in "${AGENT_SERVICES[@]}"; do
            echo "Checking and attempting to remove 'roles/run.invoker' for Principal 'allUsers' from Cloud Run Service '${agent_service}'..."
            echo "  (Project: ${FINAL_PROJECT_ID}, Region: ${FINAL_REGION})"
            
            all_users_has_invoker_role=false
            if [ "$JQ_EXISTS" = true ]; then
                current_policy_allusers=$(gcloud run services get-iam-policy "${agent_service}" \
                    --region "${FINAL_REGION}" \
                    --project "${FINAL_PROJECT_ID}" \
                    --format=json 2>/dev/null | jq -r '.bindings[] | select(.role == "roles/run.invoker") | .members[] | select(. == "allUsers")' || echo "")
                if [ "$current_policy_allusers" == "allUsers" ]; then
                    all_users_has_invoker_role=true
                    echo "  Found 'allUsers' with 'roles/run.invoker' on '${agent_service}'. Attempting removal."
                else
                     echo "  'allUsers' not found with 'roles/run.invoker' on '${agent_service}'. No removal needed based on precise check."
                fi
            else
                # Fallback if jq is not present
                echo "  jq not found. Attempting removal without precise pre-check. A non-zero exit from gcloud is expected if the binding doesn't exist."
                all_users_has_invoker_role=true # Assume it might exist to trigger removal attempt
            fi

            if [ "$all_users_has_invoker_role" = true ]; then
                if gcloud run services remove-iam-policy-binding "${agent_service}" \
                    --member="allUsers" \
                    --role="roles/run.invoker" \
                    --region "${FINAL_REGION}" \
                    --project "${FINAL_PROJECT_ID}" \
                    --quiet; then
                    echo "✅ SUCCESS: Removed 'roles/run.invoker' for principal 'allUsers' from service '${agent_service}'."
                    echo "           Project: ${FINAL_PROJECT_ID}, Region: ${FINAL_REGION}."
                else
                    # This error (exit code 1) is expected if the binding did not exist
                    echo "ℹ️  INFO: Command to remove 'allUsers' invoker permission from '${agent_service}' completed. If the binding didn't exist, a non-zero exit code is expected. Verify manually if unsure."
                fi
            fi
        done
    else
        echo "Skipping removal of 'allUsers' invoker permissions."
    fi

    echo ""
    echo "--- Permission Configuration Summary ---"
    echo "Project:          ${FINAL_PROJECT_ID}"
    echo "Region:           ${FINAL_REGION}"
    echo "Proxy Service:    ${PROXY_SERVICE_NAME}"
    echo "Proxy SA:         ${PROXY_SERVICE_ACCOUNT_EMAIL}"
    echo ""
    echo "Permissions have been configured for the proxy service account to invoke the following agent services:"
    echo "  - ${TRANSACTION_AGENT_SERVICE_NAME}"
    echo "  - ${POLICY_AGENT_SERVICE_NAME}"
    echo "Role granted: 'roles/run.invoker'."
    if [[ "$remove_all_users_confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        echo "An attempt was made to remove public 'allUsers' invoker access from the agent services."
    else
        echo "Public 'allUsers' invoker access to agent services was not modified by this script run."
    fi
    echo "Please verify the IAM policies in the Google Cloud Console if needed."
    echo "--------------------------------------"
}

# Run the main function
main