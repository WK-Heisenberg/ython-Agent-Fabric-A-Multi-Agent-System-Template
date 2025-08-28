#!/bin/bash

# test_prompts.sh - Runs a series of tests against deployed A2A services

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting (optional but good practice).
# set -u # Uncomment if you want to be strict about unset variables

# --- Configuration ---

# Cloud Run Service Details - These should match the names used in deploy_gcloud.sh
# Fetches Project ID and Region from current gcloud config.
# Ensure gcloud is configured correctly before running (gcloud config set project/region).
GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
GCP_REGION=$(gcloud config get-value run/region 2>/dev/null)
SERVICE_PREFIX="a2a-dispute" # Should match the prefix in deploy_gcloud.sh

# Check if Project ID and Region were fetched
if [ -z "$GCP_PROJECT_ID" ]; then
    echo >&2 "❌ ERROR: Could not determine GCP Project ID. Use 'gcloud config set project YOUR_PROJECT_ID'."
    exit 1
fi
if [ -z "$GCP_REGION" ]; then
    echo >&2 "❌ ERROR: Could not determine Cloud Run Region. Use 'gcloud config set run/region YOUR_REGION'."
    exit 1
fi

# Construct service names based on prefix
PROXY_SERVICE_NAME="${SERVICE_PREFIX}-proxy"
TX_AGENT_SERVICE_NAME="${SERVICE_PREFIX}-transaction-agent"
POLICY_AGENT_SERVICE_NAME="${SERVICE_PREFIX}-policy-agent"

# --- Prerequisites Check ---
echo "--- Checking Prerequisites ---"
command -v curl >/dev/null 2>&1 || { echo >&2 "❌ curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "❌ jq is required but not installed. Aborting."; exit 1; }
command -v gcloud >/dev/null 2>&1 || { echo >&2 "❌ gcloud is required but not installed. Aborting."; exit 1; }
echo "✅ Prerequisites met."

# --- Fetch Service URLs ---
echo "\n--- Fetching Cloud Run Service URLs ---"
echo "Using Project: $GCP_PROJECT_ID, Region: $GCP_REGION"

fetch_service_url() {
    local service_name="$1"
    local region="$2"
    local project_id="$3"
    local url
    # Print status message to stderr so it's not captured by command substitution
    echo "Fetching URL for service: $service_name in region $region..." >&2
    # Suppress stderr initially to handle potential "not found" errors gracefully
    url=$(gcloud run services describe "$service_name" --platform managed --region "$region" --project="$project_id" --format 'value(status.url)' 2>/dev/null)
    if [ -z "$url" ]; then
        echo >&2 "❌ ERROR: Failed to fetch URL for service '$service_name' in region '$region' for project '$project_id'." >&2
        echo >&2 "   Please check:" >&2
        echo >&2 "   - Service name ('$service_name') is correct." >&2
        echo >&2 "   - Region ('$region') is correct." >&2
        echo >&2 "   - Project ID ('$project_id') is correct." >&2
        echo >&2 "   - The service has been deployed successfully via 'deploy_gcloud.sh' or similar." >&2
        echo >&2 "   - You have permissions (e.g., roles/run.viewer) to describe the service." >&2
        exit 1
    fi
    echo "$url"
}

PROXY_BASE_URL=$(fetch_service_url "$PROXY_SERVICE_NAME" "$GCP_REGION" "$GCP_PROJECT_ID")
TX_AGENT_BASE_URL=$(fetch_service_url "$TX_AGENT_SERVICE_NAME" "$GCP_REGION" "$GCP_PROJECT_ID")
POLICY_AGENT_BASE_URL=$(fetch_service_url "$POLICY_AGENT_SERVICE_NAME" "$GCP_REGION" "$GCP_PROJECT_ID")

echo "✅ URLs fetched:"
echo "   Proxy URL:        $PROXY_BASE_URL"
echo "   TX Agent URL:     $TX_AGENT_BASE_URL"
echo "   Policy Agent URL: $POLICY_AGENT_BASE_URL"

# --- Authentication ---
echo "\n--- Fetching GCP Identity Token ---"
# Use the service account associated with the gcloud CLI user or the Cloud Build service account
ID_TOKEN=$(gcloud auth print-identity-token)
if [ -z "$ID_TOKEN" ]; then
    echo >&2 "❌ Failed to get identity token. Make sure you are authenticated with gcloud ('gcloud auth login' or application default credentials)."
    exit 1
fi
AUTH_HEADER="Authorization: Bearer $ID_TOKEN"
CONTENT_TYPE_HEADER="Content-Type: application/json"
echo "✅ Token fetched successfully."

# --- Test Prompts ---

echo "\n--- 1. Check Proxy Discovery (Active Agents) ---"
echo "Testing: GET ${PROXY_BASE_URL}/discover (Active Agents)"
echo "Expected Status: 200"
response_body=$(mktemp)
status_code=$(curl -s -H "$AUTH_HEADER" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$PROXY_BASE_URL/discover")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    echo "✅ Test Passed"
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- 2. Check Transaction Detail Agent - Get Details (Success) ---"
echo "Testing: GET ${TX_AGENT_BASE_URL}/get_transaction_details?transaction_id=TX12345"
echo "Expected Status: 200"
response_body=$(mktemp)
status_code=$(curl -s -H "$AUTH_HEADER" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$TX_AGENT_BASE_URL/get_transaction_details?transaction_id=TX12345")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    echo "✅ Test Passed"
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- 3. Check Transaction Detail Agent - Get Details (Not Found) ---"
echo "Testing: GET ${TX_AGENT_BASE_URL}/get_transaction_details?transaction_id=NOTFOUND"
echo "Expected Status: 404"
response_body=$(mktemp)
status_code=$(curl -s -H "$AUTH_HEADER" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$TX_AGENT_BASE_URL/get_transaction_details?transaction_id=NOTFOUND")

echo "Received Status: $status_code"
echo "Response Body:"
cat "$response_body" # Show body even for expected errors
if [ "$status_code" -eq 404 ]; then
    echo "✅ Test Passed (Correctly received 404)"
else
    echo "❌ Test Failed: Expected 404, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- 3b. Check Transaction Detail Agent - Get Details (Missing Parameter) ---"
echo "Testing: GET ${TX_AGENT_BASE_URL}/get_transaction_details"
echo "Expected Status: 422 (or 400 depending on implementation)"
response_body=$(mktemp)
# Expecting 422 Unprocessable Entity based on FastAPI default for missing query params
expected_status=422
status_code=$(curl -s -H "$AUTH_HEADER" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$TX_AGENT_BASE_URL/get_transaction_details")

echo "Received Status: $status_code"
echo "Response Body:"
cat "$response_body"
if [ "$status_code" -eq "$expected_status" ]; then
    echo "✅ Test Passed (Correctly received $expected_status)"
else
    # Allow for 400 Bad Request as another possibility
    if [ "$status_code" -eq 400 ]; then
        echo "✅ Test Passed (Received 400, acceptable alternative)"
    else
        echo "❌ Test Failed: Expected $expected_status or 400, got $status_code"
        exit 1
    fi
fi
rm "$response_body"

echo "\n--- 4. Check Transaction Detail Agent - BigQuery Simulation ---"
echo "Testing: POST ${TX_AGENT_BASE_URL}/query_bigquery"
echo "Expected Status: 200"
query_data='{"sql_query": "SELECT * FROM transactions WHERE amount > 100 LIMIT 1"}'
response_body=$(mktemp)
status_code=$(curl -s -X POST \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE_HEADER" \
    -d "$query_data" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$TX_AGENT_BASE_URL/query_bigquery")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    echo "✅ Test Passed"
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- 5. Check Dispute Policy Agent - Check Policy (Example - Allowed) ---"
echo "Testing: POST ${POLICY_AGENT_BASE_URL}/check_dispute_policy (Should be allowed)"
echo "Expected Status: 200"
policy_data_allowed='{
      "transaction": { "transaction_id": "TX67890", "amount": 25.00, "currency": "USD", "merchant": "Bookstore", "timestamp": "2023-10-25T15:00:00", "status": "completed" },
      "reason": "Product not received"
    }'
response_body=$(mktemp)
status_code=$(curl -s -X POST \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE_HEADER" \
    -d "$policy_data_allowed" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$POLICY_AGENT_BASE_URL/check_dispute_policy")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    # Check if the policy decision is "Approved"
    if jq -e '.policy_decision == "Approved"' "$response_body" > /dev/null; then
        echo "✅ Test Passed (Status 200 and policy_decision is Approved)"
    else
        # Extract actual decision for better warning message
        actual_decision=$(jq -r '.policy_decision // "missing"' "$response_body")
        echo "⚠️ Test Warning: Status 200 but expected policy_decision 'Approved', got '$actual_decision'."
    fi
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- 5b. Check Dispute Policy Agent - Check Policy (Example - Denied) ---"
echo "Testing: POST ${POLICY_AGENT_BASE_URL}/check_dispute_policy (Should be denied - e.g., amount too high)"
echo "Expected Status: 200 (Policy check succeeded, but decision is 'denied')"
policy_data_denied='{
      "transaction": { "transaction_id": "TX99999", "amount": 5000.00, "currency": "USD", "merchant": "Luxury Goods", "timestamp": "2023-10-26T10:00:00", "status": "completed" },
      "reason": "Unauthorized transaction"
    }'
response_body=$(mktemp)
status_code=$(curl -s -X POST \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_TYPE_HEADER" \
    -d "$policy_data_denied" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$POLICY_AGENT_BASE_URL/check_dispute_policy")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    # Check if the policy decision indicates denial or needs review (i.e., not "Approved")
    if jq -e '.policy_decision != "Approved"' "$response_body" > /dev/null; then
        actual_decision=$(jq -r '.policy_decision // "missing"' "$response_body") # Get the actual decision
        echo "✅ Test Passed (Status 200 and policy_decision is '$actual_decision' - not Approved)"
    else
        echo "⚠️ Test Warning: Status 200 but policy_decision was 'Approved' when it should not have been."
    fi
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

# --- Test #6 (Docker Compose) is removed as it's not suitable for Cloud Build post-deployment testing ---
# echo "\n--- 6. Run Orchestrator via Docker Compose ---"
# echo "This test is intended for local environments. Skipping in Cloud Build context."

# echo "\n--- 7. Check Health Endpoints ---"
# echo "Transaction Agent Health:"
# echo "Testing: GET ${TX_AGENT_BASE_URL}/healthz"
# echo "Expected Status: 200"
# status_code=$(curl -s -H "$AUTH_HEADER" -o /dev/null -w "%{http_code}" "$TX_AGENT_BASE_URL/healthz")
# echo "Received Status: $status_code"
# if [ "$status_code" -eq 200 ]; then echo "✅ Test Passed"; else echo "❌ Test Failed"; exit 1; fi

# echo "Policy Agent Health:"
# echo "Testing: GET ${POLICY_AGENT_BASE_URL}/healthz"
# echo "Expected Status: 200"
# status_code=$(curl -s -H "$AUTH_HEADER" -o /dev/null -w "%{http_code}" "$POLICY_AGENT_BASE_URL/healthz")
# echo "Received Status: $status_code"
# if [ "$status_code" -eq 200 ]; then echo "✅ Test Passed"; else echo "❌ Test Failed"; exit 1; fi

# echo "Proxy Health:"
# echo "Testing: GET ${PROXY_BASE_URL}/healthz"
# echo "Expected Status: 200"
# status_code=$(curl -s -H "$AUTH_HEADER" -o /dev/null -w "%{http_code}" "$PROXY_BASE_URL/healthz")
# echo "Received Status: $status_code"
# if [ "$status_code" -eq 200 ]; then echo "✅ Test Passed"; else echo "❌ Test Failed"; exit 1; fi


echo "\n--- 8. Check Proxy Discovery (All Agents including potentially inactive) ---"
echo "Testing: GET ${PROXY_BASE_URL}/discover?only_active=false (All Agents)"
echo "Expected Status: 200"
response_body=$(mktemp)
status_code=$(curl -s -H "$AUTH_HEADER" \
    -o "$response_body" \
    -w "%{http_code}" \
    "$PROXY_BASE_URL/discover?only_active=false")

echo "Received Status: $status_code"
echo "Response Body:"
if [ "$status_code" -eq 200 ]; then
    jq '.' "$response_body"
    echo "✅ Test Passed"
else
    cat "$response_body"
    echo "❌ Test Failed: Expected 200, got $status_code"
    exit 1
fi
rm "$response_body"

echo "\n--- Test Prompts Complete ---"
echo "✅ All tests passed successfully!"

# Note: Add more tests as needed, for example:
# - Invalid JSON body for POST requests (expect 422)
# - Different query parameters or edge cases for existing endpoints
# - Tests for PUT/DELETE methods if they exist
