# Smoke Tests

Use `scripts/smoke-test.sh` to verify that a self-hosted PlanVault deployment is
configured correctly and reachable after install, upgrade, restore, or support
triage.

The smoke test is intentionally safe: it does not print `.env`, license keys,
provider API keys, JWTs, cookies, or database dumps.

## When To Run

Run the smoke test:

- after initial installation;
- after changing `.env` URL or Keycloak values;
- after each upgrade;
- after restore from backup;
- before opening a support ticket;
- after changing ingress/TLS or observability wiring.

## Command

```bash
./scripts/smoke-test.sh
```

The script exits with code `0` when there are no hard failures. Warnings do not
make the command fail, but they should be reviewed before production use.

## What It Checks

| Check | Meaning |
|-------|---------|
| Required tools | Confirms `docker`, Compose v2, `curl`, `openssl`, `python3`, and `envsubst` are available. |
| Required files | Confirms `.env`, `VERSION`, `docker-compose.yml`, and the rendered Keycloak realm exist. |
| `.env` placeholders | Detects unresolved `__GENERATE__` values and missing required keys. |
| License key presence | Confirms `PLANVAULT_LICENSE_KEY` is set and not the invalid example value. |
| Version pin | Confirms `PLANVAULT_VERSION` matches `VERSION`. |
| URL consistency | Confirms `KEYCLOAK_ISSUER` matches `KC_PUBLIC_HOSTNAME + /realms/planvault` and warns if `CORS_ORIGINS` does not include `BASE_URL`. |
| Compose config | Runs `docker compose --env-file .env config --quiet`. |
| Service status | Prints `docker compose ps` output. |
| Health endpoint | Calls `http://127.0.0.1:${HTTP_PORT:-80}/health`. |
| Keycloak metadata | Attempts to reach the public issuer metadata from the host. |
| API/jobs logs | Prints redacted log tails and warns on common fatal markers. |

## Typical Failures

### Missing `.env`

Run:

```bash
./scripts/generate-secrets.sh
```

Then set `PLANVAULT_LICENSE_KEY` and confirm the public URL values before
starting the stack.

### Invalid License

The smoke test cannot validate license semantics by itself, but it can detect
the invalid example value. If the API logs still show license errors:

1. Confirm you pasted the full offline license JWT.
2. Confirm it was not line-wrapped by a password manager or ticket system.
3. Confirm the license matches the release/channel you are deploying.
4. Contact `support@planvault.ai` with redacted logs and image digests.

Never send the license key itself.

### Version Mismatch

`PLANVAULT_VERSION` in `.env` must match `VERSION` and a published image tag.
Fix the mismatch, then run:

```bash
docker compose --env-file .env pull
docker compose --env-file .env up -d
./scripts/smoke-test.sh
```

### Keycloak URL Mismatch

If login redirects fail or the smoke test reports issuer mismatch:

1. Set `BASE_URL`, `KC_PUBLIC_HOSTNAME`, and `KEYCLOAK_ISSUER` consistently.
2. Ensure `KEYCLOAK_ISSUER` equals `KC_PUBLIC_HOSTNAME + /realms/planvault`.
3. Re-render the realm:

   ```bash
   ./scripts/render-keycloak-realm.sh
   docker compose --env-file .env up -d keycloak api jobs
   ```

### Flyway Or Migration Failure

Flyway runs only in `jobs`. Inspect:

```bash
docker compose --env-file .env logs jobs --tail=120
```

Do not scale `jobs` above one replica. If a migration failed during upgrade,
do not downgrade images without restoring the database snapshot taken before the
upgrade.

### API Unhealthy

Check dependencies in order:

```bash
docker compose --env-file .env ps
docker compose --env-file .env logs jobs --tail=120
docker compose --env-file .env logs api --tail=120
docker compose --env-file .env logs keycloak --tail=80
docker compose --env-file .env logs litellm --tail=80
```

Redact secrets before sharing logs.

### LiteLLM Or Provider Missing

The core stack may start even without infrastructure-level provider keys if you
use org-level BYOK later. If model calls fail:

1. Confirm provider configuration in the product or `.env`.
2. Confirm outbound network access to the provider or local/private model
   endpoint.
3. Inspect `litellm` logs after redaction.

## Support Escalation Checklist

Share only:

- `VERSION`;
- `docker compose ps`;
- `docker compose images`;
- smoke test output;
- redacted `api`, `jobs`, `keycloak`, and `litellm` logs;
- `/health` result.

Never share `.env`, `PLANVAULT_LICENSE_KEY`, provider API keys, JWTs, database
dumps, or raw Keycloak exports.
