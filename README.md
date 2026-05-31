# PlanVault Self-Hosted

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Run PlanVault on your own infrastructure with Docker Compose. This stack deploys
PlanVault in its built-in self-hosted mode on a single Linux host. Only the
**edge** service publishes host ports by default; databases and internal APIs
stay on the private Docker network `planvault`.

PlanVault is commercial software distributed as signed public container images
and gated by an offline license key. The deployment configuration in this
repository (compose files, scripts, templates) is open source under
[Apache 2.0](LICENSE). Learn more at [planvault.ai](https://planvault.ai) or
contact [support@planvault.ai](mailto:support@planvault.ai).

## Contents

- [Public resources](#public-resources)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Security model](#security-model)
- [Image verification (Cosign)](#image-verification-cosign)
- [Security boundary](#security-boundary)
- [Schema migrations (Flyway)](#schema-migrations-flyway)
- [TLS and ingress](#tls-and-ingress)
- [Account bootstrap](#account-bootstrap)
- [Observability (optional)](#observability-optional)
- [Security artifacts](#security-artifacts)
- [Operator runbooks](#operator-runbooks)
- [Upgrade checklist](#upgrade-checklist)
- [Backup and restore](#backup-and-restore)
- [Troubleshooting](#troubleshooting)
- [Safe diagnostics (support)](#safe-diagnostics-support)
- [Outbound dependencies](#outbound-dependencies)
- [License](#license)

## Public resources

- [Docs](https://planvault.ai/docs#main) — product documentation, security and compliance notes, deployment guidance, architecture, and glossary.
- [Security at PlanVault](https://planvault.ai/security#main) — security posture, controls, and trust information.
- [API docs](https://planvault.ai/api-docs#/main) — OpenAPI sources and interactive API reference.
- [PlanVault Integration Examples](https://github.com/PlanVault/planvault-examples) — runnable examples for OpenAPI import, LangGraph webhooks, MCP hosts, approval gates, n8n, SSE chat, Kafka triggers, and smoke tests.
- [SBOM manifest](https://planvault.ai/sbom/manifest.json) — public CycloneDX SBOM index for supply-chain review.

## Architecture

A single Compose stack on one host. The `edge` (nginx) service is the only
public entry point and reverse-proxies to the API, dashboard, and Keycloak.

Deployment scope: this public repository supports single-host Docker Compose in
customer-managed or VPC environments. Restricted-network or fully offline
deployments, mirrored registries, and other runtime models require validated
enterprise delivery runbooks. See
[`docs/production-topology.md`](docs/production-topology.md) and
[`docs/networking-and-data-boundaries.md`](docs/networking-and-data-boundaries.md)
for operator-facing topology and network-boundary details.

| Service | Image | Role | Host exposure |
|---------|-------|------|---------------|
| `edge` | `ghcr.io/planvault/front` | nginx reverse proxy + dashboard UI | `${HTTP_PORT:-80}` (and `${HTTPS_PORT:-443}` with profile `direct_tls`) |
| `api` | `ghcr.io/planvault/api` | Application API (never runs migrations) | private network only |
| `jobs` | `ghcr.io/planvault/api` | Background jobs + **sole Flyway migration owner** | private network only |
| `postgres` | `pgvector/pgvector:pg16` | Primary datastore (planvault, keycloak, litellm DBs) | private network only |
| `redis` | `redis:7-alpine` | Session/cache store | private network only |
| `keycloak` | `quay.io/keycloak/keycloak:26.0` | OIDC identity provider (realm `planvault`) | private network only, served at `/keycloak` |
| `litellm` | `ghcr.io/berriai/litellm` | LLM gateway / provider routing | private network only |

## Prerequisites

| Requirement | Recommendation |
|-------------|----------------|
| OS | Linux x86_64 or arm64 VM (Ubuntu 22.04+ or RHEL 9+ are typical) |
| Docker Engine | 24+ with Compose plugin v2 (`docker compose version`) |
| CPU | 2 vCPU local/demo minimum; 4+ vCPU recommended for pilots |
| RAM | 4 GiB local/demo minimum; 8+ GiB recommended for pilots; add headroom for the observability overlay |
| Disk | 20 GiB local/demo minimum; 50+ GiB SSD recommended for pilots; increase for retention and image history |
| Shell tooling | Bash 4+, plus `openssl`, `python3`, and `envsubst` (gettext) for the helper scripts; `/bin/sh` is not sufficient |
| Cosign (optional) | To verify image signatures before deploying |
| Outbound network | `ghcr.io` (public, no login required), optional LLM providers |

## Platform support

The public self-hosted package targets Linux hosts with Docker Engine and Compose
v2. Linux `x86_64` and `arm64` are the intended host architectures, subject to
the published multi-arch support of the pinned third-party images
(`pgvector`, Redis, Keycloak, LiteLLM, Caddy, and observability components).

CI validates Compose and configuration syntax, but it does not currently run a
full clean-host smoke test on both architectures. For production ARM64 use,
verify image pulls and run `./scripts/smoke-test.sh` on the target host before
accepting the deployment.

## Quick start

```bash
# 1. Clone
git clone https://github.com/planvault/self-hosted
cd self-hosted

# 2. Generate secrets — creates .env from .env.example and fills __GENERATE__ placeholders.
#    Also pins PLANVAULT_VERSION from the VERSION file when unset.
./scripts/generate-secrets.sh
```

**3. Edit `.env`** — set at minimum:

- `PLANVAULT_LICENSE_KEY` — offline license JWT supplied out-of-band by PlanVault (contact [support@planvault.ai](mailto:support@planvault.ai)).
- `PLANVAULT_VERSION` — must match a published image tag. Defaults from `VERSION`; never use `latest`.
- Public URLs — keep the `localhost` defaults for a local trial, or set `BASE_URL`, `PUBLIC_DOMAIN`, `CORS_ORIGINS`, and `KC_PUBLIC_HOSTNAME` to your real origin **before** exposing the stack.
- Optional LLM provider keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) if you are not using org-level BYOK.

```bash
# 4. Render the Keycloak realm (substitutes BASE_URL and the client secret into the import file).
#    Re-run this whenever you change BASE_URL or KEYCLOAK_ADMIN_CLIENT_SECRET.
./scripts/render-keycloak-realm.sh

# 5. Run preflight before pulling images or exposing the stack.
./scripts/preflight-check.sh

# 6. Pull images and start the stack.
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

**7. Verify and open the app:**

```bash
./scripts/smoke-test.sh
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/health"
docker compose ps
```

Open `BASE_URL` (default `http://localhost`) in a browser and register the first
operator account — see [Account bootstrap](#account-bootstrap).

> On the first start, Flyway runs inside the **jobs** container. If the stack
> looks unhealthy, check `docker compose logs jobs` first — see
> [Schema migrations](#schema-migrations-flyway) and [Troubleshooting](#troubleshooting).

## Configuration reference

`scripts/generate-secrets.sh` fills every `__GENERATE__` placeholder with strong
random values. The variables you typically touch by hand during initial setup:

| Variable | Required | Notes |
|----------|----------|-------|
| `PLANVAULT_LICENSE_KEY` | Yes | Offline license JWT from PlanVault. Never commit. |
| `PLANVAULT_VERSION` | Yes | Pinned image tag; must match `VERSION` / the release you deploy. |
| `PLANVAULT_REGISTRY` | Yes | Defaults to `ghcr.io/planvault` (public, no login). |
| `BASE_URL` | After install | Public origin of the dashboard/API (no trailing slash). |
| `PUBLIC_DOMAIN` | After install | Hostname only (no scheme/path). |
| `CORS_ORIGINS` | After install | Comma-separated browser origins; must include `BASE_URL`. |
| `KC_PUBLIC_HOSTNAME` / `KEYCLOAK_ISSUER` | After install | Public Keycloak hostname + issuer; must align with `BASE_URL`. |
| `HTTP_PORT` / `HTTPS_PORT` | Optional | Edge host ports (default `80` / `443`). |
| `OPENAI_API_KEY` … | Optional | Infra-level LLM keys; org-level BYOK is preferred. |
| `SESSION_RETENTION_DAYS`, `AUDIT_RETENTION_DAYS`, … | Optional | Data retention windows. See `.env.example`. |

For the full operator reference, including every environment variable and fixed
runtime setting used by `docker-compose.yml` and
`docker-compose.observability.yml`, read [CONFIGURATION.md](CONFIGURATION.md).
It explains which values are supported operator knobs, which are generated
secrets, which are fixed self-hosted runtime policy, and which are internal
container wiring.

Secrets are never committed: `.env` stays in `.gitignore`, and
`generate-secrets.sh` never prints the license key or provider keys.

## Security model

For DEK storage, envelope encryption, `SESSION_STORE_MODE`,
`GDPR_DELETION_LOG_ENABLED`, organization soft-delete behavior, and safe support
diagnostics, read [SECURITY_MODEL.md](SECURITY_MODEL.md).

The supported public self-hosted defaults are:

| Setting | Supported value |
|---------|-----------------|
| `SECURITY_KMS_ENABLED` | `false` |
| `DEK_STORE` | `postgres` |
| `SESSION_STORE_MODE` | `postgres` |
| `GDPR_DELETION_LOG_ENABLED` | `false` |
| `PLANVAULT_LOG_LLM_BODIES` | `false` |

Treat alternative DEK stores, external event databases, and external deletion
logs as advanced deployment designs, not one-line `.env` changes.

## Image verification (Cosign)

Images are signed keylessly via Sigstore. Verify before deploying — replace
`<version>` with the pinned `PLANVAULT_VERSION` (also recorded in `VERSION`).

```bash
VERSION="$(tr -d '[:space:]' < VERSION)"
for image in api front; do
  cosign verify "ghcr.io/planvault/${image}:${VERSION}" \
    --certificate-identity-regexp="github.com/planvault" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
done
```

Cosign verifies image provenance. SBOMs support dependency and supply-chain
review:

- [Latest API runtime SBOM](https://planvault.ai/sbom/latest.json)
- [SBOM manifest](https://planvault.ai/sbom/manifest.json)
- [SBOM discovery](https://planvault.ai/.well-known/sbom)

The public SBOM currently covers the API runtime image. Frontend SBOMs are used
for internal vulnerability scanning but are not currently published.

## Security boundary

| Layer | Exposure |
|-------|----------|
| **edge** | Host ports `${HTTP_PORT:-80}` (and optional `${HTTPS_PORT:-443}` with profile `direct_tls`) |
| **postgres, redis, keycloak, litellm, api, jobs** | Docker network only — no host ports |
| **Secrets** | `.env` on disk (never commit or email) |
| **Data** | Named volumes `pg_data`, `redis_data` |

## Schema migrations (Flyway)

Flyway runs on startup inside the **jobs** container only. The **api** container
never runs migrations.

| Service | `PLANVAULT_ROLE` | `PLANVAULT_FLYWAY_MIGRATE` |
|---------|------------------|---------------------------|
| **jobs** | `jobs` | `true` (sole migration owner) |
| **api** | `api` | `false` |

On migration failure, inspect **jobs** logs only (`docker compose logs jobs`).
Do not scale **jobs** above one replica.

## TLS and ingress

**Default:** edge serves HTTP on port 80. Terminate TLS at your corporate load
balancer, ingress controller, or reverse proxy and forward
`X-Forwarded-Proto: https` and `X-Forwarded-For`.

**Direct HTTPS (optional):** place `fullchain.pem` and `privkey.pem` under
`./tls/`, then:

```bash
docker compose --env-file .env --profile direct_tls up -d
```

This adds the `edge-tls` service on `${HTTPS_PORT:-443}`. HTTP on port 80 remains
available via the `edge` service.

**Managed HTTPS with Caddy (optional):** for simple public pilots without a
corporate ingress, use the Caddy overlay. DNS for `CADDY_SITE_ADDRESS` must point
to the host, and Caddy must bind public ports 80/443 for ACME:

```bash
# in .env
BASE_URL=https://planvault.example.com
KC_PUBLIC_HOSTNAME=https://planvault.example.com/keycloak
KEYCLOAK_ISSUER=https://planvault.example.com/keycloak/realms/planvault
CORS_ORIGINS=https://planvault.example.com
HTTP_PORT=8080
CADDY_SITE_ADDRESS=https://planvault.example.com

./scripts/render-keycloak-realm.sh
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.caddy.yml up -d
```

Keep using customer-managed ingress when your platform already provides TLS,
WAF, identity-aware proxying, or centralized certificate management.

## Account bootstrap

The bundled realm allows self-registration by default so the first pilot
operator can create an account without an email dependency. Email verification
is disabled in the default import; configure Keycloak email settings separately
if your policy requires it.

## Observability (optional)

An opt-in overlay adds a full local monitoring stack: Grafana, Prometheus, Loki,
Tempo, an OpenTelemetry Collector, and node/cAdvisor exporters. Grafana binds to
`127.0.0.1:${GRAFANA_PORT:-3000}` only and authenticates via Keycloak OIDC.

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Before starting the overlay, set the `GRAFANA_*` and (for the API to emit
traces/logs) `OTEL_*` variables in `.env` — see the commented sections in
[`.env.example`](.env.example). Optional database/cache exporters are gated
behind Compose profiles:

```bash
COMPOSE_PROFILES=with_redis_exporter,with_postgres_exporter \
  docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

By default Loki and Tempo use local filesystem storage; point them at
S3-compatible object storage (`LOKI_S3_*` / `TEMPO_S3_*`) for production
retention.

See [Monitoring](docs/monitoring.md) for the full overlay guide.

## Security artifacts

Use [Security artifacts](docs/security-artifacts.md) as the procurement/security
review index. It links the official security page, public SBOM URLs, Cosign
verification, topology/data-boundary docs, and artifact-sharing rules.

## Operator runbooks

- [Smoke tests](docs/smoke-tests.md) — install/upgrade/restore verification with `scripts/smoke-test.sh`.
- `scripts/preflight-check.sh` — local checks before first start or upgrade; does not require services to be running.
- [Troubleshooting](docs/troubleshooting.md) — common failure modes and safe diagnostic commands.
- [Backup and restore](docs/backup-restore.md) — artifacts to back up, restore order, and verification.
- [Upgrade](docs/upgrade.md) — version pinning, jobs-first migrations, and rollback limits.
- [Monitoring](docs/monitoring.md) — Grafana/Prometheus/Loki/Tempo/OTel overlay and tenant-safe telemetry.
- [Security artifacts](docs/security-artifacts.md) — SBOM, Cosign, review documents, and sharing rules.
- [Production topology](docs/production-topology.md) — single-host topology, stateful services, volumes, and trust boundaries.
- [Networking and data boundaries](docs/networking-and-data-boundaries.md) — inbound/outbound paths, VPC guidance, and restricted-network notes.

## Upgrade checklist

1. **Backup** PostgreSQL (`pg_data` volume) and store `.env` securely offline.
2. **Pin** the new release: update `PLANVAULT_VERSION` in `.env` and `VERSION` to match, then `docker compose --env-file .env pull`.
3. **Review** the new release's `.env.example` for new required keys, and read `CHANGELOG.md`.
4. **Start jobs first** (migrations): `docker compose up -d jobs` and wait until logs show Flyway complete.
5. **Start remaining services:** `docker compose up -d`.
6. **Verify** `/health` and run application smoke tests.
7. **Rollback:** restore the volume snapshot and previous image tag. Irreversible Flyway migrations cannot be rolled back by image downgrade alone — coordinate with PlanVault support before upgrading across major versions.

See [Upgrade](docs/upgrade.md) for the full runbook.

## Backup and restore

**PostgreSQL:** stop writes, then snapshot the `pg_data` volume (or `pg_dump`
from a temporary sidecar container on the `planvault` network).

**Redis:** snapshot the `redis_data` volume; cache loss is recoverable but may
increase LLM latency until rebuilt.

**Configuration:** store an encrypted copy of `.env` and the rendered
`init/planvault-realm.json` in your secrets manager — never in ticket systems or
email.

See [Backup and restore](docs/backup-restore.md) for the full runbook.

## Troubleshooting

| Symptom | First checks |
|---------|--------------|
| Stack starts but `/health` fails | `docker compose logs jobs --tail=80` (migrations), then `docker compose logs api --tail=80`. |
| `docker compose pull` denied / not found | Confirm `PLANVAULT_REGISTRY=ghcr.io/planvault` and that `PLANVAULT_VERSION` matches a published tag. No login is required for public images. |
| Login redirects fail or CORS errors | Ensure `BASE_URL`, `CORS_ORIGINS`, `KC_PUBLIC_HOSTNAME`, and `KEYCLOAK_ISSUER` all match your real origin, then re-run `./scripts/render-keycloak-realm.sh` and restart `keycloak`. |
| `render-keycloak-realm.sh` errors on placeholders | `.env` still contains `__…__` values — run `./scripts/generate-secrets.sh` and set `BASE_URL` first. |
| `envsubst: command not found` | Install the `gettext` package. |
| Migration errors | Inspect `jobs` logs only; never scale `jobs` above one replica. |

See [Troubleshooting](docs/troubleshooting.md) for the full runbook.

## Safe diagnostics (support)

You may share:

- `VERSION` file contents and `docker compose ps`
- Redacted `docker compose logs` (no environment dumps)
- Output of `curl /health` (no tokens)
- Compose profile list and image digests (`docker compose images`)
- `scripts/support-bundle.sh` output after local review/redaction

**Never share:** `.env`, `PLANVAULT_LICENSE_KEY`, database dumps, raw Keycloak
exports with secrets, or unredacted logs that may contain JWTs or API keys.

## Outbound dependencies

| Destination | Purpose |
|-------------|---------|
| `ghcr.io/planvault` | Pull `api` and `front` images |
| `quay.io`, `docker.io`, `ghcr.io/berriai` | Pull base images (postgres, redis, keycloak, litellm) |
| LLM providers (optional) | OpenAI, Anthropic, Google, or customer BYOK endpoints |

## License

The deployment configuration in this repository is licensed under the
[Apache License 2.0](LICENSE).

The PlanVault application distributed as Docker images is commercial software
and requires a valid license key. See [planvault.ai](https://planvault.ai) or
contact [support@planvault.ai](mailto:support@planvault.ai).
