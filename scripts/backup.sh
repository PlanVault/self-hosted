#!/usr/bin/env bash
# Create a local PlanVault backup bundle without printing secrets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_BASE="${1:-${ROOT_DIR}/backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${OUT_BASE}/planvault-backup-${STAMP}"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
warn() { log "WARN: $*"; }

read_env_value() {
  local key="$1"
  local raw
  raw="$(awk -v k="$key" '
    index($0, k "=") == 1 {
      print substr($0, length(k) + 2)
      found = 1
      exit
    }
    END { if (!found) exit 2 }
  ' "$ENV_FILE" 2>/dev/null)" || return 1

  if [[ "$raw" == \"*\" && "$raw" == *\" ]]; then
    printf '%s' "${raw:1:${#raw}-2}"
  elif [[ "$raw" == \'*\' && "$raw" == *\' ]]; then
    printf '%s' "${raw:1:${#raw}-2}"
  else
    printf '%s' "$raw"
  fi
}

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
  fi
}

copy_encrypted_secret() {
  local src="$1"
  local logical_name="$2"
  local dest_name

  [[ -n "$src" ]] || return 1
  [[ -f "$src" ]] || die "encrypted ${logical_name} file not found: ${src}"

  case "$src" in
    *.gpg) dest_name="${logical_name}.gpg" ;;
    *.enc) dest_name="${logical_name}.enc" ;;
    *) dest_name="${logical_name}.age" ;;
  esac

  cp "$src" "${BACKUP_DIR}/sensitive/${dest_name}"
}

command -v docker >/dev/null 2>&1 || die "docker is required"
[[ -f "$ENV_FILE" ]] || die ".env missing; run scripts/generate-secrets.sh first"

mkdir -p \
  "${BACKUP_DIR}/postgres" \
  "${BACKUP_DIR}/redis" \
  "${BACKUP_DIR}/metadata" \
  "${BACKUP_DIR}/sensitive"

db_user="$(read_env_value DB_USER_SUPERUSER || true)"
[[ -n "$db_user" ]] || die ".env missing DB_USER_SUPERUSER"

log "Creating PostgreSQL dump..."
docker compose --env-file "$ENV_FILE" exec -T postgres \
  pg_dump -U "$db_user" -d planvault --format=custom \
  >"${BACKUP_DIR}/postgres/planvault.dump"

if [[ ! -s "${BACKUP_DIR}/postgres/planvault.dump" ]]; then
  die "PostgreSQL dump is empty"
fi

log "Capturing deployment metadata..."
copy_if_exists "${ROOT_DIR}/VERSION" "${BACKUP_DIR}/metadata/VERSION"
copy_if_exists "${ROOT_DIR}/docker-compose.yml" "${BACKUP_DIR}/metadata/docker-compose.yml"
copy_if_exists "${ROOT_DIR}/docker-compose.observability.yml" "${BACKUP_DIR}/metadata/docker-compose.observability.yml"

{
  printf 'created_at_utc=%s\n' "$STAMP"
  printf 'backup_format=planvault-self-hosted-v1\n'
  printf 'root=%s\n' "$ROOT_DIR"
} >"${BACKUP_DIR}/metadata/manifest.txt"

docker compose --env-file "$ENV_FILE" images >"${BACKUP_DIR}/metadata/compose-images.txt" 2>/dev/null || \
  warn "could not capture compose image metadata"
docker compose --env-file "$ENV_FILE" config --services >"${BACKUP_DIR}/metadata/compose-services.txt" 2>/dev/null || \
  warn "could not capture compose services"
docker compose --env-file "$ENV_FILE" config --profiles >"${BACKUP_DIR}/metadata/compose-profiles.txt" 2>/dev/null || \
  warn "could not capture compose profiles"

if redis_password="$(read_env_value REDIS_PASSWORD)"; then
  log "Capturing Redis persistence files..."
  if docker compose --env-file "$ENV_FILE" exec -T -e REDISCLI_AUTH="$redis_password" redis redis-cli SAVE >/dev/null 2>&1 &&
    docker compose --env-file "$ENV_FILE" cp redis:/data "${BACKUP_DIR}/redis/redis_data" >/dev/null 2>&1; then
    printf 'redis_data copied after SAVE at %s\n' "$STAMP" >"${BACKUP_DIR}/redis/redis_data.snapshot"
  else
    warn "Redis backup capture failed; continue if cache loss is acceptable"
  fi
else
  warn ".env missing REDIS_PASSWORD; Redis backup skipped"
fi

env_secret="${PLANVAULT_ENCRYPTED_ENV_BACKUP:-}"
realm_secret="${PLANVAULT_ENCRYPTED_REALM_BACKUP:-}"

if copy_encrypted_secret "$env_secret" ".env"; then
  log "Copied encrypted .env backup."
else
  warn "encrypted .env not included; set PLANVAULT_ENCRYPTED_ENV_BACKUP=/path/to/.env.age"
fi

if copy_encrypted_secret "$realm_secret" "planvault-realm.json"; then
  log "Copied encrypted Keycloak realm backup."
else
  warn "encrypted Keycloak realm not included; set PLANVAULT_ENCRYPTED_REALM_BACKUP=/path/to/planvault-realm.json.age"
fi

cat >"${BACKUP_DIR}/README.txt" <<'EOF'
PlanVault backup bundle.

Required sensitive files are intentionally not copied from plaintext sources.
Before treating this as a complete production backup, include encrypted copies:

- .env.age / .env.gpg / .env.enc
- planvault-realm.json.age / planvault-realm.json.gpg / planvault-realm.json.enc

Validate this directory with:

  scripts/backup-verify.sh <backup-directory>

For high confidence, restore into a disposable host and run scripts/smoke-test.sh.
EOF

log "Backup created: ${BACKUP_DIR}"
log "Run: ${SCRIPT_DIR}/backup-verify.sh ${BACKUP_DIR}"
