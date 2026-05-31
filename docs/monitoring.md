# Monitoring

PlanVault self-hosted includes an optional observability overlay in
`docker-compose.observability.yml`. It is an operator-owned local monitoring
stack for a single-host Compose deployment.

Start it with:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Grafana binds to `127.0.0.1:${GRAFANA_PORT:-3000}` by default. Put it behind
your own access-controlled ingress if operators need remote access.

## Components

| Component | Purpose |
|-----------|---------|
| Grafana | Dashboards and exploration UI, authenticated through Keycloak OIDC. |
| Prometheus | Metrics storage and alert-rule evaluation. |
| Loki | Log storage for OTel/log streams. |
| Tempo | Trace storage for OTel traces. |
| OTel Collector | Receives OTLP from API/jobs and exports to Loki/Tempo. |
| node exporter | Host CPU, memory, disk, filesystem metrics. |
| cAdvisor | Container resource metrics. |
| Redis exporter | Optional Redis metrics profile. |
| Postgres exporter | Optional PostgreSQL metrics profile. |

## Required `.env` Values

Grafana fails fast unless these are set:

```text
GRAFANA_ADMIN_PASSWORD
GRAFANA_OIDC_CLIENT_ID
GRAFANA_OIDC_CLIENT_SECRET
GRAFANA_OIDC_AUTH_URL
GRAFANA_OIDC_TOKEN_URL
GRAFANA_OIDC_API_URL
```

Typical local defaults:

```text
GRAFANA_PORT=3000
GRAFANA_OIDC_AUTH_URL=http://localhost/keycloak/realms/planvault/protocol/openid-connect/auth
GRAFANA_OIDC_TOKEN_URL=http://localhost/keycloak/realms/planvault/protocol/openid-connect/token
GRAFANA_OIDC_API_URL=http://localhost/keycloak/realms/planvault/protocol/openid-connect/userinfo
```

To emit API/jobs traces and logs, enable OTLP in `.env`:

```text
OTEL_JAVAAGENT_ENABLED=true
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel-collector:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_CERTS_HOST_DIR=./observability/certs
```

The default certificate paths are mounted inside API/jobs and the collector:

```text
OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE=/certs/client.crt
OTEL_EXPORTER_OTLP_CLIENT_KEY=/certs/client.key
OTEL_EXPORTER_OTLP_CERTIFICATE=/certs/ca.crt
```

## Prometheus Profiles

Default config:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Minimal config without local Redis/Postgres exporters:

```bash
PROMETHEUS_CONFIG_FILE=./observability/prometheus/prometheus.minimal.yml \
  docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Exporter profile:

```bash
COMPOSE_PROFILES=with_redis_exporter,with_postgres_exporter \
  docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

## Storage

By default:

- Prometheus uses the `prometheus_data` Docker volume.
- Grafana uses `grafana_data`.
- Loki uses filesystem storage in `loki_data`.
- Tempo uses local storage in `tempo_data`.

For production retention, use S3-compatible object storage for Loki and Tempo:

```text
LOKI_OBJECT_STORE=s3
LOKI_DELETE_REQUEST_STORE=s3
LOKI_S3_BUCKET=planvault-loki
LOKI_S3_ENDPOINT=<s3-or-minio-endpoint>
LOKI_S3_REGION=<region>
LOKI_S3_ACCESS_KEY_ID=<access-key>
LOKI_S3_SECRET_ACCESS_KEY=<secret-key>

TEMPO_STORAGE_BACKEND=s3
TEMPO_S3_BUCKET=planvault-tempo
TEMPO_S3_ENDPOINT=<s3-or-minio-endpoint>
TEMPO_S3_REGION=<region>
TEMPO_S3_ACCESS_KEY=<access-key>
TEMPO_S3_SECRET_KEY=<secret-key>
```

Use TLS for object-storage endpoints in production.

## Included Dashboards

| Dashboard | File | Use |
|-----------|------|-----|
| API runtime | `observability/grafana/dashboards/api-runtime.json` | API/jobs health, JVM/runtime, request behavior. |
| Ingestion by organization hash | `observability/grafana/dashboards/ingestion-by-organization-hash.json` | Tenant-safe ingestion trends using hashed org labels. |
| LiteLLM | `observability/grafana/dashboards/litellm.json` | Model gateway behavior and provider troubleshooting. |
| Postgres/Redis | `observability/grafana/dashboards/postgres-redis.json` | Database/cache health when exporters are enabled. |
| Host disk | `observability/grafana/dashboards/host-disk.json` | Host and volume capacity monitoring. |

## Tenant-Safe Telemetry

Keep observability safe for support and internal review:

- Use hashed organization labels, not raw organization names or customer IDs.
- Keep `PLANVAULT_LOG_LLM_BODIES=false`.
- Do not log raw prompts, completions, tool payloads, secrets, JWTs, cookies, or
  Authorization headers.
- Treat `OBSERVABILITY_TENANT_HMAC_KEY` as a secret and back it up with `.env`.
- Redact logs before sharing support bundles.

## Basic Triage

Check overlay status:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml ps
```

Check Grafana and collector logs:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml logs grafana --tail=80
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml logs otel-collector --tail=80
```

If API/jobs telemetry is missing, confirm `OTEL_JAVAAGENT_ENABLED=true`, cert
files exist in `OTEL_CERTS_HOST_DIR`, and the collector is healthy.
