## A2A Python Dispute Project: Functionality and Multi-Agent Architecture Template

This document details the functionality of the A2A Python Dispute Project and explains how its design can serve as a template for implementing multi-agent architectures using the Agent-to-Agent (A2A) communication protocol.

### Overall Project Functionality

The project demonstrates a system for processing transaction disputes through a collaboration of specialized, independent agents. An orchestrator initiates a dispute request, which is then handled by various agents whose capabilities are discovered and invoked dynamically via a proxy server. The core workflow involves:

1.  **Initiation**: An orchestrator receives a transaction ID and a reason for a dispute.
2.  **Discovery**: The orchestrator queries a proxy server to find available and active agents required for processing the dispute (e.g., an agent for transaction details and an agent for policy checks).
3.  **Information Gathering**: The orchestrator, using the information from the proxy, calls the Transaction Detail Agent to fetch details about the disputed transaction. This agent can retrieve mock data or simulate a query to a database like BigQuery.
4.  **Policy Evaluation**: The orchestrator then sends the transaction details and the dispute reason to the Dispute Policy Agent, which evaluates the dispute against predefined company policies.
5.  **Outcome**: The orchestrator receives the policy decision and logs the outcome of the dispute process.

The system is designed to be deployable both locally using Docker Compose and on Google Cloud Platform using Cloud Run. Shell scripts are provided for deployment, testing, and cleanup.

### Component Breakdown

The project is composed of four main services:

#### 1. Transaction Detail Agent (`agent_transaction_detail`)

* **Purpose**: Provides details for a given transaction ID and can simulate querying a larger transaction database (e.g., BigQuery).
* **Functionality**:
    * Exposes an HTTP endpoint (e.g., `/get_transaction_details`) to retrieve transaction information based on an ID.
    * Includes a mock database of transactions.
    * Offers an endpoint (e.g., `/query_bigquery`) to simulate SQL-like queries.
    * Advertises its capabilities through A2A discovery files (`/.well-known/a2a/agent.json`, `/.well-known/a2a/capabilities.json`, `/.well-known/a2a/openapi.yaml`).
* **Key Files**:
    * `app/main.py`: Defines the FastAPI application, endpoints, and logic.
    * `app/models.py`: Contains Pydantic models for request and response data structures.
    * `app/well_known/a2a/`: Directory for A2A service discovery metadata.

#### 2. Dispute Policy Agent (`agent_dispute_policy`)

* **Purpose**: Evaluates a transaction dispute against a set of predefined policies to determine if it should be approved, rejected, or needs further review.
* **Functionality**:
    * Exposes an HTTP endpoint (e.g., `/check_dispute_policy`) that accepts transaction details and a dispute reason.
    * Implements logic to make a policy decision (e.g., based on transaction amount, reason, status).
    * Returns a decision, reasoning, and potential next steps.
    * Advertises its capabilities using A2A discovery files.
* **Key Files**:
    * `app/main.py`: Defines the FastAPI application, policy checking endpoint, and logic.
    * `app/models.py`: Contains Pydantic models for request and response data structures.
    * `app/well_known/a2a/`: Directory for A2A service discovery metadata.

#### 3. Proxy Server (`proxy_server`)

* **Purpose**: Acts as a service discovery mechanism. It polls registered agents to check their health and discover their capabilities, providing a central point for other services (like the orchestrator) to find active agents.
* **Functionality**:
    * Periodically polls a list of configured agent URLs to fetch their `agent.json` files from the `/.well-known/a2a/` path.
    * Maintains a list of active and reachable agents.
    * Exposes an HTTP endpoint (e.g., `/discover`) that returns information about the discovered agents.
    * Handles authentication when polling agents, for instance, by fetching GCP Identity Tokens if running in a GCP environment.
* **Key Files**:
    * `app/main.py`: Defines the FastAPI application and the `/discover` endpoint.
    * `app/discovery.py`: Contains the logic for continuous polling of agents, liveness checks, and managing the list of active agents.
    * `app/models.py`: Defines Pydantic models for agent information.

#### 4. Orchestrator (`orchestrator`)

* **Purpose**: Manages the overall dispute resolution process by coordinating calls to the various agents.
* **Functionality**:
    * Takes a transaction ID and dispute reason as input.
    * Contacts the Proxy Server to discover the necessary agents (Transaction Detail Agent and Dispute Policy Agent).
    * Calls the Transaction Detail Agent to get information about the transaction.
    * Calls the Dispute Policy Agent with the transaction details and reason to get a policy decision.
    * Logs the final outcome of the dispute.
* **Key Files**:
    * `app/main.py`: Contains the main script for processing a dispute request, including argument parsing and initiating the A2A client.
    * `app/client.py`: Implements the `A2AClient` class responsible for interacting with the proxy and the individual agents.
    * `app/models.py`: Defines Pydantic models used by the orchestrator to structure data for agent communication.

### A2A Protocol Implementation Details

The project implements key aspects of the A2A (Agent-to-Agent) protocol, facilitating dynamic discovery and interaction between services:

* **Well-Known URI for Discovery**: Each agent (Transaction Detail and Dispute Policy) exposes metadata at a standard path: `/.well-known/a2a/`.
    * `agent.json`: Provides basic information about the agent, such as its ID, name, description, and the URL to its capabilities document.
    * `capabilities.json`: Lists the specific capabilities or functions the agent offers, including an ID for each capability and a link to the relevant part of its OpenAPI specification.
    * `openapi.yaml`: An OpenAPI (formerly Swagger) specification that formally defines the API endpoints, request/response schemas, and operation IDs for the agent's capabilities. This allows for standardized machine-readable API descriptions.

* **Dynamic Discovery via Proxy**:
    * The Proxy Server is responsible for discovering agents. It polls the `/.well-known/a2a/agent.json` endpoint of pre-configured agent base URLs.
    * This allows the system to be flexible; new agents can be added or existing ones updated, and the proxy will dynamically discover these changes as long as they adhere to the A2A discovery conventions.
    * The Orchestrator queries the Proxy Server's `/discover` endpoint to get the current list of active agents and their base URLs.

* **Capability-Based Interaction**:
    * The A2A protocol facilitates capability-based interaction by providing metadata in `capabilities.json` and a formal API definition in `openapi.yaml`. This allows a consumer to dynamically understand and call an agent's functions.
    * For simplicity in this template project, the `A2AClient` in the Orchestrator uses a more direct approach. It discovers the `base_url` of an agent from the proxy, but then uses hardcoded knowledge of the API paths (e.g., `/get_transaction_details`, `/check_dispute_policy`) to make calls.
    * This is a common and valid pattern for systems where the orchestrator and agents are developed in tandem. A more advanced implementation could be extended to dynamically parse the `openapi.yaml` to construct requests, making the orchestrator more generic and adaptable to unknown agents.

### Using the Project as a Template for Multi-Agent Architectures

This project serves as an excellent template for building more complex multi-agent systems due to its modularity, reliance on standardized discovery, and clear separation of concerns:

1.  **Modular Agent Design**:
    * Each agent is a self-contained service with specific responsibilities (e.g., fetching transaction data, applying policies).
    * **To create a new agent**:
        * Develop the core logic for the agent's specific task.
        * Implement it as a FastAPI (or similar) service.
        * Define its data models (requests/responses) using Pydantic.
        * Crucially, create the A2A discovery files:
            * `agent.json` describing the agent.
            * `capabilities.json` listing its functions.
            * `openapi.yaml` detailing its API.
        * Ensure the new agent is added to the list of URLs the Proxy Server polls (e.g., via environment variables).

2.  **Extensible Proxy for Service Discovery**:
    * The Proxy Server handles the discovery of any agent that conforms to the `/.well-known/a2a/` convention.
    * This decouples agents from each other; they only need to know about the proxy (or be discoverable by it) rather than having direct knowledge of every other agent's location.

3.  **Flexible Orchestration**:
    * The Orchestrator's logic can be adapted to different workflows.
    * New sequences of agent interactions can be designed by modifying the `A2AClient` or the main orchestration flow in `orchestrator/app/main.py` to call different agents or capabilities based on the task.
    * For example, a new dispute type might require an additional "Fraud Check Agent." The orchestrator could be updated to discover and call this new agent as part of its workflow.

4.  **Standardized Communication**:
    * The use of HTTP/REST APIs, JSON for data exchange, and OpenAPI for API definition promotes interoperability.
    * New agents written in different languages could still integrate into the system as long as they expose capabilities via the A2A protocol.

5.  **Scalability and Resilience**:
    * Individual agents can be scaled independently (especially when deployed on platforms like Cloud Run).
    * The proxy's liveness checks allow the system to be aware of unresponsive agents, and an orchestrator could potentially implement fallback logic or retry mechanisms.

**Steps to Adapt as a Template:**

1.  **Define New Agent Roles**: Identify the distinct functionalities required for your multi-agent system. Each distinct function or data source can become a new agent.
2.  **Implement New Agents**: For each new role:
    * Follow the structure of `agent_transaction_detail` or `agent_dispute_policy`.
    * Implement its unique logic.
    * Provide the A2A discovery files (`agent.json`, `capabilities.json`, `openapi.yaml`).
3.  **Update Proxy Configuration**: Ensure the Proxy Server is configured to poll the base URLs of your new agents. This is typically done via the `AGENT_URLS` environment variable.
4.  **Modify or Create New Orchestrators**:
    * If the overall workflow changes significantly, you might create a new orchestrator service.
    * If extending an existing workflow, modify the existing `A2AClient` and orchestration logic to incorporate calls to the new agents' capabilities.
5.  **Deployment**: Utilize the provided `docker-compose.yml` for local development and testing, and `deploy_gcloud.sh` [cite: 4] as a basis for cloud deployment of the new multi-agent system.

By following these patterns, the A2A Python Dispute Project provides a solid foundation for building robust, scalable, and maintainable multi-agent systems where services can be dynamically discovered and composed to achieve complex tasks.

## A2A Python Dispute Project: Interaction Flow (Textual Representation)

This describes the sequence of interactions between the components.

### I. Background Process: Agent Discovery & Liveness (Continuous Polling)

This process runs continuously, managed by the Proxy Server.

**Proxy Server Logic:**
*   Periodically sends `GET` requests to the `/.well-known/a2a/agent.json` endpoint of each configured agent (Transaction Detail Agent, Dispute Policy Agent).
*   Receives `agent.json` metadata from the agents.
*   Updates its internal list of active and available agents and their capabilities.

**Visual Representation:**
```text
+-----------------+        (Polls agent.json)        +--------------------------+
|                 | ---------------------------------> | Transaction Detail Agent |
|  Proxy Server   | <--------------------------------- |  (Responds with info)    |
|                 |                                    +--------------------------+
|                 |                                    
|                 |        (Polls agent.json)        +-----------------------+
|                 | ---------------------------------> | Dispute Policy Agent  |
|                 | <--------------------------------- | (Responds with info)  |
+-----------------+                                    +-----------------------+
```

### II. Main Dispute Processing Flow

This flow is initiated when a user (or an external system) starts a dispute.

1.  **User/System -> Orchestrator:**
    *   **Action:** Initiate Dispute
    *   **Provides:** Transaction ID, Reason for Dispute

2.  **Orchestrator -> Proxy Server:**
    *   **Request:** Discover Agents (e.g., HTTP `GET` to `/discover`)
    *   **Sends:** Request for available agents, potentially specifying required agent IDs.

3.  **Proxy Server -> Orchestrator:**
    *   **Response:** List of Active Agents
    *   **Provides:** Base URLs, capabilities information for agents like "Transaction_Detail_Agent" and "Dispute_Policy_Agent".
    *   *Note:* If required agents are not found, the Orchestrator may terminate the process and report failure to the User.

4.  **Orchestrator -> Transaction Detail Agent:**
    *   **Request:** Get Transaction Details (e.g., HTTP `GET` to `/get_transaction_details`)
    *   **Sends:** `transaction_id`

5.  **Transaction Detail Agent -> Orchestrator:**
    *   **Response:** Transaction Details (JSON data: amount, merchant, timestamp, etc.)
    *   *Or:* An error if the transaction is not found.

6.  **Fallback (if direct lookup fails and a query mechanism exists):**
    *   **Orchestrator -> Transaction Detail Agent:**
        *   **Request:** Query Transactions (e.g., HTTP `POST` to `/query_bigquery`)
        *   **Sends:** SQL-like query string (e.g., `SELECT * FROM transactions WHERE transaction_id = '...'`)
    *   **Transaction Detail Agent -> Orchestrator:**
        *   **Response:** Query Results (JSON data: list of transactions matching the query)
    *   *Note:* The Orchestrator then extracts the required transaction details. If transaction details cannot be retrieved by any method, the Orchestrator terminates and reports failure.

7.  **Orchestrator -> Dispute Policy Agent:**
    *   **Request:** Check Dispute Policy (e.g., HTTP `POST` to `/check_dispute_policy`)
    *   **Sends:** Transaction Details (obtained in step 5/6), Reason for Dispute

8.  **Dispute Policy Agent -> Orchestrator:**
    *   **Response:** Policy Decision
    *   **Provides:** (JSON data) `policy_decision` (e.g., "Approved", "Rejected", "NeedsReview"), `reasoning`, `next_steps`.
    *   *Or:* An error if the policy check fails for some reason.

9.  **Orchestrator -> User/System:**
    *   **Report:** Dispute Outcome
    *   **Provides:** Final status of the dispute based on the policy decision (e.g., "Success: Dispute for TX12345 - Decision: Approved.").
    *   *Note:* If any step failed (e.g., agents not discovered, transaction not found, policy check error), a failure outcome is reported.

### Visual Representation:

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
