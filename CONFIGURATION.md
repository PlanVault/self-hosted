# PlanVault Self-Hosted Configuration Reference

This document is the operator reference for the environment variables and fixed
runtime settings used by `docker-compose.yml` and
`docker-compose.observability.yml`. For end-to-end operator runbooks, see
`docs/monitoring.md`, `docs/backup-restore.md`, `docs/upgrade.md`, and
`docs/troubleshooting.md`.

The short version:

- Edit `.env` for supported self-hosted configuration.
- Do not edit fixed runtime policy values in `docker-compose.yml` unless
  PlanVault support explicitly asks you to.
- Use a Compose override file for site-specific infrastructure changes, so you
  can still pull upstream updates cleanly.

## Configuration Classes

| Class | Meaning | Examples | Operator action |
|-------|---------|----------|-----------------|
| Supported operator setting | Public self-hosted configuration surface. | `BASE_URL`, `PLANVAULT_LICENSE_KEY`, `SESSION_RETENTION_DAYS` | Configure in `.env`. |
| Generated secret | Created locally by `scripts/generate-secrets.sh`. | `TINK_LOCAL_KEYSET_JSON`, `DB_PASSWORD_API`, `REDIS_PASSWORD` | Generate once, back up securely, rotate with care. |
| Fixed runtime policy | Deliberately pinned for the supported self-hosted profile. | `DEK_STORE=postgres`, `SESSION_STORE_MODE=postgres`, `SECURITY_KMS_ENABLED=false` | Treat as read-only unless support gives a migration plan. |
| Internal container wiring | Hostnames, ports, service roles, and plugin choices inside the Compose network. | `DB_HOST=postgres`, `LITELLM_URL=http://litellm:4000`, `PLANVAULT_ROLE=api` | Do not change in normal deployments. |
| Optional observability | Only used when the observability overlay is enabled. | `GRAFANA_*`, `LOKI_*`, `TEMPO_*`, `OTEL_*` | Configure only if you run the overlay. |

## Release And Public URLs

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `PLANVAULT_REGISTRY` | `api`, `jobs`, `edge`, `edge-tls` image references | `ghcr.io/planvault` | Usually no | Public image registry. No `docker login` is required for the default registry. |
| `PLANVAULT_VERSION` | `api`, `jobs`, `edge`, `edge-tls` image references | From `VERSION` / `.env.example` | Yes, per upgrade | Pinned image tag. Must match a published release. Never use `latest` for supported deployments. |
| `PLANVAULT_LICENSE_KEY` | `api`, `jobs` | none | Yes | Offline license JWT supplied by PlanVault. Never commit, email, or paste into tickets. |
| `BASE_URL` | Rendered into Keycloak realm by `scripts/render-keycloak-realm.sh` | `http://localhost` | Yes before exposure | Public dashboard/API origin, without a trailing slash. Re-render the Keycloak realm after changing it. |
| `PUBLIC_DOMAIN` | Documentation and optional integrations | `localhost` | Yes before exposure | Hostname only, with no scheme or path. |
| `CORS_ORIGINS` | `api`, `jobs` | `http://localhost,http://127.0.0.1` | Yes before exposure | Comma-separated browser origins allowed by the API. Must include `BASE_URL`. |
| `KC_PUBLIC_HOSTNAME` | `keycloak` | `http://localhost/keycloak` | Yes before exposure | Public Keycloak URL, including the `/keycloak` path. |
| `KEYCLOAK_ISSUER` | `api`, `jobs` | `http://localhost/keycloak/realms/planvault` | Yes before exposure | OIDC issuer expected in tokens. Must equal `KC_PUBLIC_HOSTNAME + /realms/planvault`. |
| `HTTP_PORT` | `edge` | `80` | Optional | Host port for HTTP traffic. |
| `HTTPS_PORT` | `edge-tls` | `443` | Optional | Host port for direct TLS when profile `direct_tls` is enabled. |

The default public registry path requires outbound access to `ghcr.io`.
Restricted-network or offline delivery needs an enterprise-validated mirror or
image/package transfer process; do not treat it as a local `.env` change.

## Secrets And Key Material

Run `./scripts/generate-secrets.sh` before editing `.env` by hand. The script
creates `.env` from `.env.example` if it does not exist and replaces
`__GENERATE__` placeholders only. It does not generate the license key or LLM
provider keys.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `TINK_LOCAL_KEYSET_JSON` | `api`, `jobs` | generated | Generate, then preserve | Local Tink keyset used as the self-hosted KEK. This protects org key material. See `SECURITY_MODEL.md`. |
| `SECURITY_HMAC_KEY` | `api`, `jobs` | generated | Generate, then preserve | Base64 HMAC key for pseudonymizing external user identifiers. Rotating it changes pseudonymous identifiers. |
| `OBSERVABILITY_TENANT_HMAC_KEY` | `api`, `jobs` | generated | Generate, then preserve | Separate HMAC key used for tenant-safe observability labels. |
| `DB_PASSWORD_SUPERUSER` | `postgres` | generated | Generate, then preserve | PostgreSQL bootstrap superuser password. |
| `DB_PASSWORD_API` | `postgres`, `api`, `jobs`, observability exporters | generated | Generate, then preserve | PostgreSQL password for the PlanVault application database user. |
| `DB_PASSWORD_KC` | `postgres`, `keycloak` | generated | Generate, then preserve | PostgreSQL password for the Keycloak database user. |
| `DB_PASSWORD_LITELLM` | `postgres`, `litellm` | generated | Generate, then preserve | PostgreSQL password for the LiteLLM database user. |
| `REDIS_PASSWORD` | `redis`, `api`, `jobs`, `litellm`, optional Redis exporter | generated | Generate, then preserve | Redis password. |
| `KEYCLOAK_ADMIN_PASSWORD` | `keycloak` | generated | Generate, then preserve | Keycloak admin password. Store securely; do not share with normal app users. |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | `api`, `jobs`, realm template | generated | Generate, then preserve | Confidential client secret used by PlanVault backend to administer the realm. Re-run `scripts/render-keycloak-realm.sh` if changed. |
| `LITELLM_MASTER_KEY` | `litellm`, `api`, `jobs` | generated | Generate, then preserve | Shared secret for the LiteLLM gateway. |
| `GRAFANA_ADMIN_PASSWORD` | `grafana` overlay | unset | Required for overlay | Grafana local admin password. The overlay fails fast if missing. |
| `GRAFANA_OIDC_CLIENT_SECRET` | `grafana` overlay | unset | Required for overlay | Grafana Keycloak OIDC confidential client secret. |

Do not regenerate `.env` on an existing deployment unless you are intentionally
rotating credentials and have a tested restart/rollback plan.

## PostgreSQL

The bundled PostgreSQL service stores the PlanVault application database,
Keycloak database, and LiteLLM database. The self-hosted profile does not expose
PostgreSQL on a host port.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `DB_USER_SUPERUSER` | `postgres` | `planvault_super` | Rarely | PostgreSQL bootstrap user. |
| `DB_USER_API` | `postgres`, `api`, `jobs`, optional Postgres exporter | `planvault_api` | Rarely | Application database user. |
| `DB_USER_KC` | `postgres`, `keycloak` | `planvault_kc` | Rarely | Keycloak database user. |
| `DB_USER_LITELLM` | `postgres`, `litellm` | `planvault_litellm` | Rarely | LiteLLM database user. |
| `POSTGRES_MAX_CONNECTIONS` | `postgres`, `api`, `jobs` | `150` | With sizing | PostgreSQL `max_connections`; keep aligned with API/jobs pool sizes and exporter overhead. |
| `DB_POOL_SIZE` | `api` | `10` | With sizing | PlanVault API JDBC pool size. |
| `DB_POOL_SIZE_JOBS` | `jobs` | `4` | With sizing | PlanVault jobs JDBC pool size. |

Internal fixed values:

| Variable | Services | Value | Meaning |
|----------|----------|-------|---------|
| `DB_HOST` | `api`, `jobs` | `postgres` | Internal Docker DNS name for PostgreSQL. |
| `DB_PORT` | `api`, `jobs` | `5432` | Internal PostgreSQL port. |
| `DB_URL` | `api`, `jobs` | `jdbc:postgresql://postgres:5432/planvault` | Application JDBC URL. |
| `DB_USER` / `DB_PASSWORD` | `api`, `jobs` | from `DB_USER_API` / `DB_PASSWORD_API` | Application DB credentials passed under names expected by the backend. |
| `POSTGRES_DB` | `postgres` | `planvault` | Initial database created by the Postgres image. |

### External Or Separate Event Database

The supported public self-hosted profile stores session events/runs in the
bundled PostgreSQL database by setting `SESSION_STORE_MODE=postgres` in
`docker-compose.yml`.

The application has lower-level support for other session-store modes
(`postgres`, `dynamodb`, `memory`, `file`) and for a separate PostgreSQL session
store URL, but the public Compose contract does not expose that as a supported
operator setting today.

To make a separate event database officially supported, treat it as an
implementation change rather than a README-only change:

1. Add explicit `.env.example` variables such as `SESSION_STORE_POSTGRES_JDBC_URL`,
   `SESSION_STORE_POSTGRES_JDBC_USER`, and `SESSION_STORE_POSTGRES_JDBC_PASSWORD`.
2. Pass those variables to both `api` and `jobs` in `docker-compose.yml`.
3. Define who owns schema migrations for the separate database.
4. Add backup/restore instructions and a clean-VM smoke test.
5. Document rollback, connection pool sizing, and failure behavior.

Until that contract exists, use the bundled PostgreSQL path for supported
self-hosted deployments.

## Redis

Redis is internal-only and used by PlanVault and LiteLLM.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `REDIS_PASSWORD` | `redis`, `api`, `jobs`, `litellm` | generated | Generate, then preserve | Redis auth password. |
| `REDIS_ENABLED` | `api`, `jobs` | `true` | No | Fixed policy: Redis is enabled in the self-hosted stack. |
| `REDIS_HOST` | `api`, `jobs`, `litellm` | `redis` | No | Internal Docker DNS name. |
| `REDIS_PORT` | `api`, `jobs`, `litellm` | `6379` | No | Internal Redis port. |

Redis persistence is enabled with append-only files in the `redis_data` named
volume.

## Keycloak And Authentication

Keycloak is bundled and imported from `init/planvault-realm.json`. The rendered
realm must match your public URL settings.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `KEYCLOAK_ADMIN_USER` | `keycloak` | `admin` | Optional | Keycloak local admin username. |
| `KEYCLOAK_ADMIN_PASSWORD` | `keycloak` | generated | Generate, then preserve | Keycloak local admin password. |
| `KEYCLOAK_ADMIN_CLIENT_ID` | `api`, `jobs` | `planvault-api` | No | Confidential client used by the backend. |
| `KEYCLOAK_ADMIN_CLIENT_SECRET` | `api`, `jobs`, realm import | generated | Generate, then preserve | Backend client secret. Re-render the realm after changing it. |
| `KEYCLOAK_AZP_PRIMARY` | `api`, `jobs` | `planvault-front` | Rarely | Expected authorized party (`azp`) for dashboard tokens. |
| `KEYCLOAK_SKIP_ACCESS_TOKEN_AUDIENCE_ISSUER_CHECKS` | `api`, `jobs` | `false` | No for production | Compatibility switch for token validation. Keep `false` in production. |
| `KEYCLOAK_ISSUER` | `api`, `jobs` | derived from URL defaults | Yes before exposure | Public OIDC issuer expected in tokens. |

Internal fixed values:

| Variable | Services | Value | Meaning |
|----------|----------|-------|---------|
| `KC_DB` | `keycloak` | `postgres` | Keycloak database vendor. |
| `KC_DB_URL` | `keycloak` | `jdbc:postgresql://postgres:5432/keycloak` | Internal Keycloak JDBC URL. |
| `KC_DB_USERNAME` / `KC_DB_PASSWORD` | `keycloak` | from `DB_USER_KC` / `DB_PASSWORD_KC` | Keycloak DB credentials. |
| `KC_HOSTNAME` | `keycloak` | from `KC_PUBLIC_HOSTNAME` | Public hostname used by Keycloak. |
| `KC_HTTP_RELATIVE_PATH` | `keycloak` | `/keycloak` | Keycloak path behind edge. |
| `KC_PROXY_HEADERS` | `keycloak` | `xforwarded` | Honors reverse proxy headers. |
| `KC_HTTP_ENABLED` | `keycloak` | `true` | HTTP is enabled inside the private Docker network. Terminate TLS at edge/ingress. |
| `KC_LOG_LEVEL` | `keycloak` | `INFO` | Keycloak log level. |
| `KEYCLOAK_SERVER_URL` | `api`, `jobs` | `http://keycloak:8080/keycloak` | Internal URL used by backend to reach Keycloak. |

After changing `BASE_URL`, `KC_PUBLIC_HOSTNAME`, or
`KEYCLOAK_ADMIN_CLIENT_SECRET`, run:

```bash
./scripts/render-keycloak-realm.sh
docker compose --env-file .env up -d keycloak api jobs
```

## LiteLLM And LLM Providers

LiteLLM is the internal LLM gateway. Provider keys are optional at the
infrastructure level because org-level BYOK is preferred.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `LITELLM_MASTER_KEY` | `litellm`, `api`, `jobs` | generated | Generate, then preserve | Shared secret for API/jobs to call LiteLLM. |
| `OPENAI_API_KEY` | `litellm` | unset | Optional | Infrastructure-level OpenAI key. Prefer org-level BYOK when available. |
| `ANTHROPIC_API_KEY` | `litellm` | unset | Optional | Infrastructure-level Anthropic key. |
| `GEMINI_API_KEY` | `litellm` | unset | Optional | Infrastructure-level Google Gemini key. |

Internal fixed values:

| Variable | Services | Value | Meaning |
|----------|----------|-------|---------|
| `LITELLM_URL` | `api`, `jobs` | `http://litellm:4000` | Internal LiteLLM URL. |
| `DATABASE_URL` | `litellm` | `postgresql://...@postgres:5432/litellm` | LiteLLM database URL assembled from generated credentials. |
| `LITELLM_LOG` | `litellm` | `INFO` | LiteLLM log level. |

## Encryption, DEK Storage, And Security Runtime

See `SECURITY_MODEL.md` for conceptual details. Operationally, the supported
self-hosted profile is intentionally local-postgres based:

| Variable | Services | Value / Default | Change? | Meaning |
|----------|----------|-----------------|---------|---------|
| `SECURITY_KMS_ENABLED` | `api`, `jobs` | `false` | No | Fixed policy: self-hosted uses the local Tink KEK from `TINK_LOCAL_KEYSET_JSON`, not cloud KMS. |
| `TINK_LOCAL_KEYSET_JSON` | `api`, `jobs` | generated | Generate, then preserve | Local key-encryption material for envelope encryption. |
| `DEK_STORE` | `api`, `jobs` | `postgres` | No in supported self-hosted | Store org wrapped DEKs in PostgreSQL. Code also has a DynamoDB mode for hosted/advanced deployments, but it is not exposed by this public Compose profile. |
| `SECURITY_HMAC_KEY` | `api`, `jobs` | generated | Generate, then preserve | Pseudonymization HMAC key. |
| `PLANVAULT_LOG_LLM_BODIES` | `api`, `jobs` | `false` | Keep false | Prevents raw LLM bodies from being logged. Do not enable in production. |

Advanced DynamoDB DEK storage requires additional application variables such as
`AWS_REGION`, `DYNAMODB_DEK_TABLE`, `DYNAMODB_DELETION_LOG_TABLE`,
`DYNAMODB_ORG_DEK_GRAVEYARD_TABLE`, `DYNAMODB_ORG_KEY_TABLE`, and optional
`DYNAMODB_ENDPOINT`. Those variables are not part of the supported public
self-hosted Compose contract today.

## Session Store, Events, And Runs

The session store controls where session events, session runs, and related
cleanup state are stored.

| Variable | Services | Value / Default | Change? | Meaning |
|----------|----------|-----------------|---------|---------|
| `SESSION_STORE_MODE` | `api`, `jobs` | `postgres` | No in supported self-hosted | Use PostgreSQL-backed session event/run stores and JDBC Pekko persistence cleanup. |
| `SESSION_RETENTION_DAYS` | `api`, `jobs` | `90` | Optional | Default retention for session data. |
| `SESSION_RETENTION_MIN_DAYS` | `api`, `jobs` | `1` | Usually no | Lower bound accepted by the app. |
| `SESSION_RETENTION_MAX_DAYS` | `api`, `jobs` | `1461` | Usually no | Upper bound accepted by the app. |
| `AUDIT_RETENTION_DAYS` | `api`, `jobs` | `365` | Optional | Default retention for audit data. |
| `AUDIT_RETENTION_MIN_DAYS` | `api`, `jobs` | `0` | Usually no | Lower bound accepted by the app. |
| `AUDIT_RETENTION_MAX_DAYS` | `api`, `jobs` | `3650` | Usually no | Upper bound accepted by the app. |

Application-supported modes:

| Mode | Meaning | Public self-hosted support |
|------|---------|---------------------------|
| `postgres` | Session events/runs in PostgreSQL. | Supported default. |
| `dynamodb` | Session events/runs and Pekko persistence cleanup in DynamoDB tables. | Hosted/advanced only; not exposed in this Compose profile. |
| `memory` | In-process stores. | Development/testing only; data is lost on restart. |
| `file` | File-backed stores with H2 journal under a local base path. | Development/testing only. |

Do not switch `SESSION_STORE_MODE` in `docker-compose.yml` without also wiring
the required storage variables, migrations/provisioning, backup procedure, and
smoke tests.

## GDPR Deletion Log And Organization Soft Delete

| Variable | Services | Value / Default | Change? | Meaning |
|----------|----------|-----------------|---------|---------|
| `GDPR_DELETION_LOG_ENABLED` | `api`, `jobs` | `false` | No in supported self-hosted | Fixed policy: the DynamoDB-backed append-only deletion log is disabled in public self-hosted. Deletion effects are handled in the primary PostgreSQL deployment. |
| `GDPR_RECONCILIATION_ON_STARTUP` | `jobs` | `false` | No for self-hosted | If enabled, jobs reconciles recent deletion-log entries on startup. It is meaningful only with the deletion log backend enabled. |
| `PLANVAULT_ORG_SOFT_DELETE_GRACE_DAYS` | `api`, `jobs` | `7` | Optional | Grace window before a soft-deleted organization is hard-deleted. During this window restoration may be possible. |
| `PLANVAULT_ORG_SOFT_DELETE_SWEEPER_INTERVAL_HOURS` | `api`, `jobs` | `24` | Rarely | How often the jobs role wakes the hard-delete sweeper. |

`GDPR_DELETION_LOG_ENABLED=true` is not just a boolean toggle for this Compose
profile. It requires the DynamoDB deletion-log table, IAM/credentials or endpoint
configuration, reconciliation runbook, backup/retention policy, and support
validation.

## Roles, Migrations, And Runtime Profile

These values define how the same API image behaves as either the request-serving
API process or the jobs/migration process.

| Variable | Services | Value | Change? | Meaning |
|----------|----------|-------|---------|---------|
| `PLANVAULT_PROFILE` | `api`, `jobs` | `production` | No | Runtime profile. |
| `PLANVAULT_ROLE` | `api`, `jobs` | `api` / `jobs` | No | Selects service role. |
| `PLANVAULT_FLYWAY_MIGRATE` | `api`, `jobs` | `false` / `true` | No | Only `jobs` runs Flyway migrations. Never enable migrations in `api`. |

Do not scale `jobs` above one replica. On migration failure, inspect
`docker compose logs jobs` first.

## Pekko Runtime

These are internal clustering and persistence plugin settings for the self-hosted
single-host profile.

| Variable | Services | Value | Change? | Meaning |
|----------|----------|-------|---------|---------|
| `PEKKO_ACTOR_PROVIDER` | `api`, `jobs` | `cluster` | No | Enables clustered actor provider. |
| `PEKKO_CLUSTER_HOSTNAME` | `api`, `jobs` | `api-blue` / `jobs` | No | Internal actor system hostname. |
| `PEKKO_CLUSTER_SBR_STRATEGY` | `api`, `jobs` | `keep-oldest` | No | Split-brain resolver strategy. |
| `PEKKO_JOURNAL_PLUGIN` | `api`, `jobs` | `jdbc-journal` | No | Pekko persistence journal plugin. |
| `PEKKO_SNAPSHOT_PLUGIN` | `api`, `jobs` | `jdbc-snapshot-store` | No | Pekko snapshot plugin. |

## Java And Process Sizing

| Variable | Services | Value | Change? | Meaning |
|----------|----------|-------|---------|---------|
| `JAVA_OPTS` | `api` | `-Xms256m -Xmx768m ...` | Usually no | JVM heap and entropy settings for the API process. |
| `JAVA_OPTS` | `jobs` | `-Xms128m -Xmx512m ...` | Usually no | JVM heap and entropy settings for the jobs process. |

Container memory limits are set directly in `docker-compose.yml` and are not
currently exposed through `.env`.

## OpenTelemetry

These variables are meaningful when you enable telemetry export from `api` /
`jobs`, usually together with `docker-compose.observability.yml`.

| Variable | Services | Default | Change? | Meaning |
|----------|----------|---------|---------|---------|
| `OTEL_JAVAAGENT_ENABLED` | `api`, `jobs` | `false` | Optional | Enables the OpenTelemetry Java agent. |
| `OTEL_SERVICE_NAME` | `api` | `planvault-api` | Optional | Service name for API telemetry. |
| `OTEL_SERVICE_NAME_JOBS` | `jobs` | `planvault-jobs` | Optional | Service name for jobs telemetry. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `api`, `jobs` | unset | Required when exporting | OTLP collector endpoint, for example `https://otel-collector:4317`. |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `api`, `jobs` | `grpc` | Usually no | OTLP protocol. |
| `OTEL_CERTS_HOST_DIR` | `api`, `jobs`, `otel-collector` | `./observability/certs` | Optional | Host directory mounted at `/certs`. |
| `OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE` | `api`, `jobs` | `/certs/client.crt` | Optional | mTLS client certificate path inside the container. |
| `OTEL_EXPORTER_OTLP_CLIENT_KEY` | `api`, `jobs` | `/certs/client.key` | Optional | mTLS client key path inside the container. |
| `OTEL_EXPORTER_OTLP_CERTIFICATE` | `api`, `jobs` | `/certs/ca.crt` | Optional | OTLP server CA certificate path inside the container. |
| `OTEL_INSTRUMENTATION_NETTY_4_1_ENABLED` | `api`, `jobs` | `false` | Usually no | Fine-grained Java agent instrumentation switch. |
| `OTEL_INSTRUMENTATION_JAVA_HTTP_CLIENT_ENABLED` | `api`, `jobs` | `false` | Usually no | Fine-grained Java agent instrumentation switch. |
| `OTEL_LOGS_EXPORTER` | `api`, `jobs` | `otlp` | Optional | Logs exporter used by the OpenTelemetry Java agent. |
| `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_CAPTURE_ALL_MDC_ATTRIBUTES` | `api`, `jobs` | `true` | Usually no | Includes MDC attributes in OTel log records. |
| `OBSERVABILITY_TENANT_HMAC_KEY` | `api`, `jobs` | generated | Generate, then preserve | HMAC key for tenant-safe telemetry labels. |

Do not enable raw request, response, token, or LLM body logging. Keep
`PLANVAULT_LOG_LLM_BODIES=false`.

## Observability Overlay

The overlay is enabled with:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

For the full operator guide, including dashboards, storage choices, profiles,
and tenant-safe telemetry rules, see `docs/monitoring.md`.

Optional Redis/Postgres exporters are enabled with:

```bash
COMPOSE_PROFILES=with_redis_exporter,with_postgres_exporter \
  docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.observability.yml up -d
```

### Grafana

| Variable | Service | Default | Change? | Meaning |
|----------|---------|---------|---------|---------|
| `GRAFANA_ADMIN_PASSWORD` | `grafana` | unset | Required | Local Grafana admin password. |
| `GRAFANA_PORT` | `grafana` | `3000` | Optional | Host port bound to `127.0.0.1`. |
| `GRAFANA_OIDC_CLIENT_ID` | `grafana` | unset | Required | Keycloak OIDC client ID for Grafana. |
| `GRAFANA_OIDC_CLIENT_SECRET` | `grafana` | unset | Required | Keycloak OIDC client secret for Grafana. |
| `GRAFANA_OIDC_AUTH_URL` | `grafana` | unset | Required | Keycloak authorization endpoint. |
| `GRAFANA_OIDC_TOKEN_URL` | `grafana` | unset | Required | Keycloak token endpoint. |
| `GRAFANA_OIDC_API_URL` | `grafana` | unset | Required | Keycloak userinfo endpoint. |
| `GRAFANA_OIDC_SIGNOUT_REDIRECT_URL` | `grafana` | unset | Optional | Keycloak logout URL. |

The `GF_*` variables in `docker-compose.observability.yml` are Grafana's native
environment names. Configure the corresponding `GRAFANA_*` variables in `.env`;
do not edit the `GF_*` mapping unless you are customizing Grafana itself.

### Prometheus

| Variable | Service | Default | Change? | Meaning |
|----------|---------|---------|---------|---------|
| `PROMETHEUS_CONFIG_FILE` | `prometheus` | `./observability/prometheus/prometheus.yml` | Optional | Prometheus config mounted into the container. Use `prometheus.minimal.yml` to omit local DB/cache exporters. |
| `PROMETHEUS_ENV` | comments / conventions | `onprem` | Optional | Environment label convention for dashboards/rules. |
| `COMPOSE_PROFILES` | Compose CLI | unset | Optional | Set to `with_redis_exporter,with_postgres_exporter` to enable optional exporters. |

### Loki

| Variable | Service | Default | Change? | Meaning |
|----------|---------|---------|---------|---------|
| `LOKI_OBJECT_STORE` | `loki` | `filesystem` | For production retention | Object store backend. Use `s3` for S3-compatible storage. |
| `LOKI_DELETE_REQUEST_STORE` | `loki` | `filesystem` | For production retention | Store for delete requests. Match your object-store choice. |
| `LOKI_S3_BUCKET` | `loki` | unset | Required for S3 | S3 bucket name. |
| `LOKI_S3_ENDPOINT` | `loki` | unset | Optional | S3-compatible endpoint, for example MinIO. |
| `LOKI_S3_REGION` | `loki` | `eu-central-1` | Optional | S3 region. |
| `LOKI_S3_ACCESS_KEY_ID` | `loki` | unset | Required for S3 unless using ambient credentials | Access key ID. |
| `LOKI_S3_SECRET_ACCESS_KEY` | `loki` | unset | Required for S3 unless using ambient credentials | Secret access key. |
| `LOKI_S3_INSECURE` | `loki` | `false` | Local only | Allows insecure endpoint. Do not use for production over untrusted networks. |
| `LOKI_S3_FORCE_PATH_STYLE` | `loki` | `false` | S3-compatible stores | Enables path-style access for MinIO-like endpoints. |

### Tempo

| Variable | Service | Default | Change? | Meaning |
|----------|---------|---------|---------|---------|
| `TEMPO_STORAGE_BACKEND` | `tempo` | `local` | For production retention | Tempo trace storage backend. Use `s3` for S3-compatible storage. |
| `TEMPO_S3_BUCKET` | `tempo` | unset | Required for S3 | S3 bucket name. |
| `TEMPO_S3_ENDPOINT` | `tempo` | unset | Optional | S3-compatible endpoint, for example MinIO. |
| `TEMPO_S3_REGION` | `tempo` | `eu-central-1` | Optional | S3 region. |
| `TEMPO_S3_ACCESS_KEY` | `tempo` | unset | Required for S3 unless using ambient credentials | Access key. |
| `TEMPO_S3_SECRET_KEY` | `tempo` | unset | Required for S3 unless using ambient credentials | Secret key. |
| `TEMPO_S3_INSECURE` | `tempo` | `false` | Local only | Allows insecure endpoint. Do not use for production over untrusted networks. |
| `TEMPO_S3_FORCE_PATH_STYLE` | `tempo` | `false` | S3-compatible stores | Enables path-style access for MinIO-like endpoints. |

### Exporters

| Variable | Service | Value | Change? | Meaning |
|----------|---------|-------|---------|---------|
| `REDIS_ADDR` | `redis_exporter` | `redis://redis:6379` | No | Internal Redis target for metrics. |
| `DATA_SOURCE_NAME` | `postgres_exporter` | assembled from `DB_USER_API` / `DB_PASSWORD_API` | No | Internal PostgreSQL exporter DSN. |

## Default Billing Plan

These optional variables are present in `.env.example` but not currently passed
through `docker-compose.yml`. They are reserved for deployments that explicitly
wire plan bootstrapping into the app container environment.

| Variable | Default | Meaning |
|----------|---------|---------|
| `PLANVAULT_DEFAULT_FREE_PLAN_SLUG` | `free` | Slug for the default plan. |
| `PLANVAULT_DEFAULT_FREE_PLAN_NAME` | `Free` | Display name for the default plan. |
| `PLANVAULT_DEFAULT_FREE_PLAN_MAX_ORGS_AS_OWNER` | `1` | Max organizations a user can own. |
| `PLANVAULT_DEFAULT_FREE_PLAN_MAX_PROJECTS_PER_ORG` | `2` | Max projects per organization. |
| `PLANVAULT_DEFAULT_FREE_PLAN_MAX_MEMBERS_PER_ORG` | `5` | Max members per organization. |
| `PLANVAULT_DEFAULT_FREE_PLAN_MAX_TOKENS` | `1000000` | Token quota. |
| `PLANVAULT_DEFAULT_FREE_PLAN_MAX_AUTO_SCENARIOS` | `10` | Auto-scenario quota. |

## Compose Override Pattern

Prefer an override file for site-specific changes:

```yaml
# docker-compose.override.yml
services:
  api:
    environment:
      SESSION_RETENTION_DAYS: "180"
  jobs:
    environment:
      SESSION_RETENTION_DAYS: "180"
```

Start with:

```bash
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.override.yml up -d
```

For settings used by both `api` and `jobs`, update both services. Many runtime
features require the two roles to agree.
