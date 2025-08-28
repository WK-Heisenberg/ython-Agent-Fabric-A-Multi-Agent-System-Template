# orchestrator/app/main.py
import asyncio
import os
import argparse
import logging
from dotenv import load_dotenv

from .client import A2AClient
from .models import TransactionDetails as OrchestratorTxDetails

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("Orchestrator")

if os.path.exists("../../.env"):
    load_dotenv(dotenv_path="../../.env")
    logger.info(".env file loaded for orchestrator.")

async def process_dispute_request(proxy_url: str, transaction_id: str, reason: str):
    logger.info(f"--- Starting Dispute Process for Tx: {transaction_id} ---")
    a2a_client = A2AClient(proxy_url=proxy_url)
    required_agents = ["Transaction_Detail_Agent", "Dispute_Policy_Agent"]
    dispute_outcome = "Failed: Could not complete process."

    try:
        logger.info(f"1. Discovering agents via Proxy: {proxy_url}")
        if not await a2a_client.discover_agents(required_agent_ids=required_agents):
            logger.error("Failed to discover all required agents. Aborting.")
            dispute_outcome = "Failed: Required agents not found."
            return dispute_outcome

        logger.info("2. Fetching Transaction Details...")
        transaction_details = await a2a_client.get_transaction_details(transaction_id)

        if not transaction_details:
            logger.warning(f"Transaction details not found for {transaction_id}. Trying BigQuery as fallback.")
            bq_response = await a2a_client.query_transactions(f"SELECT * FROM transactions WHERE transaction_id = '{transaction_id}' LIMIT 1")
            if bq_response and bq_response.results:
                logger.info("Found transaction via simulated BigQuery.")
                # Assuming first result is the one we want and fits TransactionDetails
                try:
                    transaction_details_dict = bq_response.results[0]
                    transaction_details = OrchestratorTxDetails(**transaction_details_dict)

                except Exception as e:
                    logger.error(f"Could not map BQ result to TransactionDetails: {e}")
                    transaction_details = None

            if not transaction_details:
                logger.error(f"Could not retrieve transaction details for {transaction_id} via any method.")
                dispute_outcome = f"Failed: Transaction {transaction_id} details not found."
                return dispute_outcome
        else:
             logger.info(f"Transaction details found for {transaction_id}: Amount={transaction_details.amount} {transaction_details.currency}, Merchant='{transaction_details.merchant}'")

        logger.info("3. Checking Dispute Policy...")
        policy_result = await a2a_client.check_dispute_policy(transaction_details, reason)

        if policy_result:
            logger.info(f"Policy Decision: {policy_result.policy_decision}")
            logger.info(f"Reasoning: {policy_result.reasoning}")
            if policy_result.next_steps:
                logger.info(f"Next Steps: {policy_result.next_steps}")
            dispute_outcome = f"Success: Dispute for {transaction_id} - Decision: {policy_result.policy_decision}."
        else:
            logger.error("Failed to get policy check result.")
            dispute_outcome = f"Failed: Could not get policy check for {transaction_id}."

    except Exception as e:
        logger.error(f"An error occurred during dispute processing: {e}", exc_info=True)
        dispute_outcome = f"Failed: Unexpected error during processing for {transaction_id}."
    finally:
        await a2a_client.close()
        logger.info(f"--- Dispute Process Finished for Tx: {transaction_id}. Outcome: {dispute_outcome} ---")

    return dispute_outcome

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run Transaction Dispute Orchestrator")
    parser.add_argument("--txid", help="Transaction ID to dispute", default=os.getenv("TEST_TX_ID", "TX12345"))
    parser.add_argument("--reason", help="Reason for dispute", default=os.getenv("TEST_REASON", "Duplicate charge"))

    args = parser.parse_args()

    proxy_url_env = os.getenv("PROXY_URL")
    if not proxy_url_env:
        logger.error("PROXY_URL environment variable not set. Cannot run orchestrator.")
        exit(1)

    logger.info(f"Running dispute for Transaction ID: {args.txid} with Reason: '{args.reason}' using Proxy: {proxy_url_env}")
    asyncio.run(process_dispute_request(proxy_url=proxy_url_env, transaction_id=args.txid, reason=args.reason))

    # Example of another call using BQ path
    logger.info("\n--- Running dispute for high value Tx: TX11223 (Unauthorized) ---")
    asyncio.run(process_dispute_request(proxy_url=proxy_url_env, transaction_id="TX11223", reason="Unauthorized charge on card"))