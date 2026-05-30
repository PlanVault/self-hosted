#!/usr/bin/env bash
# Copy .env.example → .env (if missing) and replace __GENERATE__ placeholders with strong random values.
# Does not generate or print: PLANVAULT_LICENSE_KEY, registry credentials, or LLM provider keys.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
EXAMPLE_FILE="${ROOT_DIR}/.env.example"

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

rand_hex() { openssl rand -hex "${1}"; }
rand_b64() { openssl rand -base64 "${1}" | tr -d '\n'; }

generate_tink_keyset_json() {
  command -v python3 >/dev/null 2>&1 || die "python3 is required to generate TINK_LOCAL_KEYSET_JSON"

  python3 - <<'PY'
import base64
import json
import os
import secrets

# Tink AesGcmKey protobuf: field 3 (key_value) with a 32-byte AES-256 key.
key_material = os.urandom(32)
serialized_aes_gcm_key = b"\x1a\x20" + key_material
key_id = secrets.randbits(31) or 1
keyset = {
    "primaryKeyId": key_id,
    "key": [
        {
            "keyData": {
                "typeUrl": "type.googleapis.com/google.crypto.tink.AesGcmKey",
                "value": base64.b64encode(serialized_aes_gcm_key).decode("ascii"),
                "keyMaterialType": "SYMMETRIC",
            },
            "status": "ENABLED",
            "keyId": key_id,
            "outputPrefixType": "TINK",
        }
    ],
}
print(json.dumps(keyset, separators=(",", ":")), end="")
PY
}

replace_generate_placeholder() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2016
  awk -v k="$key" -v v="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^" k "=" {
      current = substr($0, length(k) + 2)
      if (current == "" || current == "__GENERATE__") print k "=" v
      else print $0
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) print k "=" v }
  ' "$ENV_FILE" >"$tmp" || die "failed to update ${key} in .env"
  mv "$tmp" "$ENV_FILE"
}

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  die ".env.example not found at ${EXAMPLE_FILE}"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  log "Created ${ENV_FILE} from .env.example"
else
  log "Using existing ${ENV_FILE} (will only replace __GENERATE__ placeholders)"
fi

tink_json="$(generate_tink_keyset_json)"
# Single-quoted .env value (JSON contains double quotes).
tink_env_value="'${tink_json//\'/\'\\\'\'}'"

replace_generate_placeholder "DB_PASSWORD_SUPERUSER" "$(rand_hex 16)"
replace_generate_placeholder "DB_PASSWORD_API" "$(rand_hex 16)"
replace_generate_placeholder "DB_PASSWORD_KC" "$(rand_hex 16)"
replace_generate_placeholder "DB_PASSWORD_LITELLM" "$(rand_hex 16)"
replace_generate_placeholder "REDIS_PASSWORD" "$(rand_hex 16)"
replace_generate_placeholder "KEYCLOAK_ADMIN_PASSWORD" "$(rand_hex 16)"
replace_generate_placeholder "KEYCLOAK_ADMIN_CLIENT_SECRET" "$(rand_hex 24)"
replace_generate_placeholder "LITELLM_MASTER_KEY" "sk-litellm-$(rand_hex 24)"
replace_generate_placeholder "SECURITY_HMAC_KEY" "$(rand_b64 32)"
replace_generate_placeholder "OBSERVABILITY_TENANT_HMAC_KEY" "$(rand_b64 32)"
replace_generate_placeholder "TINK_LOCAL_KEYSET_JSON" "${tink_env_value}"

VERSION_FILE="${ROOT_DIR}/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  pinned_version="$(tr -d '[:space:]' <"$VERSION_FILE")"
  if [[ -n "$pinned_version" ]]; then
    current_version="$(awk -F= '/^PLANVAULT_VERSION=/{print $2}' "$ENV_FILE" || true)"
    if [[ "$current_version" == "__PLANVAULT_VERSION__" || -z "$current_version" ]]; then
      replace_generate_placeholder "PLANVAULT_VERSION" "$pinned_version"
      log "Set PLANVAULT_VERSION=${pinned_version} from VERSION"
    fi
  fi
fi

current_issuer="$(awk -F= '/^KEYCLOAK_ISSUER=/{print $2}' "$ENV_FILE" || true)"
if [[ -z "$current_issuer" ]]; then
  kc_public_hostname="$(awk -F= '/^KC_PUBLIC_HOSTNAME=/{print $2}' "$ENV_FILE" | tail -n 1)"
  kc_public_hostname="${kc_public_hostname:-http://localhost/keycloak}"
  kc_public_hostname="${kc_public_hostname%/}"
  printf 'KEYCLOAK_ISSUER=%s/realms/planvault\n' "$kc_public_hostname" >>"$ENV_FILE"
  log "Set KEYCLOAK_ISSUER=${kc_public_hostname}/realms/planvault from KC_PUBLIC_HOSTNAME"
fi

log "Secrets ensured in ${ENV_FILE}."
log "Next: set PLANVAULT_LICENSE_KEY; keep localhost URL defaults for local trials or update BASE_URL, PUBLIC_DOMAIN, CORS_ORIGINS, and KC_PUBLIC_HOSTNAME before exposing the stack. Confirm PLANVAULT_VERSION matches your release."
log "Do not share .env or commit it to version control."
