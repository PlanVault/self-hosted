# Upgrade

This runbook describes a conservative upgrade flow for PlanVault self-hosted.

The key rule: take a verified backup before starting migrations. Flyway
migrations may be irreversible, so image downgrade alone is not a rollback plan.

## Pre-Upgrade Checklist

1. Read `CHANGELOG.md` for the target version.
2. Review the target release `.env.example` for new required variables.
3. Confirm the target images exist and are signed.
4. Review the SBOM manifest:

   <https://planvault.ai/sbom/manifest.json>

5. Back up:
   - PostgreSQL `pg_data`;
   - `.env`;
   - `init/planvault-realm.json`;
   - optional `redis_data`;
   - TLS/certs and observability volumes if used.
6. Record current image digests:

   ```bash
   docker compose --env-file .env images
   ```

7. Run pre-upgrade smoke test:

   ```bash
   ./scripts/preflight-check.sh
   ./scripts/smoke-test.sh
   ```

## Version Pinning

Update both:

```text
VERSION
PLANVAULT_VERSION in .env
```

They must match. Do not use `latest`.

Check:

```bash
tr -d '[:space:]' < VERSION
awk -F= '/^PLANVAULT_VERSION=/{print $2}' .env
```

## Pull New Images

```bash
docker compose --env-file .env pull
```

Optionally verify signatures:

```bash
VERSION="$(tr -d '[:space:]' < VERSION)"
for image in api front; do
  cosign verify "ghcr.io/planvault/${image}:${VERSION}" \
    --certificate-identity-regexp="github.com/planvault" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
done
```

## Migration Order

Start `jobs` first because it is the sole Flyway migration owner:

```bash
docker compose --env-file .env up -d postgres redis keycloak litellm
docker compose --env-file .env up -d jobs
docker compose --env-file .env logs jobs --tail=160
```

Wait for Flyway completion or a clear healthy state before starting the rest:

```bash
docker compose --env-file .env up -d
```

Do not set `PLANVAULT_FLYWAY_MIGRATE=true` on `api`. Do not scale `jobs` above
one replica.

## Post-Upgrade Verification

Run:

```bash
./scripts/smoke-test.sh
docker compose --env-file .env ps
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/health"
```

Then perform an application-level smoke:

- sign in as an operator;
- open an existing organization/project;
- verify Keycloak redirects use the expected public URL;
- run a non-destructive test session if model/provider configuration is present;
- inspect `api` and `jobs` logs for errors.

## Rollback

Safe rollback requires the pre-upgrade database snapshot.

1. Stop the stack:

   ```bash
   docker compose --env-file .env down
   ```

2. Restore the pre-upgrade PostgreSQL snapshot or dump.
3. Restore the previous `.env`, `VERSION`, and `init/planvault-realm.json`.
4. Pull the previous pinned images.
5. Start the stack and run `./scripts/smoke-test.sh`.

If Flyway applied irreversible migrations, do not attempt to roll back by image
downgrade only.

## Failed Upgrade Triage

If the upgrade fails:

1. Do not run repeated migrations blindly.
2. Capture safe diagnostics:

   ```bash
   docker compose --env-file .env ps
   docker compose --env-file .env logs jobs --tail=200
   docker compose --env-file .env logs api --tail=120
   ```

3. Redact logs before sharing.
4. Decide whether to restore the pre-upgrade backup or wait for support
   guidance.

## URL Or Secret Changes During Upgrade

If the upgrade also changes `BASE_URL`, `KC_PUBLIC_HOSTNAME`, or
`KEYCLOAK_ADMIN_CLIENT_SECRET`, re-render the realm before starting Keycloak:

```bash
./scripts/render-keycloak-realm.sh
```
