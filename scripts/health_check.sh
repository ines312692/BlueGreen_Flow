# scripts/health_check.sh
#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://localhost:8080/health}"
RETRIES="${2:-30}"
SLEEP_SECS="${3:-1}"

for i in $(seq 1 "$RETRIES"); do
  if curl -fsS "$URL" >/dev/null; then
    echo "Health OK: $URL"
    exit 0
  fi
  echo "Waiting for $URL ($i/$RETRIES)..."
  sleep "$SLEEP_SECS"
done

echo "Health check FAILED: $URL"
exit 1