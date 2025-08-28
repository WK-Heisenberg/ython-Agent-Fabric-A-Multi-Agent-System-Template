# 🚀 A2A Python Dispute Project

[![Python Version](https://img.shields.io/badge/python-3.10-blue.svg)](https://www.python.org/downloads/release/python-3100/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=flat&logo=google-cloud&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=flat&logo=fastapi)

This project provides a complete, end-to-end reference architecture for building scalable, decoupled multi-agent systems using Python. It demonstrates a financial dispute processing workflow where an **Orchestrator** coordinates tasks between multiple specialized **Agents** that are discovered dynamically via a **Proxy**.

While the use case is a simulation, the underlying architectural framework—the "agent fabric"—is robust, extensible, and directly applicable to a wide range of real-world problems requiring the coordination of multiple intelligent or specialized services.

## ✨ Key Features

*   **Dynamic Service Discovery**: Agents are discovered at runtime via a central proxy, eliminating hardcoded dependencies.
*   **A2A Protocol Compliant**: Follows Agent-to-Agent communication patterns with `.well-known` endpoints for capability advertisement.
*   **Modular & Extensible**: Easily add new agents with distinct capabilities to the fabric.
*   **Cloud-Native Design**: Ready for deployment on Google Cloud Run with secure, token-based service-to-service authentication.
*   **Containerized**: Fully containerized with Docker and orchestrated with Docker Compose for easy local development.
*   **Clear Separation of Concerns**: Includes distinct services for Orchestration, Discovery, and Agent business logic.

## 🏛️ Architecture Overview

The system is composed of four main, decoupled services that communicate over the network.

```text
+----------+
|   User   |
+----------+
     |
     | (Initiate Dispute: Tx ID, Reason)
     v
+--------------+      (1. Discover Agents)      +--------------+
|              | -----------------------------> |              |
| Orchestrator |                              | Proxy Server |
|              | <----------------------------- |              |
+--------------+      (2. Active Agent List)    +--------------+
     |
     | (If Agents Found)
     |
     v
+--------------+   (3. Get Tx Details / Query)  +--------------------------+
|              | -----------------------------> |                          |
| Orchestrator |                              | Transaction Detail Agent |
|              | <----------------------------- |                          |
+--------------+   (4. Tx Details / Results)    +--------------------------+
     |
     | (If Tx Details Acquired)
     |
     v
+--------------+     (5. Check Policy)        +-----------------------+
|              | -----------------------------> |                       |
| Orchestrator |                              | Dispute Policy Agent  |
|              | <----------------------------- |                       |
+--------------+     (6. Policy Decision)     +-----------------------+
     |
     | (Report Outcome)
     v
+----------+
|   User   |
+----------+
     |
     | (7. Final Dispute Outcome / Error)
     v
   (End)
```

1.  Client initiates a task (e.g., a dispute).

2.  The Orchestrator asks the Proxy Server to discover available agents.

3.  The Proxy Server, which continuously polls all known agents for their status and capabilities, returns a list of active agents.

4.  The Orchestrator calls the specialized agents in sequence (e.g., first the Transaction Agent for data, then the Policy Agent for a decision).

5.  The Orchestrator consolidates the results and completes the task.

## 🛠️ Technology Stack

*   **Backend**: Python, FastAPI, Pydantic
*   **Containerization**: Docker, Docker Compose
*   **Cloud**: Google Cloud Run, Google Artifact Registry, Google Cloud Build
*   **Tooling**: `gcloud` SDK, Shell Scripts

## ⚙️ Getting Started

### Prerequisites

*   Git
*   Docker & Docker Compose
*   Google Cloud SDK (`gcloud`)
*   `jq`

### 1. Clone the Repository

```bash
git clone https://github.com/WK-Heisenberg/ython-Agent-Fabric-A-Multi-Agent-System-Template.git
cd a2a-python-dispute-project
```

### 2. Local Setup (Docker Compose) 🐳

This is the quickest way to get all services running on your local machine.

**a. Create your environment file:**
```bash
cp .env.example .env
```
The `.env` file contains default ports and URLs for local execution.

**b. Build and run the services:**
```bash
docker-compose up --build
```
The services will be available at:
*   **Proxy Server**: `http://localhost:8000`
*   **Transaction Detail Agent**: `http://localhost:8001`
*   **Dispute Policy Agent**: `http://localhost:8002`

The orchestrator will run its test script, and you can view the output in the logs.

**c. View Logs:**
```bash
docker-compose logs -f orchestrator
```

**d. Stop and Clean Up:**
```bash
docker-compose down -v
```

### 3. Cloud Deployment (Google Cloud Run) ☁️

The project includes scripts to automate deployment to Google Cloud.

**a. Configure the deployment script:**
Open `scripts/deploy_gcloud.sh` and set your `PROJECT_ID` and `REGION`.

**b. Authenticate with gcloud:**
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

**c. Run the deployment:**
```bash
chmod +x scripts/deploy_gcloud.sh
./scripts/deploy_gcloud.sh
```
This will build and deploy the agents and proxy to Cloud Run as **private** services.

**d. Configure Service-to-Service Permissions:**
By default, the deployed services are private. Run the provided script to allow the proxy to securely call the agents.
```bash
chmod +x scripts/configure_invoker_permissions.sh
./scripts/configure_invoker_permissions.sh
```

**e. Clean Up Cloud Resources:**
To avoid incurring costs, run the cleanup script when you are done.
```bash
chmod +x scripts/cleanup_gcloud.sh
./scripts/cleanup_gcloud.sh
```

## 📂 Project Structure

```
a2a-python-dispute-project/
├── .env.example
├── agent_dispute_policy/     # Agent for evaluating business rules
├── agent_transaction_detail/ # Agent for fetching data
├── docker-compose.yml
├── docs/
├── orchestrator/             # Coordinates the workflow between agents
├── proxy_server/             # Handles service discovery
└── scripts/                  # Deployment and cleanup scripts
```

## 🌐 A2A Protocol & Design

This project implements key aspects of the Agent-to-Agent (A2A) protocol to facilitate dynamic discovery and interaction.

*   **Well-Known URI for Discovery**: Each agent exposes metadata at `/.well-known/a2a/agent.json`, which describes its identity and capabilities.
*   **Dynamic Discovery via Proxy**: The Proxy Server polls these endpoints to maintain a real-time registry of active agents, which the Orchestrator queries.
*   **Capability-Based Interaction**: The Orchestrator discovers an agent's `base_url` from the proxy and then uses hardcoded knowledge of its API paths (e.g., `/get_transaction_details`) to make calls. A more advanced implementation could dynamically parse the agent's `openapi.yaml` to construct requests, making the orchestrator more generic.

This design makes the system highly extensible. To add a new agent (e.g., a "Fraud Detection Agent"), you simply create the new service, ensure it exposes the A2A discovery files, and add its URL to the proxy's configuration. The orchestrator can then be updated to incorporate this new capability into its workflow.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a pull request.

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
