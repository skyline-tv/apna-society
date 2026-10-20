#!/usr/bin/env bash
# Concurrent smoke load against a running backend. Does not invent results.
# Usage:
#   BASE_URL=http://127.0.0.1:4000 CONCURRENCY=50 REQUESTS=500 ./scripts/load-smoke.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"
CONCURRENCY="${CONCURRENCY:-20}"
REQUESTS="${REQUESTS:-200}"
PATHS=("/health" "/api/v1/ready")

echo "Load smoke: ${REQUESTS} requests, concurrency ${CONCURRENCY}, target ${BASE_URL}"

node --input-type=module <<'EOF'
const base = process.env.BASE_URL || 'http://127.0.0.1:4000';
const concurrency = Number(process.env.CONCURRENCY || 20);
const total = Number(process.env.REQUESTS || 200);
const paths = ['/health', '/api/v1/ready'];

const latencies = [];
let errors = 0;
let completed = 0;

async function one(i) {
  const path = paths[i % paths.length];
  const start = performance.now();
  try {
    const res = await fetch(`${base}${path}`);
    latencies.push(performance.now() - start);
    if (!res.ok) errors += 1;
  } catch {
    errors += 1;
    latencies.push(performance.now() - start);
  } finally {
    completed += 1;
  }
}

const workers = Array.from({ length: concurrency }, async (_, workerId) => {
  for (let i = workerId; i < total; i += concurrency) {
    await one(i);
  }
});

await Promise.all(workers);
latencies.sort((a, b) => a - b);
const pct = (p) => latencies[Math.min(latencies.length - 1, Math.floor((p / 100) * latencies.length))];
console.log(JSON.stringify({
  completed,
  errors,
  errorRate: completed ? errors / completed : 1,
  p50Ms: Number(pct(50).toFixed(2)),
  p95Ms: Number(pct(95).toFixed(2)),
  p99Ms: Number(pct(99).toFixed(2)),
}, null, 2));
if (errors / completed > 0.05) {
  console.error('Error rate exceeded 5%');
  process.exit(1);
}
EOF
