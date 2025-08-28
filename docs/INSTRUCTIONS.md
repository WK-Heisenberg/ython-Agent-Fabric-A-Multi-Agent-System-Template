
# A2A Python Dispute Project: Deployment & Testing Instructions

This document provides instructions on how to deploy, test, and clean up resources for the A2A Transaction Dispute Orchestration project, covering both local (Docker Compose) and Google Cloud (Cloud Run) deployments.

**Directory Structure:**

```
a2a-python-dispute-project/
├── .env
├── .gitignore
├── agent_dispute_policy/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py
│       ├── models.py
│       └── well_known/
│           └── a2a/
│               ├── agent.json
│               ├── capabilities.json
│               └── openapi.yaml
├── agent_transaction_detail/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py
│       ├── models.py
│       └── well_known/
│           └── a2a/
│               ├── agent.json
│               ├── capabilities.json
│               └── openapi.yaml
├── docker-compose.yml
├── docs/
│   ├── A2A-DISPUTE-AGENT-ARCHITECTURE.md
│   └── INSTRUCTIONS.md
├── orchestrator/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── cloudbuild.yaml
│   └── app/
│       ├── client.py
│       ├── main.py
│       └── models.py
├── proxy_server/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── discovery.py
│       ├── main.py
│       └── models.py
└── scripts/
    ├── cleanup_gcloud.sh
    ├── configure_invoker_permissions.sh
    ├── deploy_gcloud.sh
    ├── deploy_local.sh
    ├── set_public_access.sh
    └── test_prompts.sh
```

## Prerequisites

1.  **Git:** To clone repository (if applicable) or manage code.
2.  **Docker:** Latest version installed.
3.  **Docker Compose:** Usually installed with Docker Desktop.
4.  **Google Cloud SDK (`gcloud`):** Installed and configured for Google Cloud deployment. (Install from [here](https://cloud.google.com/sdk/docs/install)).
5.  **`jq`:** Command-line JSON processor (for pretty-printing test output). Install it via your package manager (e.g., `brew install jq`, `sudo apt-get install jq`).
6.  **Text Editor:** For editing configuration files.
7.  **Google Cloud Project:** You need a GCP project with billing enabled to deploy to Cloud Run.

## Project Setup

Navigate to the root of the `a2a-python-dispute-project` directory in your terminal.

First, create your local environment file by copying the template:
`cp .env.example .env`

This file provides default ports and URLs for running services individually without Docker.

## I. Local Deployment (Docker Compose)

This uses `docker-compose.yml` to run all services locally within Docker containers.

### 1. Build and Run Services

From the project root directory:

```bash
docker-compose up --build -d
```

*   `--build`: Builds images if they don't exist or have changed.
*   `-d`: Runs containers in detached mode (in the background). Omit `-d` if you want to see logs directly in your terminal.

The services will be available at:
*   **Proxy Server:** `http://localhost:8000`
*   **Transaction Detail Agent:** `http://localhost:8001`
*   **Dispute Policy Agent:** `http://localhost:8002`
*   **Orchestrator:** Runs its script and exits (check logs).

### 2. View Logs

To view logs from running containers (especially if using `-d`):

```bash
docker-compose logs -f # View logs from all services
docker-compose logs -f proxy_server
docker-compose logs -f agent_transaction_detail
docker-compose logs -f agent_dispute_policy
docker-compose logs -f orchestrator # Important for seeing dispute process
```

Wait for the proxy to start polling and discover agents (should appear in `proxy_server` logs). The orchestrator log will show the dispute processing flow.

### 3. Testing Local Deployment

Use the provided `test_prompts.txt` file. You can copy and paste commands into your terminal.

```bash
# Either copy-paste from test_prompts.txt or make it executable and run:
# chmod +x test_prompts.txt
# ./test_prompts.txt # (If you add #!/bin/bash at the top of test_prompts.txt)
```

**Key things to check from `test_prompts.txt`:**

1.  **Proxy Discovery:** Does `curl http://localhost:8000/discover` show both agents as active?
2.  **Agent Endpoints:** Can you get transaction details (`:8001/get_transaction_details...`) and check policy (`:8002/check_dispute_policy...`)?
3.  **Orchestrator Output:** The `docker-compose.yml` is configured to run the orchestrator for a couple of transaction IDs. Check `docker-compose logs -f orchestrator` for:
    *   Agent discovery messages.
    *   Transaction detail fetching.
    *   Policy check calls and decisions.
    *   Final dispute outcome.

You can also manually trigger the orchestrator for different inputs:

```bash
docker-compose run --rm orchestrator python app/main.py --txid TX11223 --reason "High value review"
```

### 4. Stop and Clean Up Local Deployment

When finished with local testing:

```bash
docker-compose down -v
```

*   `down`: Stops and removes containers, networks defined in `docker-compose.yml`.
*   `-v`: Removes volumes (if any were explicitly created, though not heavily used here).

For a more thorough Docker cleanup (optional):

```bash
docker system prune -a --volumes
```

## II. Cloud Deployment (Google Cloud Run)

This uses `deploy_gcloud.sh` to build container images, push them to Google Artifact Registry, and deploy them as Cloud Run services.

### 1. Configure Deployment Script

*   **Open `deploy_gcloud.sh` in your editor.**
*   **Set `PROJECT_ID`:** Replace `"your-gcp-project-id"` with your actual Google Cloud Project ID.
*   **Set `REGION`:** Choose a desired GCP region (e.g., `us-central1`, `europe-west1`). Ensure it supports Cloud Run and Artifact Registry.

### 2. Authenticate with `gcloud`

Ensure you are authenticated:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID # Set your project ID
```

Replace `YOUR_PROJECT_ID` with the one you set in `deploy_gcloud.sh`.

### 3. Make Script Executable

```bash
chmod +x deploy_gcloud.sh
```

### 4. Run Deployment Script

Execute the deployment script from the project root:

```bash
./deploy_gcloud.sh
```

The script will:
1.  Enable necessary GCP APIs.
2.  Create an Artifact Registry repository if needed.
3.  Build and push container images for agents and proxy using Cloud Build.
4.  Deploy `agent-transaction-detail`, `agent-dispute-policy`, and `proxy-server` to Cloud Run, allowing unauthenticated access for easy testing (consider security for production).
5.  Output the URLs for the deployed Cloud Run services.

**Note:** Cloud Build and Cloud Run incur costs. Monitor your GCP billing.

### 5. Testing Cloud Deployment

The `deploy_gcloud.sh` script will output the URLs for your deployed services.

1.  **Get Proxy URL:** Note the `PROXY_SERVICE_NAME URL` from the script output. Let's call it `YOUR_CLOUD_PROXY_URL`.

2.  **Test Proxy and Agents via `curl`:** Replace `http://localhost:8000` (and other ports) in `test_prompts.txt` with your Cloud Run URLs.

    ```bash
    # Example: Test cloud proxy discovery
    curl -s YOUR_CLOUD_PROXY_URL/discover | jq

    # Example: Test transaction agent via its Cloud Run URL
    # Get agent URL from YOUR_CLOUD_PROXY_URL/discover if needed.
    # Or note it from deploy script output.
    # curl -s YOUR_TRANSACTION_AGENT_URL/get_transaction_details?transaction_id=TX12345 | jq
    ```

3.  **Run Orchestrator Locally against Cloud Proxy:**

    ```bash
    cd orchestrator
    export PROXY_URL="YOUR_CLOUD_PROXY_URL" # Use URL from deploy script output
    python app/main.py --txid TX12345 --reason "Cloud deployment test"
    python app/main.py --txid TX67890 --reason "Another cloud test"
    cd ..
    unset PROXY_URL
    ```
    Check the terminal output for successful discovery and dispute processing.

4.  **Run Orchestrator via Cloud Build (Optional):**
    The `deploy_gcloud.sh` script creates a sample `orchestrator/cloudbuild.yaml`.

    ```bash
    cd orchestrator
    gcloud builds submit --config cloudbuild.yaml \
        --project=YOUR_PROJECT_ID \
        --substitutions=_PROXY_URL="YOUR_CLOUD_PROXY_URL",_TX_ID=TX11223,_REASON="Dispute via Cloud Build"
    cd ..
    ```
    Check Cloud Build logs in the GCP Console for execution details.

## III. Resource Cleanup

It's important to delete cloud resources to avoid ongoing charges.

### 1. Local Cleanup

If you ran `docker-compose up`:

```bash
docker-compose down -v
```

### 2. Google Cloud Cleanup

1.  **Set Environment Variables (Important! Use values from `deploy_gcloud.sh`):**

    ```bash
    export PROJECT_ID="your-gcp-project-id" # <-- REPLACE with your Project ID used for deployment
    export REGION="us-central1"             # <-- REPLACE with your region used for deployment
    export SERVICE_PREFIX="a2a-dispute"
    ```

2.  **Derive Service and Repo Names:**

    ```bash
    export TRANSACTION_SERVICE_NAME="${SERVICE_PREFIX}-transaction-agent"
    export POLICY_SERVICE_NAME="${SERVICE_PREFIX}-policy-agent"
    export PROXY_SERVICE_NAME="${SERVICE_PREFIX}-proxy"
    export AR_REPO_NAME="${SERVICE_PREFIX}-repo"
    export AR_LOCATION=$REGION
    ```

3.  **Delete Cloud Run Services:**

    ```bash
    echo "Deleting Cloud Run Services..."
    gcloud run services delete $TRANSACTION_SERVICE_NAME --platform managed --region $REGION --project $PROJECT_ID --quiet || echo "Service $TRANSACTION_SERVICE_NAME not found or already deleted."
    gcloud run services delete $POLICY_SERVICE_NAME --platform managed --region $REGION --project $PROJECT_ID --quiet || echo "Service $POLICY_SERVICE_NAME not found or already deleted."
    gcloud run services delete $PROXY_SERVICE_NAME --platform managed --region $REGION --project $PROJECT_ID --quiet || echo "Service $PROXY_SERVICE_NAME not found or already deleted."
    echo "Cloud Run service deletion attempted."
    ```

4.  **Delete Artifact Registry Repository (Deletes all images within):**

    ```bash
    echo "Deleting Artifact Registry Repository: $AR_REPO_NAME..."
    gcloud artifacts repositories delete $AR_REPO_NAME \
        --location=$AR_LOCATION \
        --project=$PROJECT_ID \
        --quiet || echo "Repository $AR_REPO_NAME not found or failed to delete (maybe it has images still being referenced)."
    echo "Artifact Registry repository deletion attempted."
    ```
    *Note:* If repository deletion fails, you might need to manually delete images inside it first via GCP console or `gcloud artifacts docker images delete...`.

5.  **Review Cloud Build History (Optional):** Check GCP Console under Cloud Build for build logs and optionally delete them if no longer needed. They might have associated storage costs.

## Troubleshooting

*   **Local Port Conflicts:** If ports `8000`, `8001`, or `8002` are in use, stop the conflicting service or change ports in `.env` and `docker-compose.yml`.
*   **`gcloud` Permissions:** Ensure your user/service account has roles like `roles/run.admin`, `roles/storage.admin` (for Cloud Build artifacts), `roles/artifactregistry.admin`, and `roles/cloudbuild.builds.editor`.
*   **Proxy Not Discovering Agents (Docker Compose):** Check `AGENT_URLS` in `docker-compose.yml` for `proxy_server` service uses correct service names (`agent_transaction_detail:8001`, `agent_dispute_policy:8002`). Check proxy logs.
*   **Proxy Not Discovering Agents (Cloud Run):** Ensure correct Cloud Run service URLs were passed to the proxy during its deployment via `AGENT_URLS` in `deploy_gcloud.sh`. Check proxy logs in Cloud Run.
*   **Orchestrator Failures:** Check orchestrator logs. Is `PROXY_URL` correct? Can it reach the proxy? Are agents discovered?
