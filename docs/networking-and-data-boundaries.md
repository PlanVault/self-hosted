# Networking And Data Boundaries

This document explains what network paths exist in the supported public
self-hosted profile and how to keep data inside a customer-managed perimeter.

## Scope

Supported public distribution:

- single-host Docker Compose;
- customer-managed host, VPC, or controlled network;
- public image pull from GHCR by default;
- configured LLM providers or local/private LiteLLM-compatible endpoints;
- optional customer-operated observability overlay.

Restricted-network or fully offline deployment is an enterprise delivery path,
not a public self-service toggle. It requires mirrored images/packages, license
delivery, operator runbooks, and a validated smoke test.

## Inbound Network Paths

| Path | Default exposure | Purpose |
|------|------------------|---------|
| `${HTTP_PORT:-80}` to `edge` | Host port | Dashboard, API, and Keycloak browser flows over HTTP unless TLS is terminated upstream. |
| `${HTTPS_PORT:-443}` to `edge-tls` | Host port with profile `direct_tls` | Optional direct TLS when certs are mounted under `./tls/`. |
| Grafana `127.0.0.1:${GRAFANA_PORT:-3000}` | Localhost only, overlay | Optional monitoring UI. |

Internal services do not publish host ports by default.

## Required Outbound Destinations

| Destination | Required when | Purpose |
|-------------|---------------|---------|
| `ghcr.io/planvault` | Default install/upgrade | Pull PlanVault `api` and `front` images. |
| `quay.io`, `docker.io`, `ghcr.io/berriai` | Default install/upgrade | Pull supporting images used by Compose. |
| Configured LLM providers | If using external models | Planner and utility model calls through LiteLLM. |
| Local/private model endpoints | If configured | Private model calls through LiteLLM, for example Ollama/vLLM/OpenAI-compatible endpoints. |
| Configured tool/API targets | If tools call external systems | Runtime OpenAPI, webhook, MCP, and integration calls. |
| Optional OTLP endpoint | If telemetry export is enabled | Traces/logs/metrics to customer-operated collector. |

No separate PlanVault product telemetry endpoint is required by the self-hosted
Compose profile.

## Data Boundary Rules

- Secrets are not placed into LLM prompts. The runtime injects secret values only
  at tool execution time.
- Raw large tool outputs are not sent back to the planner by default; bounded
  evidence replan is opt-in for read-only paths.
- Provider API keys are configured by the operator/org and encrypted at rest.
- Session and audit data stay in the configured stores in the customer
  environment.
- OpenTelemetry export is optional and should use tenant-safe labels.

## VPC-Ready Deployment Guidance

For a typical VPC deployment:

1. Put a customer-managed load balancer or reverse proxy in front of `edge`.
2. Terminate TLS at that layer, or use the `direct_tls` profile.
3. Restrict inbound traffic to the ports you intentionally expose.
4. Restrict egress to the image registries, model backends, APIs, and telemetry
   endpoints you explicitly need.
5. Keep PostgreSQL, Redis, Keycloak, LiteLLM, API, and jobs on the private Docker
   network.
6. Store `.env`, rendered Keycloak realm, TLS material, and volume backups in
   your secrets/backup system.

## Restricted Or Offline Delivery

Do not treat restricted/offline delivery as a local config change. A validated
enterprise path should define:

- image/package mirroring and provenance verification;
- how the license key is delivered and rotated;
- which registry or offline artifact store is authoritative;
- how SBOMs and Cosign signatures are made available to the operator;
- how backups, restore tests, and upgrades are performed without public network
  access;
- how local/private LLM endpoints and tool targets are validated;
- support bundle and redaction procedures.

Until that runbook exists for a customer environment, use the default public
registry pull path.

## What To Share With Support

Safe to share:

- `VERSION`
- `docker compose ps`
- `docker compose images`
- redacted logs
- `/health` response
- SBOM manifest URL and image digest references

Never share:

- `.env`
- `PLANVAULT_LICENSE_KEY`
- provider API keys
- raw database dumps
- raw Keycloak exports with secrets
- JWTs, cookies, or Authorization headers
- unredacted LLM/tool payloads
