# Security Artifacts

This page centralizes the PlanVault self-hosted artifacts commonly requested by
security, procurement, and platform-review teams.

## Official Resources

| Resource | URL |
|----------|-----|
| Security overview | <https://planvault.ai/security#main> |
| API runtime SBOM | <https://planvault.ai/sbom/latest.json> |
| SBOM manifest | <https://planvault.ai/sbom/manifest.json> |
| SBOM discovery | <https://planvault.ai/.well-known/sbom> |
| Product docs | <https://planvault.ai/docs#main> |
| API docs | <https://planvault.ai/api-docs#/main> |
| Integration examples | <https://github.com/PlanVault/planvault-examples> |

The deployment configuration in this repository is licensed under
Apache-2.0. The PlanVault application container images are commercial software
and require a valid license key.

## Image Provenance

Images are signed keylessly via Sigstore. Verify the pinned release before
deploying:

```bash
VERSION="$(tr -d '[:space:]' < VERSION)"
for image in api front; do
  cosign verify "ghcr.io/planvault/${image}:${VERSION}" \
    --certificate-identity-regexp="github.com/planvault" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
done
```

Use the same `VERSION` value as `PLANVAULT_VERSION` in `.env`.

## SBOM Coverage

The public CycloneDX SBOM currently covers the API runtime image. Frontend SBOMs
are generated for internal vulnerability scanning but are not currently
published.

Use the SBOM manifest to discover published SBOM files and metadata:

```text
https://planvault.ai/sbom/manifest.json
```

## Review Documents

| Document | Purpose |
|----------|---------|
| `SECURITY_MODEL.md` | Encryption model, DEK storage, session store, deletion-log behavior, logging rules. |
| `CONFIGURATION.md` | Full environment-variable and Compose runtime reference. |
| `docs/production-topology.md` | Single-host topology, stateful services, volumes, and trust boundaries. |
| `docs/networking-and-data-boundaries.md` | Inbound/outbound traffic, data boundary rules, VPC guidance. |
| `docs/backup-restore.md` | Backup scope, restore order, RPO/RTO ownership. |
| `docs/monitoring.md` | Observability stack, tenant-safe telemetry guidance. |

## Procurement Checklist

For a standard public self-hosted review, provide:

- the pinned `VERSION`;
- image digests from `docker compose images`;
- Cosign verification output;
- SBOM manifest and API runtime SBOM URL;
- `SECURITY_MODEL.md`;
- `docs/production-topology.md`;
- `docs/networking-and-data-boundaries.md`;
- backup/restore and upgrade runbooks;
- a statement that the public self-hosted repository supports single-host Docker
  Compose in customer-managed or VPC environments.

Restricted-network or fully offline deployments require enterprise-validated
delivery runbooks, mirrored images/packages, license/key delivery process, and
validated smoke tests.

## What Not To Share

Never provide these as security-review artifacts:

- `.env`;
- `PLANVAULT_LICENSE_KEY`;
- provider API keys;
- Tink keyset JSON;
- HMAC keys;
- database dumps;
- raw Keycloak exports containing secrets;
- unredacted logs containing JWTs, cookies, Authorization headers, prompts,
  completions, or tool payloads.
