# PlanVault Self-Hosted Security Model

This document explains the security-related runtime settings in the self-hosted
Compose stack. For the full parameter table, see `CONFIGURATION.md`.

## Security Boundary

The public self-hosted profile is a single-host Docker Compose deployment:

- `edge` is the only service with host ports.
- `api`, `jobs`, `postgres`, `redis`, `keycloak`, and `litellm` stay on the
  private Docker network `planvault`.
- Secrets live in `.env` on the host and are injected as environment variables.
- Durable data lives in named Docker volumes (`pg_data`, `redis_data`, and
  optional observability volumes).

The deployment assumes the host, Docker daemon, `.env`, and volume snapshots are
admin-controlled assets. Protect them as production secrets/data.

## Network And Data Boundary

The supported public self-hosted profile is intended for customer-managed or VPC
networks:

- Browser and API traffic enters through `edge`.
- Application services communicate over the private Docker network.
- Outbound runtime traffic goes only to endpoints you configure: LLM providers,
  local/private LiteLLM-compatible model endpoints, integrated APIs, MCP
  servers, webhooks, and optional observability collectors.
- There is no separate PlanVault product telemetry in the self-hosted stack.

Restricted-network or fully offline delivery is an advanced enterprise path. It
requires mirrored images/packages, an operator runbook, license/key delivery
process, and a validated smoke test. It is not a one-line `.env` or Compose
toggle.

## Supply-Chain Artifacts

PlanVault publishes supply-chain artifacts for procurement and security review:

- Latest API runtime SBOM: <https://planvault.ai/sbom/latest.json>
- Machine-readable SBOM manifest: <https://planvault.ai/sbom/manifest.json>
- SBOM discovery endpoint: <https://planvault.ai/.well-known/sbom>
- Security overview: <https://planvault.ai/security#main>

The public CycloneDX SBOM currently covers the API runtime image. Frontend SBOMs
are generated for internal vulnerability scanning but are not currently
published. Use Cosign verification in `README.md` for image provenance and the
SBOM manifest for dependency/component review.

For the procurement/security-review index, see
`docs/security-artifacts.md`.

## Envelope Encryption And DEKs

PlanVault uses envelope encryption for sensitive application data.

Terminology:

- **DEK**: Data Encryption Key. A per-tenant or per-organization key used to
  encrypt sensitive data.
- **KEK**: Key Encryption Key. A higher-level key used to wrap/protect DEKs.
- **Wrapped DEK**: A DEK encrypted by the KEK before storage.

In the supported self-hosted profile:

| Setting | Value | Meaning |
|---------|-------|---------|
| `SECURITY_KMS_ENABLED` | `false` | Cloud KMS integration is disabled. |
| `TINK_LOCAL_KEYSET_JSON` | generated locally | Local Tink KEK material. |
| `DEK_STORE` | `postgres` | Wrapped org DEKs are stored in PostgreSQL. |

This is deliberate: the public self-hosted stack can run without AWS, IAM, KMS,
or DynamoDB. The operator owns the host and the `.env` file containing the local
Tink keyset.

## What `TINK_LOCAL_KEYSET_JSON` Means

`scripts/generate-secrets.sh` generates `TINK_LOCAL_KEYSET_JSON` as a local Tink
keyset and writes it into `.env`.

Operational rules:

- Back it up securely with `.env`.
- Do not paste it into support tickets, email, chat, logs, or issue trackers.
- Do not regenerate it for an existing deployment unless you are following an
  explicit key-rotation procedure.
- If you lose it, data encrypted under DEKs protected by that key material may
  become unrecoverable.

For self-hosted v1, this local keyset is the practical replacement for a cloud
KMS dependency.

## What `DEK_STORE=postgres` Means

`DEK_STORE` controls where PlanVault stores wrapped DEK metadata.

Supported application modes:

| Mode | Meaning | Self-hosted status |
|------|---------|--------------------|
| `postgres` | Store wrapped DEKs in the bundled PostgreSQL database. | Supported default. |
| `dynamodb` | Store/mirror wrapped DEKs in DynamoDB tables. | Hosted/advanced only; not exposed in the public self-hosted Compose profile. |

`DEK_STORE=dynamodb` is not a safe one-line change in `docker-compose.yml`.
It requires:

- DynamoDB table provisioning.
- AWS region / endpoint configuration.
- IAM or local endpoint credentials.
- Backup and restore runbooks.
- Deletion-log and graveyard-table decisions.
- Clean-VM smoke testing.

For supported self-hosted deployments, keep `DEK_STORE=postgres`.

## Session Store And Event Storage

`SESSION_STORE_MODE` controls where session events, session runs, and related
cleanup state are stored.

The public self-hosted Compose file pins:

| Setting | Value | Meaning |
|---------|-------|---------|
| `SESSION_STORE_MODE` | `postgres` | Use PostgreSQL-backed session event/run stores. |
| `PEKKO_JOURNAL_PLUGIN` | `jdbc-journal` | Use JDBC-backed actor persistence. |
| `PEKKO_SNAPSHOT_PLUGIN` | `jdbc-snapshot-store` | Use JDBC-backed snapshots. |

Supported application modes:

| Mode | Meaning | Self-hosted status |
|------|---------|--------------------|
| `postgres` | Session events/runs in PostgreSQL. | Supported default. |
| `dynamodb` | Session events/runs and cleanup state in DynamoDB. | Hosted/advanced only. |
| `memory` | In-process state. | Development/testing only; loses data on restart. |
| `file` | File-backed local state. | Development/testing only. |

### Using A Separate Event Database

The code has lower-level support for a separate PostgreSQL session-store JDBC
URL, but the public self-hosted Compose contract does not expose it as a
supported knob yet.

To support a separate event database safely, the release would need:

1. New `.env.example` variables for the separate session-store JDBC URL/user/password.
2. Those variables passed to both `api` and `jobs`.
3. Schema ownership and migrations for the separate database.
4. Backup and restore guidance for both primary and event stores.
5. Connection pool sizing guidance.
6. Smoke tests for install, upgrade, rollback, and restore.

Until then, the supported path is bundled PostgreSQL.

## GDPR Deletion Log

`GDPR_DELETION_LOG_ENABLED` controls an append-only deletion-log integration used
by DynamoDB-backed deployments.

In the public self-hosted profile:

| Setting | Value | Meaning |
|---------|-------|---------|
| `GDPR_DELETION_LOG_ENABLED` | `false` | DynamoDB-backed deletion log is disabled. |
| `GDPR_RECONCILIATION_ON_STARTUP` | `false` | Startup reconciliation is disabled. |

This does not mean GDPR deletion is disabled. It means the optional external
append-only deletion-log backend is not part of the supported public
self-hosted Compose profile.

Turning it on requires more than a boolean change:

- a deletion-log storage backend;
- retention/TTL policy;
- reconciliation runbook;
- access control;
- monitoring and alerting;
- support validation.

## Organization Soft Delete

Organization deletion is modeled as a soft-delete window followed by hard-delete
cleanup.

| Setting | Default | Meaning |
|---------|---------|---------|
| `PLANVAULT_ORG_SOFT_DELETE_GRACE_DAYS` | `7` | Number of days an organization remains restorable before hard delete. |
| `PLANVAULT_ORG_SOFT_DELETE_SWEEPER_INTERVAL_HOURS` | `24` | How often the `jobs` role wakes the hard-delete sweeper. |

Operational impact:

- A longer grace period increases the time deleted org data remains in the
  system.
- A shorter grace period reduces recovery time after accidental deletion.
- The sweeper runs in `jobs`, so do not scale `jobs` above one replica.
- In advanced DynamoDB DEK-store deployments, the soft-delete grace window must
  align with DEK graveyard-table TTL and backup/PITR policy.

For typical pilots, keep the default `7` days unless your data-retention policy
requires a different window.

## Logging And Diagnostics

The self-hosted Compose profile pins:

| Setting | Value | Meaning |
|---------|-------|---------|
| `PLANVAULT_LOG_LLM_BODIES` | `false` | Raw LLM request/response bodies are not logged. |
| `OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL_CAPTURE_ALL_MDC_ATTRIBUTES` | `true` | MDC fields may be exported when OpenTelemetry logs are enabled. |
| `OBSERVABILITY_TENANT_HMAC_KEY` | generated | Tenant labels can be pseudonymized for observability. |

Rules for support bundles:

- Share `docker compose ps`, image digests, `VERSION`, and redacted logs.
- Do not share `.env`, license keys, raw database dumps, Keycloak exports with
  secrets, JWTs, provider API keys, or unredacted request/LLM bodies.
- Redact bearer tokens, cookies, Authorization headers, and provider keys before
  sending logs.

## Keycloak And Identity

Keycloak is bundled for self-hosted deployments and served through edge at
`/keycloak`.

Important settings:

- `KC_PUBLIC_HOSTNAME` is the public Keycloak URL.
- `KEYCLOAK_ISSUER` is the issuer the backend expects in tokens.
- `KEYCLOAK_ADMIN_CLIENT_SECRET` is used by the backend confidential client.
- `KEYCLOAK_SKIP_ACCESS_TOKEN_AUDIENCE_ISSUER_CHECKS=false` should remain false
  in production.

After changing URL or client-secret settings, re-render the realm:

```bash
./scripts/render-keycloak-realm.sh
docker compose --env-file .env up -d keycloak api jobs
```

## Secret Handling Checklist

- Keep `.env` out of Git. It is already ignored; do not override that.
- Store an encrypted backup of `.env` and `init/planvault-realm.json`.
- Rotate generated secrets only with a tested procedure.
- Limit access to Docker host admins.
- Protect volume snapshots like production data.
- Use TLS at your ingress or the optional `direct_tls` profile before exposing
  the stack outside localhost.

## Supported Self-Hosted Defaults

For a standard public self-hosted deployment, these values should stay as-is:

| Setting | Supported value |
|---------|-----------------|
| `SECURITY_KMS_ENABLED` | `false` |
| `DEK_STORE` | `postgres` |
| `SESSION_STORE_MODE` | `postgres` |
| `GDPR_DELETION_LOG_ENABLED` | `false` |
| `PLANVAULT_LOG_LLM_BODIES` | `false` |
| `PLANVAULT_FLYWAY_MIGRATE` on `api` | `false` |
| `PLANVAULT_FLYWAY_MIGRATE` on `jobs` | `true` |

If a customer needs AWS KMS, DynamoDB DEK storage, a separate event database, or
external deletion logs, treat that as an advanced deployment design and validate
it with PlanVault support before production use.
