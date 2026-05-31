# Backup And Restore

This runbook describes what to back up, how to restore, and how to verify a
PlanVault self-hosted deployment.

RPO and RTO are operator-owned targets. PlanVault provides the application and
deployment package; your storage, snapshot, scheduling, encryption, and restore
testing determine the actual recovery guarantees.

## What To Back Up

| Artifact | Required | Why |
|----------|----------|-----|
| PostgreSQL `pg_data` | Yes | Primary application data, Keycloak DB, LiteLLM DB, wrapped DEK metadata, audit/session data. |
| `.env` | Yes | License key, generated credentials, local Tink keyset, HMAC keys, URL settings. Store encrypted. |
| `init/planvault-realm.json` | Yes | Rendered Keycloak realm with generated client secret and public URL settings. Store encrypted. |
| `redis_data` | Recommended | Redis persistence. Cache loss is recoverable but can affect idempotency windows and latency. |
| TLS files under `./tls/` | If direct TLS is used | Required for `direct_tls` profile. |
| `observability/*` volumes | If overlay is used | Prometheus/Grafana/Loki/Tempo local history and settings. |
| `VERSION` and image digests | Recommended | Recreate the exact deployed version. |

Never store `.env`, database dumps, or Keycloak exports in tickets, email, or
unencrypted object storage.

## PostgreSQL Backup Options

### Option A: Volume Snapshot

Use your infrastructure snapshot tooling for the Docker volume backing
`pg_data`. For consistency:

1. Stop writes or schedule a maintenance window.
2. Stop the stack or at minimum stop `api` and `jobs`.
3. Snapshot the volume.
4. Start services again.
5. Record `VERSION`, image digests, and snapshot ID.

### Option B: `scripts/backup.sh`

Use the bundled helper to create a timestamped backup directory:

```bash
./scripts/backup.sh
```

By default it:

- streams a custom-format PostgreSQL dump into `backups/planvault-backup-*`;
- records `VERSION`, Compose files, service/profile lists, and image metadata;
- attempts to save and copy Redis persistence files;
- refuses to copy plaintext `.env` or rendered Keycloak realm files.

To include encrypted sensitive files, prepare them with your own encryption tool
and pass their paths:

```bash
PLANVAULT_ENCRYPTED_ENV_BACKUP=/secure/.env.age \
PLANVAULT_ENCRYPTED_REALM_BACKUP=/secure/planvault-realm.json.age \
  ./scripts/backup.sh
```

Adjust this for your backup system. Avoid printing passwords; Docker Compose
already injects PostgreSQL credentials into the container.

## Configuration Backup

Store encrypted copies of:

```text
.env
init/planvault-realm.json
VERSION
```

The `.env` file contains the local Tink keyset and HMAC keys. Losing it can make
encrypted data unrecoverable.

`scripts/backup.sh` intentionally does not encrypt plaintext files for you. Use
your approved secret-storage process, then pass encrypted artifacts through
`PLANVAULT_ENCRYPTED_ENV_BACKUP` and `PLANVAULT_ENCRYPTED_REALM_BACKUP`.

## Restore Order

1. Provision a clean host with the same or compatible Docker/Compose version.
2. Check out the self-hosted repository at the release matching `VERSION`.
3. Restore `.env`, `VERSION`, and `init/planvault-realm.json`.
4. Restore `pg_data` from snapshot or restore `pg_dump` into PostgreSQL.
5. Restore `redis_data` if available.
6. Restore TLS/cert files if direct TLS is used.
7. Pull the pinned images:

   ```bash
   docker compose --env-file .env pull
   ```

8. Start dependencies and jobs:

   ```bash
   docker compose --env-file .env up -d postgres redis keycloak litellm
   docker compose --env-file .env up -d jobs
   docker compose --env-file .env logs jobs --tail=120
   ```

9. Start remaining services:

   ```bash
   docker compose --env-file .env up -d
   ```

10. Run verification:

    ```bash
    ./scripts/smoke-test.sh
    ```

## Restore Verification Checklist

- `docker compose ps` shows expected services.
- `/health` returns success.
- Keycloak issuer metadata is reachable.
- `jobs` logs do not show migration failures.
- `api` logs do not show license or encryption errors.
- You can sign in with an operator account.
- You can inspect existing organizations/projects/sessions as expected.
- If LLM providers are configured, a non-destructive test session can plan and
  complete.

## RPO / RTO Guidance

Define your own targets:

| Target | Operator decision |
|--------|-------------------|
| RPO | How frequently PostgreSQL and `.env` backups are captured and replicated. |
| RTO | How quickly a replacement host, volumes, secrets, images, and DNS/ingress can be restored. |
| Restore confidence | How often restore tests are performed on a disposable environment. |

Do not claim a production RPO/RTO until you have performed a timed restore test
using your own backup system.

## Backup Verification

Use `scripts/backup-verify.sh` to validate backup metadata:

```bash
./scripts/backup-verify.sh /path/to/backup-directory
```

The verifier checks artifact presence and basic metadata only. It does not
perform a full database restore and does not prove the backup is restorable.

Use `scripts/restore-dry-run.sh` to combine backup verification with the manual
restore order:

```bash
./scripts/restore-dry-run.sh /path/to/backup-directory
```

This is read-only. It does not stop containers, overwrite volumes, or restore
databases.

For high confidence, schedule a periodic disposable restore test:

1. Create a clean VM.
2. Restore the backup.
3. Run `./scripts/smoke-test.sh`.
4. Record elapsed time and failures.
5. Delete the disposable environment.

## Rollback After Failed Upgrade

If the upgrade reached Flyway migrations, image rollback alone may not be safe.
Use the pre-upgrade PostgreSQL snapshot and matching previous image tag.

See `docs/upgrade.md`.
