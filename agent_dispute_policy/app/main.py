# agent_dispute_policy/app/main.py
import os
import logging
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import uuid
import yaml

from .models import DisputePolicyCheckRequest, DisputePolicyCheckResponse, HealthResponse, PolicyDecisionEnum

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Dispute Policy Agent",
    description="Applies dispute policies to transactions.",
    version="0.1.0"
)

# --- Pydantic models defined in models.py ---

# --- Static files for .well-known/a2a ---
well_known_path = Path(__file__).parent / "well_known"
openapi_path = well_known_path / "a2a" / "openapi.yaml"

if openapi_path.exists():
    with open(openapi_path, 'r', encoding='utf-8') as f:
        openapi_spec = yaml.safe_load(f)
    app.openapi_schema = openapi_spec
else:
    logger.warning(f"OpenAPI spec not found at {openapi_path}")

app.mount("/.well-known", StaticFiles(directory=well_known_path, html=True), name="well-known")

@app.get("/healthz", response_model=HealthResponse, tags=["Health"])
async def health_check():
    return HealthResponse(status="ok")

@app.post("/check_dispute_policy",
           response_model=DisputePolicyCheckResponse,
           summary="Check Dispute Policy",
           operation_id="check_dispute_policy_post",
           tags=["A2ACapabilities"])
async def check_dispute_policy(request: DisputePolicyCheckRequest):
    """
    Checks if a dispute aligns with company policy based on transaction details and reason.
    """
    dispute_id = f"DISPUTE-{uuid.uuid4().hex[:8].upper()}"
    transaction = request.transaction
    reason = request.reason
    logger.info(f"Checking policy for Tx: {transaction.transaction_id}, Reason: {reason}, Amount: {transaction.amount}")

    decision = PolicyDecisionEnum.NEEDS_REVIEW
    reasoning = "Default decision: Further review required."
    next_steps = "Assign to dispute resolution team."

    if transaction.amount < 10 and "not received" not in reason.lower():
        decision = PolicyDecisionEnum.APPROVED
        reasoning = f"Auto-approved: Low transaction amount (${transaction.amount:.2f}) and acceptable reason."
        next_steps = "Refund processed automatically (simulated)."
    elif transaction.amount < 50 and ("duplicate" in reason.lower() or "not received" in reason.lower()):
        decision = PolicyDecisionEnum.APPROVED
        reasoning = f"Auto-approved: Transaction amount (${transaction.amount:.2f}) under threshold for reason '{reason}'."
        next_steps = "Refund processed automatically (simulated)."
    elif transaction.amount >= 500:
        decision = PolicyDecisionEnum.NEEDS_REVIEW
        reasoning = f"High value transaction (${transaction.amount:.2f}). Manual review required."
        next_steps = "Escalate to senior dispute agent."
    elif "unauthorized" in reason.lower():
        decision = PolicyDecisionEnum.NEEDS_REVIEW
        reasoning = f"Potential unauthorized transaction. Requires fraud check."
        next_steps = "Forward to fraud department and request more info from customer."
    elif transaction.status == "pending":
        decision = PolicyDecisionEnum.REJECTED
        reasoning = "Dispute rejected: Transaction is still pending and not completed."
        next_steps = "Advise customer to wait for transaction completion."

    return DisputePolicyCheckResponse(
        dispute_id=dispute_id,
        transaction_id=transaction.transaction_id,
        policy_decision=decision,
        reasoning=reasoning,
        next_steps=next_steps
    )

if __name__ == "__main__":
    import uvicorn
    from dotenv import load_dotenv
    load_dotenv(dotenv_path="../../.env")
    port = int(os.getenv("AGENT_POLICY_PORT", 8002))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")