#!/usr/bin/env bash
# Preflight checks for install and upgrade. Does not require the stack to run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
VERSION_FILE="${ROOT_DIR}/VERSION"

pass_count=0
warn_count=0
fail_count=0

pass() { pass_count=$((pass_count + 1)); printf 'PASS %s\n' "$*"; }
warn() { warn_count=$((warn_count + 1)); printf 'WARN %s\n' "$*"; }
fail() { fail_count=$((fail_count + 1)); printf 'FAIL %s\n' "$*"; }

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

require_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    pass "tool available: ${tool}"
  else
    fail "missing required tool: ${tool}"
  fi
}

check_port() {
  local port="$1"
  local name="$2"
  if [[ -z "$port" ]]; then
    warn "${name} port is empty"
    return
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    fail "${name} port is not numeric"
    return
  fi
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "port ${port} already has a listener (${name})"
  else
    pass "port ${port} appears available (${name})"
  fi
}

check_env_key() {
  local key="$1"
  local value
  if ! value="$(read_env_value "$key")"; then
    fail ".env missing required key: ${key}"
    return
  fi
  if [[ -z "$value" || "$value" == *"__GENERATE__"* || "$value" == "__INVALID_LICENSE_JWT__" ]]; then
    fail ".env key is unset or placeholder: ${key}"
  else
    pass ".env key present: ${key}"
  fi
}

printf 'PlanVault self-hosted preflight\n'
printf 'root: %s\n\n' "$ROOT_DIR"

require_tool docker
require_tool curl
require_tool openssl
require_tool python3
require_tool envsubst

if docker compose version >/dev/null 2>&1; then
  pass "docker compose plugin available"
else
  fail "docker compose plugin is not available"
fi

if [[ -f "$ENV_FILE" ]]; then
  pass ".env exists"
else
  fail ".env missing; run scripts/generate-secrets.sh"
fi

if [[ -f "$VERSION_FILE" ]]; then
  pass "VERSION exists"
else
  fail "VERSION missing"
fi

if [[ -f "${ROOT_DIR}/init/planvault-realm.json" ]]; then
  pass "rendered Keycloak realm exists"
else
  fail "init/planvault-realm.json missing; run scripts/render-keycloak-realm.sh"
fi

if [[ -f "$ENV_FILE" ]]; then
  for key in PLANVAULT_LICENSE_KEY PLANVAULT_VERSION BASE_URL CORS_ORIGINS KC_PUBLIC_HOSTNAME KEYCLOAK_ISSUER; do
    check_env_key "$key"
  done

  version="$(tr -d '[:space:]' <"$VERSION_FILE" 2>/dev/null || true)"
  env_version="$(read_env_value PLANVAULT_VERSION || true)"
  if [[ -n "$version" && "$version" == "$env_version" ]]; then
    pass "PLANVAULT_VERSION matches VERSION"
  else
    fail "PLANVAULT_VERSION does not match VERSION"
  fi

  base_url="$(read_env_value BASE_URL || true)"
  cors_origins="$(read_env_value CORS_ORIGINS || true)"
  kc_public_hostname="$(read_env_value KC_PUBLIC_HOSTNAME || true)"
  keycloak_issuer="$(read_env_value KEYCLOAK_ISSUER || true)"
  expected_issuer="${kc_public_hostname%/}/realms/planvault"

  if [[ "$keycloak_issuer" == "$expected_issuer" ]]; then
    pass "Keycloak issuer is consistent"
  else
    fail "KEYCLOAK_ISSUER must equal KC_PUBLIC_HOSTNAME + /realms/planvault"
  fi

  if [[ ",${cors_origins}," == *",${base_url},"* ]]; then
    pass "CORS_ORIGINS includes BASE_URL"
  else
    warn "CORS_ORIGINS does not include BASE_URL"
  fi

  http_port="$(read_env_value HTTP_PORT || printf '80')"
  https_port="$(read_env_value HTTPS_PORT || printf '443')"
  check_port "$http_port" "HTTP_PORT"
  check_port "$https_port" "HTTPS_PORT/direct_tls"
fi

if [[ -f "$ENV_FILE" ]] && docker compose --env-file "$ENV_FILE" config --quiet >/dev/null 2>&1; then
  pass "docker compose config is valid"
else
  fail "docker compose config failed"
fi

if [[ -f "$ENV_FILE" ]]; then
  registry="$(read_env_value PLANVAULT_REGISTRY || printf 'ghcr.io/planvault')"
  registry_host="${registry%%/*}"
  registry_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "https://${registry_host}/v2/" || true)"
  if [[ "$registry_status" == "200" || "$registry_status" == "401" ]]; then
    pass "registry endpoint reachable: ${registry_host}"
  else
    warn "registry endpoint not reachable from host; this is expected for restricted networks"
  fi
fi

if command -v df >/dev/null 2>&1; then
  available_kb="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}')"
  if [[ "${available_kb:-0}" -ge 10485760 ]]; then
    pass "disk free space is at least 10 GiB"
  else
    warn "disk free space is below 10 GiB; pilots should usually have 50+ GiB"
  fi
fi

printf '\nSummary: %s PASS, %s WARN, %s FAIL\n' "$pass_count" "$warn_count" "$fail_count"
if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
