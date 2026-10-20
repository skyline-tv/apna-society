#!/usr/bin/env bash
# Run a k6 profile against local/staging only.
# Usage:
#   PROFILE=smoke SCENARIO=health ./scripts/load-k6.sh
#   PROFILE=normal SCENARIO=admin-reads LOAD_TEST_ACCESS_TOKEN=... BASE_URL=http://127.0.0.1:4000 ./scripts/load-k6.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-smoke}"
SCENARIO="${SCENARIO:-health}"
BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"

if [[ "${BASE_URL}" == *"production"* ]] || [[ "${BASE_URL}" == *"apnasociety.com"* ]]; then
  echo "Refusing to run load tests against a production-looking BASE_URL: ${BASE_URL}" >&2
  exit 1
fi

# Preflight: refuse to invent results when nothing is listening.
if ! curl -fsS --max-time 2 "${BASE_URL}/health" >/dev/null 2>&1; then
  echo "Load target not reachable at ${BASE_URL}." >&2
  echo "Start local/staging API first (e.g. npm run dev or docker compose up)." >&2
  echo "No benchmark numbers recorded." >&2
  exit 2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "k6 is not installed. Install: https://k6.io/docs/get-started/installation/" >&2
  echo "Falling back to Node health smoke (scripts/load-smoke.sh)." >&2
  BASE_URL="${BASE_URL}" CONCURRENCY=20 REQUESTS=100 bash "${ROOT}/scripts/load-smoke.sh"
  exit $?
fi

SCRIPT="${ROOT}/load/k6/scenarios/${SCENARIO}.js"
if [[ ! -f "${SCRIPT}" ]]; then
  echo "Unknown scenario: ${SCENARIO}" >&2
  echo "Available: health auth admin-reads resident-reads payments-mock" >&2
  exit 1
fi

echo "k6 profile=${PROFILE} scenario=${SCENARIO} base=${BASE_URL}"
exec k6 run \
  -e "PROFILE=${PROFILE}" \
  -e "BASE_URL=${BASE_URL}" \
  -e "LOAD_TEST_EMAIL=${LOAD_TEST_EMAIL:-}" \
  -e "LOAD_TEST_OTP=${LOAD_TEST_OTP:-}" \
  -e "LOAD_TEST_ACCESS_TOKEN=${LOAD_TEST_ACCESS_TOKEN:-}" \
  -e "LOAD_TEST_BILL_ID=${LOAD_TEST_BILL_ID:-}" \
  "${SCRIPT}"
