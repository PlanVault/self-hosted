#!/usr/bin/env bash
# Validate backup artifact presence and metadata. Does not restore by default.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/backup-verify.sh <backup-directory>

Checks for expected PlanVault backup artifacts:
  - PostgreSQL dump or pg_data snapshot marker
  - encrypted .env copy
  - encrypted rendered Keycloak realm
  - VERSION metadata
  - optional Redis and observability snapshots

This validates metadata and artifact presence only. It does not perform a
disposable restore smoke test.
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

pass_count=0
warn_count=0
fail_count=0

pass() { pass_count=$((pass_count + 1)); printf 'PASS %s\n' "$*"; }
warn() { warn_count=$((warn_count + 1)); printf 'WARN %s\n' "$*"; }
fail() { fail_count=$((fail_count + 1)); printf 'FAIL %s\n' "$*"; }

has_match() {
  local pattern="$1"
  find "$BACKUP_DIR" -maxdepth 3 -type f -iname "$pattern" -print -quit | grep -q .
}

has_dir_match() {
  local pattern="$1"
  find "$BACKUP_DIR" -maxdepth 3 -type d -iname "$pattern" -print -quit | grep -q .
}

printf 'PlanVault backup verification\n'
printf 'backup: %s\n\n' "$BACKUP_DIR"

if has_match 'manifest.txt'; then
  pass "backup manifest present"
else
  warn "backup manifest missing"
fi

if has_match 'VERSION'; then
  pass "VERSION metadata present"
else
  warn "VERSION metadata missing"
fi

if has_match 'docker-compose.yml' || has_match 'compose-images.txt' || has_match 'image-digests.txt'; then
  pass "deployment metadata present"
else
  warn "deployment metadata missing (compose file or image digest list)"
fi

if has_match '*.dump' || has_match '*.sql' || has_match '*.sql.gz' || has_match 'pg_data.snapshot' || has_dir_match 'pg_data'; then
  pass "PostgreSQL backup artifact present"
else
  fail "missing PostgreSQL backup artifact (*.dump, *.sql, *.sql.gz, pg_data snapshot marker, or pg_data directory)"
fi

if has_match '.env.age' || has_match '.env.gpg' || has_match 'env.age' || has_match 'env.gpg' || has_match '.env.enc'; then
  pass "encrypted .env backup present"
elif has_match '.env'; then
  fail "plaintext .env found in backup; store encrypted only"
else
  fail "missing encrypted .env backup"
fi

if has_match 'planvault-realm.json.age' || has_match 'planvault-realm.json.gpg' || has_match 'planvault-realm.json.enc'; then
  pass "encrypted rendered Keycloak realm backup present"
elif has_match 'planvault-realm.json'; then
  fail "plaintext rendered Keycloak realm found in backup; store encrypted only"
else
  fail "missing encrypted rendered Keycloak realm backup"
fi

if has_match 'redis_data.snapshot' || has_dir_match 'redis_data' || has_match 'redis*.rdb' || has_match 'appendonly*.aof'; then
  pass "Redis backup artifact present"
else
  warn "Redis backup artifact missing; cache loss may be acceptable but should be intentional"
fi

if has_dir_match 'observability' || has_match 'grafana_data.snapshot' || has_match 'prometheus_data.snapshot' || has_match 'loki_data.snapshot' || has_match 'tempo_data.snapshot'; then
  pass "observability backup artifact present"
else
  warn "observability backup artifact missing; acceptable if overlay is not used"
fi

if has_dir_match 'tls' || has_match 'fullchain.pem' || has_match 'privkey.pem'; then
  pass "TLS artifact present"
else
  warn "TLS artifacts missing; acceptable if TLS terminates outside this repository"
fi

if find "$BACKUP_DIR" -maxdepth 3 -type f \( -iname '*.dump' -o -iname '*.sql' -o -iname '*.sql.gz' \) -size 0 -print -quit | grep -q .; then
  fail "one or more PostgreSQL dump files are empty"
else
  pass "PostgreSQL dump files are non-empty when present"
fi

printf '\nSummary: %s PASS, %s WARN, %s FAIL\n' "$pass_count" "$warn_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
