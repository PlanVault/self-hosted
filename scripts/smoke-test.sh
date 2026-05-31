#!/usr/bin/env bash
# Safe post-install / post-upgrade smoke test for the PlanVault self-hosted stack.
# This script intentionally avoids printing environment values or secrets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
VERSION_FILE="${ROOT_DIR}/VERSION"
REALM_FILE="${ROOT_DIR}/init/planvault-realm.json"

pass_count=0
warn_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS %s\n' "$*"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN %s\n' "$*"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL %s\n' "$*"
}

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

redact() {
  sed -E \
    -e 's/(Authorization: Bearer )[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig' \
    -e 's/(Bearer )[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig' \
    -e 's/(PLANVAULT_LICENSE_KEY=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(OPENAI_API_KEY=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(ANTHROPIC_API_KEY=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(GEMINI_API_KEY=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(sk-[A-Za-z0-9_-]{12,})/[REDACTED_API_KEY]/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED_JWT]/g'
}

require_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    pass "tool available: ${tool}"
  else
    fail "missing required tool: ${tool}"
  fi
}

check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    pass "file exists: ${file#"$ROOT_DIR/"}"
  else
    fail "missing file: ${file#"$ROOT_DIR/"}"
  fi
}

check_env_required() {
  local key="$1"
  local value
  if ! value="$(read_env_value "$key")"; then
    fail ".env missing required key: ${key}"
    return
  fi
  if [[ -z "$value" ]]; then
    fail ".env key is empty: ${key}"
    return
  fi
  if [[ "$value" == *"__"* ]]; then
    fail ".env key still contains placeholder: ${key}"
    return
  fi
  if [[ "$key" == "PLANVAULT_LICENSE_KEY" && "$value" == "__INVALID_LICENSE_JWT__" ]]; then
    fail "PLANVAULT_LICENSE_KEY is still the invalid example value"
    return
  fi
  pass ".env key present: ${key}"
}

printf 'PlanVault self-hosted smoke test\n'
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

check_file "$ENV_FILE"
check_file "$VERSION_FILE"
check_file "${ROOT_DIR}/docker-compose.yml"
check_file "$REALM_FILE"

if [[ -f "$ENV_FILE" ]]; then
  if awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 ~ /__GENERATE__/' "$ENV_FILE" | grep -q .; then
    fail ".env still contains active __GENERATE__ placeholders"
  else
    pass ".env has no active __GENERATE__ placeholders"
  fi

  for key in PLANVAULT_LICENSE_KEY PLANVAULT_VERSION BASE_URL CORS_ORIGINS KC_PUBLIC_HOSTNAME KEYCLOAK_ISSUER; do
    check_env_required "$key"
  done

  if [[ -f "$VERSION_FILE" ]]; then
    pinned_version="$(tr -d '[:space:]' <"$VERSION_FILE")"
    env_version="$(read_env_value PLANVAULT_VERSION || true)"
    if [[ -n "$pinned_version" && "$env_version" == "$pinned_version" ]]; then
      pass "PLANVAULT_VERSION matches VERSION"
    else
      fail "PLANVAULT_VERSION does not match VERSION"
    fi
  fi

  kc_public_hostname="$(read_env_value KC_PUBLIC_HOSTNAME || true)"
  keycloak_issuer="$(read_env_value KEYCLOAK_ISSUER || true)"
  expected_issuer="${kc_public_hostname%/}/realms/planvault"
  if [[ -n "$kc_public_hostname" && "$keycloak_issuer" == "$expected_issuer" ]]; then
    pass "KEYCLOAK_ISSUER matches KC_PUBLIC_HOSTNAME"
  else
    fail "KEYCLOAK_ISSUER must equal KC_PUBLIC_HOSTNAME + /realms/planvault"
  fi

  base_url="$(read_env_value BASE_URL || true)"
  cors_origins="$(read_env_value CORS_ORIGINS || true)"
  if [[ -n "$base_url" && ",${cors_origins}," == *",${base_url},"* ]]; then
    pass "CORS_ORIGINS includes BASE_URL"
  else
    warn "CORS_ORIGINS does not appear to include BASE_URL"
  fi
fi

if [[ -f "$ENV_FILE" ]] && docker compose --env-file "$ENV_FILE" config --quiet >/dev/null 2>&1; then
  pass "docker compose config is valid"
else
  fail "docker compose config failed"
fi

if [[ -f "$ENV_FILE" ]]; then
  printf '\nService status:\n'
  if docker compose --env-file "$ENV_FILE" ps 2>/dev/null | redact; then
    pass "docker compose ps completed"
  else
    warn "docker compose ps failed; stack may not be running"
  fi
fi

http_port="$(read_env_value HTTP_PORT 2>/dev/null || printf '80')"
health_url="http://127.0.0.1:${http_port}/health"
if curl -fsS --max-time 5 "$health_url" >/dev/null 2>&1; then
  pass "health endpoint OK: ${health_url}"
else
  fail "health endpoint failed: ${health_url}"
fi

if [[ -f "$ENV_FILE" ]]; then
  keycloak_public="$(read_env_value KC_PUBLIC_HOSTNAME 2>/dev/null || true)"
  keycloak_local="${keycloak_public/localhost/127.0.0.1}"
  keycloak_local="${keycloak_local%/}/realms/planvault/.well-known/openid-configuration"
  if [[ -n "$keycloak_public" ]] && curl -fsS --max-time 5 "$keycloak_local" >/dev/null 2>&1; then
    pass "Keycloak issuer metadata reachable"
  else
    warn "Keycloak issuer metadata not reachable from host"
  fi
fi

for service in jobs api; do
  printf '\nRecent %s logs (redacted):\n' "$service"
  if docker compose --env-file "$ENV_FILE" logs "$service" --tail=40 2>/dev/null | redact; then
    if docker compose --env-file "$ENV_FILE" logs "$service" --tail=120 2>/dev/null |
      grep -Eiq 'FATAL|ERROR|Exception|Flyway.*failed|migration.*failed|invalid license|license.*invalid'; then
      warn "${service} logs contain error-like lines; inspect full redacted logs"
    else
      pass "${service} logs do not show common fatal markers"
    fi
  else
    warn "could not read ${service} logs; service may not exist or stack may be stopped"
  fi
done

printf '\nSummary: %s PASS, %s WARN, %s FAIL\n' "$pass_count" "$warn_count" "$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
