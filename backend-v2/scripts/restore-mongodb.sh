#!/usr/bin/env bash
# Restore a mongodump archive into a TARGET database URI.
# SAFETY: refuses to run when TARGET looks like the live production URI unless
# RESTORE_CONFIRM=YES is set. Prefer restoring into a separate verification DB.
set -euo pipefail

ARCHIVE="${1:-}"
TARGET_URI="${RESTORE_MONGODB_URI:-${MONGODB_URI:-}}"

if [[ -z "${ARCHIVE}" || ! -f "${ARCHIVE}" ]]; then
  echo "Usage: $0 /path/to/apna_society.archive.gz" >&2
  echo "Set RESTORE_MONGODB_URI to the destination (prefer a non-production DB)." >&2
  exit 1
fi

if [[ -z "${TARGET_URI}" ]]; then
  echo "RESTORE_MONGODB_URI or MONGODB_URI is required" >&2
  exit 1
fi

if [[ "${RESTORE_CONFIRM:-}" != "YES" ]]; then
  echo "Refusing restore without RESTORE_CONFIRM=YES" >&2
  echo "Example:" >&2
  echo "  RESTORE_CONFIRM=YES RESTORE_MONGODB_URI='mongodb://localhost:27017/apna_society_restore?replicaSet=rs0' $0 ${ARCHIVE}" >&2
  exit 1
fi

echo "Restoring ${ARCHIVE} -> ${TARGET_URI}"
mongorestore \
  --uri="${TARGET_URI}" \
  --gzip \
  --archive="${ARCHIVE}" \
  --drop

echo "Restore finished. Verify application health against the restore URI before promoting."
