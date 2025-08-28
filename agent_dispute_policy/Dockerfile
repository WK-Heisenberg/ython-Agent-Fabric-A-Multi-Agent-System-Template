# agent_dispute_policy/Dockerfile
FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY ./app /app/app

# Create a non-root user and switch to it.
# This is a security best practice to avoid running as root.
RUN adduser --system --group appuser
USER appuser

# Make port configurable through environment variable, default to 8002
ENV PORT 8002

EXPOSE $PORT

CMD uvicorn app.main:app --host 0.0.0.0 --port $PORT