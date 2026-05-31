#!/usr/bin/env bash
# Create a redacted diagnostics bundle. Never includes .env or database dumps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
OUT_BASE="${1:-${ROOT_DIR}/support-bundles}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_DIR="${OUT_BASE}/planvault-support-${STAMP}"
BUNDLE_TAR="${BUNDLE_DIR}.tar.gz"

redact() {
  sed -E \
    -e 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig' \
    -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/Ig' \
    -e 's/(Cookie:[[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(Set-Cookie:[[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(PLANVAULT_LICENSE_KEY=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/((OPENAI|ANTHROPIC|GEMINI|LITELLM|GRAFANA|KEYCLOAK)[A-Z0-9_]*(KEY|SECRET|PASSWORD)=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(sk-[A-Za-z0-9_-]{12,})/[REDACTED_API_KEY]/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED_JWT]/g'
}

run_capture() {
  local name="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n\n'
    "$@" 2>&1 || true
  } | redact >"${BUNDLE_DIR}/${name}.txt"
}

mkdir -p "$BUNDLE_DIR"

if [[ -f "${ROOT_DIR}/VERSION" ]]; then
  cp "${ROOT_DIR}/VERSION" "${BUNDLE_DIR}/VERSION"
fi

{
  printf 'created_at_utc=%s\n' "$STAMP"
  printf 'root=%s\n' "$ROOT_DIR"
  uname -a
} >"${BUNDLE_DIR}/host.txt"

run_capture docker-version docker version
run_capture docker-compose-version docker compose version
run_capture compose-ps docker compose --env-file "$ENV_FILE" ps
run_capture compose-images docker compose --env-file "$ENV_FILE" images
run_capture compose-services docker compose --env-file "$ENV_FILE" config --services
run_capture compose-profiles docker compose --env-file "$ENV_FILE" config --profiles

if [[ -f "$ENV_FILE" ]]; then
  http_port="$(awk -F= '/^HTTP_PORT=/{print $2}' "$ENV_FILE" | tail -n 1)"
  http_port="${http_port:-80}"
else
  http_port="80"
fi

run_capture health curl -fsS --max-time 5 "http://127.0.0.1:${http_port}/health"

for service in api jobs keycloak litellm edge postgres redis; do
  run_capture "logs-${service}" docker compose --env-file "$ENV_FILE" logs "$service" --tail=200
done

if [[ -f "${ROOT_DIR}/docker-compose.yml" ]]; then
  cp "${ROOT_DIR}/docker-compose.yml" "${BUNDLE_DIR}/docker-compose.yml"
fi
if [[ -f "${ROOT_DIR}/docker-compose.observability.yml" ]]; then
  cp "${ROOT_DIR}/docker-compose.observability.yml" "${BUNDLE_DIR}/docker-compose.observability.yml"
fi

find "$BUNDLE_DIR" -type f -name '*.txt' -exec sh -c 'for f do sed -E -i.bak "s/[[:cntrl:]]//g" "$f" && rm -f "$f.bak"; done' sh {} +

tar -C "$OUT_BASE" -czf "$BUNDLE_TAR" "$(basename "$BUNDLE_DIR")"

printf 'Created support bundle: %s\n' "$BUNDLE_TAR"
printf 'Review contents before sharing. The bundle excludes .env, database dumps, and raw Keycloak exports.\n'
