#!/usr/bin/env bash
# Automated MongoDB backup for Apna Society backend-v2.
# Never runs against a host unless MONGODB_URI / BACKUP_* are set by the operator.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${BACKUP_ROOT}/${STAMP}"

if [[ -z "${MONGODB_URI:-}" ]]; then
  echo "MONGODB_URI is required" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
echo "Backing up to ${OUT_DIR}"

mongodump \
  --uri="${MONGODB_URI}" \
  --gzip \
  --archive="${OUT_DIR}/apna_society.archive.gz"

# Optional integrity marker (size > 0)
SIZE="$(wc -c < "${OUT_DIR}/apna_society.archive.gz" | tr -d ' ')"
if [[ "${SIZE}" -lt 64 ]]; then
  echo "Backup archive looks empty (${SIZE} bytes)" >&2
  exit 1
fi

echo "${STAMP}" > "${OUT_DIR}/COMPLETE"
echo "Backup complete (${SIZE} bytes)"

# Retention: delete completed backups older than RETENTION_DAYS
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -print0 \
  | while IFS= read -r -d '' dir; do
      if [[ -f "${dir}/COMPLETE" ]]; then
        echo "Removing expired backup ${dir}"
        rm -rf "${dir}"
      fi
    done
