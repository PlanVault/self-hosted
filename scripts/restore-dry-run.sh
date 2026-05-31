#!/usr/bin/env bash
# Validate a backup directory and print the manual restore sequence. Does not restore data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/restore-dry-run.sh <backup-directory>

Validates backup artifacts and prints the conservative manual restore order.
This script is read-only: it does not stop containers, overwrite volumes, or
restore databases.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  printf 'FAIL backup directory not found: %s\n' "$BACKUP_DIR"
  exit 1
fi

"${SCRIPT_DIR}/backup-verify.sh" "$BACKUP_DIR"

cat <<EOF

Restore dry run passed for:
  ${BACKUP_DIR}

Manual restore order:
  1. Provision a clean host with Docker Engine 24+ and Compose v2.
  2. Check out this self-hosted repository at the VERSION recorded in the backup.
  3. Decrypt .env and planvault-realm.json locally; do not paste them into tickets.
  4. Restore .env, VERSION, and init/planvault-realm.json into the repository.
  5. Restore PostgreSQL from pg_data snapshot or the custom-format pg_dump.
  6. Restore redis_data if present and required for your RPO.
  7. Restore TLS and observability volumes if used.
  8. Pull pinned images and start dependencies, jobs, then the full stack.
  9. Run scripts/smoke-test.sh and record elapsed restore time.

This dry run does not prove the database dump is restorable. Use a disposable
host restore test before claiming production RPO/RTO.
EOF

printf 'Repository root checked by dry run: %s\n' "$ROOT_DIR" >/dev/null
