# Troubleshooting

This runbook helps operators diagnose common PlanVault self-hosted deployment
issues without exposing secrets.

Start with:

```bash
./scripts/smoke-test.sh
docker compose --env-file .env ps
```

## Safe Diagnostics

Safe to share with PlanVault support:

- `VERSION`
- `docker compose ps`
- `docker compose images`
- `./scripts/smoke-test.sh` output
- redacted logs
- `/health` response

Never share:

- `.env`
- `PLANVAULT_LICENSE_KEY`
- provider API keys
- JWTs, cookies, Authorization headers
- raw database dumps
- raw Keycloak exports with secrets
- unredacted LLM/tool payloads

## Image Pull Fails

Symptoms:

- `docker compose pull` returns `manifest unknown`
- `pull access denied`
- image tag not found

Checks:

```bash
tr -d '[:space:]' < VERSION
awk -F= '/^PLANVAULT_VERSION=/{print $2}' .env
awk -F= '/^PLANVAULT_REGISTRY=/{print $2}' .env
docker compose --env-file .env images
```

Fixes:

- Ensure `PLANVAULT_REGISTRY=ghcr.io/planvault`.
- Ensure `PLANVAULT_VERSION` matches `VERSION`.
- Do not use `latest`.
- Confirm the tag is published before upgrading.
- In restricted networks, use a validated mirror process rather than editing the
  registry ad hoc.

## Missing Or Invalid License

Symptoms:

- API starts but returns license-related errors.
- `api` or `jobs` logs mention invalid/missing license.

Checks:

```bash
awk -F= '/^PLANVAULT_LICENSE_KEY=/{print ($2 == "" ? "empty" : "set")}' .env
docker compose --env-file .env logs api --tail=80
docker compose --env-file .env logs jobs --tail=80
```

Fixes:

- Set `PLANVAULT_LICENSE_KEY` to the offline license JWT supplied by PlanVault.
- Make sure the token was not truncated or line-wrapped.
- Do not share the token with support; share only redacted logs.

## `.env` Still Has Placeholders

Symptoms:

- Compose interpolation errors.
- `render-keycloak-realm.sh` fails.
- Services start with invalid credentials.

Checks:

```bash
grep -n '__GENERATE__\|__INVALID' .env
```

Fixes:

```bash
./scripts/generate-secrets.sh
```

Then set the license key and public URLs manually.

## Keycloak, OIDC, Or Login Redirects Fail

Symptoms:

- Browser loops during login.
- Token issuer mismatch.
- API rejects tokens.
- CORS errors in browser.

Checks:

```bash
awk -F= '/^(BASE_URL|CORS_ORIGINS|KC_PUBLIC_HOSTNAME|KEYCLOAK_ISSUER)=/{print $1 "=" $2}' .env
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/keycloak/realms/planvault/.well-known/openid-configuration"
```

Expected:

- `BASE_URL` is the public dashboard/API origin.
- `CORS_ORIGINS` includes `BASE_URL`.
- `KC_PUBLIC_HOSTNAME` is the public Keycloak URL ending in `/keycloak`.
- `KEYCLOAK_ISSUER` equals `KC_PUBLIC_HOSTNAME + /realms/planvault`.

Fixes:

```bash
./scripts/render-keycloak-realm.sh
docker compose --env-file .env up -d keycloak api jobs
```

## Flyway Or Migration Failure

Symptoms:

- `/health` fails after upgrade.
- `jobs` logs mention Flyway or migration errors.
- API waits on schema state.

Checks:

```bash
docker compose --env-file .env ps jobs
docker compose --env-file .env logs jobs --tail=160
```

Rules:

- `jobs` is the sole migration owner.
- `api` must keep `PLANVAULT_FLYWAY_MIGRATE=false`.
- Do not scale `jobs` above one replica.
- Do not roll back by image downgrade alone after an irreversible migration;
  restore the pre-upgrade database snapshot.

## API Health Fails

Symptoms:

- `/health` returns non-2xx.
- `edge` is reachable but app is unhealthy.

Checks:

```bash
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/health"
docker compose --env-file .env ps
docker compose --env-file .env logs jobs --tail=120
docker compose --env-file .env logs api --tail=120
docker compose --env-file .env logs postgres --tail=80
docker compose --env-file .env logs redis --tail=80
docker compose --env-file .env logs keycloak --tail=80
docker compose --env-file .env logs litellm --tail=80
```

Compose healthchecks gate the main startup path for PostgreSQL, Redis,
Keycloak, LiteLLM, API, and edge. `jobs` stays a singleton and waits for the API
container to start rather than for API health, so migrations can complete during
first boot or upgrade.

Common causes:

- migration failure in `jobs`;
- invalid license;
- Keycloak issuer mismatch;
- database credentials regenerated after initial install;
- Redis password mismatch;
- image version mismatch.

## LiteLLM Or Model Provider Errors

Symptoms:

- Sessions fail during planning.
- Provider returns auth/rate-limit errors.
- Local model endpoint unavailable.

Checks:

```bash
docker compose --env-file .env logs litellm --tail=120
docker compose --env-file .env logs api --tail=120
```

Fixes:

- Confirm provider credentials are configured in `.env` or in org-level BYOK.
- Confirm outbound access to external providers.
- Confirm local/private model endpoints are reachable from the Docker network.
- Confirm model names match provider/LiteLLM configuration.

## Observability Overlay Fails

Symptoms:

- Grafana does not start.
- OTel export fails.
- Loki/Tempo storage errors.

Checks:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml ps
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml logs grafana --tail=80
docker compose --env-file .env -f docker-compose.yml -f docker-compose.observability.yml logs otel-collector --tail=80
```

Common causes:

- missing `GRAFANA_ADMIN_PASSWORD`;
- missing Grafana OIDC variables;
- OTel cert files missing under `OTEL_CERTS_HOST_DIR`;
- Loki/Tempo S3 variables incomplete;
- exporter profiles enabled without matching Prometheus config.

See `docs/monitoring.md`.

## Port Conflicts

Symptoms:

- `edge` or `edge-tls` fails to bind.
- Docker reports port already allocated.

Checks:

```bash
docker compose --env-file .env ps edge edge-tls
lsof -iTCP:80 -sTCP:LISTEN
lsof -iTCP:443 -sTCP:LISTEN
```

Fixes:

- Change `HTTP_PORT` / `HTTPS_PORT` in `.env`.
- Or stop the conflicting host process.
- If using corporate ingress, bind PlanVault to internal ports and route through
  the load balancer.

## TLS Or Ingress Mistakes

Symptoms:

- Browser says mixed content or insecure redirect.
- Login redirects to localhost.
- API sees wrong scheme.

Fixes:

- Terminate TLS at the customer ingress and forward:
  - `X-Forwarded-Proto: https`
  - `X-Forwarded-For`
- Set `BASE_URL` and `KC_PUBLIC_HOSTNAME` to HTTPS public URLs.
- Re-render the Keycloak realm after URL changes.

## Escalation

Before contacting support:

```bash
./scripts/smoke-test.sh > smoke-test.txt 2>&1
docker compose --env-file .env ps > compose-ps.txt
docker compose --env-file .env images > compose-images.txt
./scripts/support-bundle.sh
```

Attach only redacted logs and safe outputs. Do not attach `.env`.
