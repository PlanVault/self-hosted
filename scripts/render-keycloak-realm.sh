#!/usr/bin/env bash
# Render init/planvault-realm.json from the template using URL and client-secret values in .env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
TEMPLATE="${ROOT_DIR}/init/planvault-realm.template.json"
OUTPUT="${ROOT_DIR}/init/planvault-realm.json"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

[[ -f "$ENV_FILE" ]] || die ".env not found — run scripts/generate-secrets.sh first"
[[ -f "$TEMPLATE" ]] || die "template not found: ${TEMPLATE}"

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
  ' "$ENV_FILE")" || die "${key} is missing in .env"

  if [[ "$raw" == \"*\" && "$raw" == *\" ]]; then
    printf '%s' "${raw:1:${#raw}-2}"
  elif [[ "$raw" == \'*\' && "$raw" == *\' ]]; then
    printf '%s' "${raw:1:${#raw}-2}"
  else
    printf '%s' "$raw"
  fi
}

BASE_URL="$(read_env_value BASE_URL)"
KEYCLOAK_ADMIN_CLIENT_SECRET="$(read_env_value KEYCLOAK_ADMIN_CLIENT_SECRET)"

[[ -n "${BASE_URL:-}" ]] || die "BASE_URL is required in .env"
[[ "${BASE_URL}" != *__* ]] || die "BASE_URL still contains a placeholder"
[[ -n "${KEYCLOAK_ADMIN_CLIENT_SECRET:-}" ]] || die "KEYCLOAK_ADMIN_CLIENT_SECRET is required in .env"
[[ "${KEYCLOAK_ADMIN_CLIENT_SECRET}" != *__* ]] || die "KEYCLOAK_ADMIN_CLIENT_SECRET still contains a placeholder"

export BASE_URL KEYCLOAK_ADMIN_CLIENT_SECRET

if ! command -v envsubst >/dev/null 2>&1; then
  die "envsubst not found (install gettext package)"
fi

envsubst '${BASE_URL} ${KEYCLOAK_ADMIN_CLIENT_SECRET}' <"$TEMPLATE" >"$OUTPUT"
log "Rendered ${OUTPUT}"
