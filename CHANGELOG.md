# Changelog

All notable changes to this deployment configuration will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Images follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **One connection model for everything outbound.** An MCP server no longer carries its own auth
  mode: it binds a connection (Organisation settings → Connections) exactly as an imported
  OpenAPI service does, through the same resolver, statuses, audit vocabulary and reason codes.
  Nothing to do in `.env` — this is a console and API change.
- `CONFIGURATION.md` section "Outbound MCP Connectors (OAuth 2.1)" is now **"Outbound Connections
  (MCP + API)"**, and states the two prerequisites separately, because they are independent: an
  `https` `BASE_URL` is required by any `oauth2_authorization_code` connection (either flow
  driver), while profile `mcp_outbound` is required only by `flowDriver = mcp_sidecar`.
  `oauth2_client_credentials`, `mtls` and the static modes need neither.
- `docs/troubleshooting.md` section "MCP Endpoint Or OAuth Connector Problems" is split into
  "MCP Endpoint Problems" and **"Connection Problems (Outbound Auth)"**, the latter keyed by the
  `connection_*` reason codes a run actually reports.

### Added
- Documented the `PLANVAULT_CONNECTIONS_*` tuning variables (binding cache TTL, token refresh
  skew, request timeout, max refresh failures, sweep interval, discovery cache TTL). They have
  working defaults in the API image and are **not** wired in `docker-compose.yml`; to change one,
  use a Compose override on both `api` and `jobs`.
- `mtls` connections (client certificate, optionally with an RFC 8705 `tls_client_auth` grant)
  are accepted by every deployment — they need neither the sidecar nor an `https` `BASE_URL`.

### Fixed
- `CONNECTOR_SIDECAR_CLIENT_METADATA_URL` and the OAuth redirect URI now point at
  `${BASE_URL}/api/v1/oauth/client-metadata.json` and `…/api/v1/oauth/callback`. The
  `/api/v1/mcp/oauth/*` routes were removed upstream when MCP moved onto the connection model, so
  a `mcp_outbound` deployment was advertising a client-metadata URL that answers `404`. Deployments
  running that profile must `docker compose up -d outbound-connectors` after upgrading, and
  re-register any client whose authorization server cached the old document URL.

## [0.1.38] — 2026-09-03

MCP release. PlanVault now speaks Model Context Protocol in both directions from one new,
optional image (`ghcr.io/planvault/mcp`, signed and SBOM-published like `api` and `front`).
Nothing changes for a deployment that does not enable the new profiles.

### Added
- Compose profile `mcp` — service `mcp` (inbound role of `ghcr.io/planvault/mcp`): PlanVault as an
  MCP server for Cursor / Claude Code / Claude Desktop at `${BASE_URL}/mcp` (four tools:
  `discover_capabilities`, `execute`, `check_status`, `provide_input`; approvals stay in the
  console). Enable with `PLANVAULT_MCP_ENABLED=true` + `COMPOSE_PROFILES=mcp`.
- Compose profile `mcp_outbound` — service `outbound-connectors` (outbound role of the same
  image): stateless OAuth 2.1 (CIMD → preconfigured → DCR) + Streamable HTTP adapter required
  only for MCP servers registered with `auth_mode = "oauth"`. Enable with
  `PLANVAULT_OUTBOUND_CONNECTORS_ENABLED=true` + `COMPOSE_PROFILES=mcp_outbound`; requires an
  `https` `BASE_URL`.
- Edge route `location = /mcp` in `nginx/default.conf` and `nginx/default-tls.conf` (Streamable
  HTTP: buffering off, long timeouts, upstream resolved at request time so the edge starts
  without the optional service).
- `.env` keys passed through to `api` and `jobs`: `PLANVAULT_MCP_ENABLED`,
  `PLANVAULT_MCP_DASHBOARD_BASE_URL` (= `BASE_URL`), `PLANVAULT_OUTBOUND_CONNECTORS_ENABLED`,
  `PLANVAULT_OUTBOUND_CONNECTORS_PUBLIC_BASE_URL` (= `BASE_URL`),
  `PLANVAULT_OUTBOUND_CONNECTORS_REAUTH_PAUSE_ENABLED`, `OUTBOUND_CONNECTORS_INTERNAL_TOKEN`,
  `CONNECTOR_SIDECAR_CLIENT_NAME`, `COMPOSE_PROFILES`.
- `scripts/generate-secrets.sh` generates `OUTBOUND_CONNECTORS_INTERNAL_TOKEN` (64 hex chars).
- `scripts/preflight-check.sh` validates profile/flag consistency, token length and `https`
  `BASE_URL` for the outbound connector; `scripts/smoke-test.sh` probes `/mcp` (expects 401
  without a key) and includes `mcp` / `outbound-connectors` logs when enabled.
- `docs/adr/0002-mcp-sidecar-profiles.md` — why one image, two roles, two profiles, and why
  `/mcp` is routed through `edge`.
- `CONFIGURATION.md` sections "MCP Agent Server (Inbound)" and "Outbound MCP Connectors
  (OAuth 2.1)" replace the previous "Not In This Distribution" note.

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to `ghcr.io/planvault/*:0.1.38`.
- Cosign verification loop and outbound-dependency tables now list the `mcp` image.
- `README.md`, `SECURITY_MODEL.md`, `docs/production-topology.md`,
  `docs/networking-and-data-boundaries.md`, `docs/smoke-tests.md` and `docs/upgrade.md`
  describe the two optional services and their exposure.

### Fixed
- Cosign verification snippets (`README.md`, `docs/upgrade.md`, `docs/security-artifacts.md`) used
  `--certificate-identity-regexp="github.com/planvault"`, which never matched: the signing identity
  is case-sensitive `https://github.com/PlanVault/planvault/.github/workflows/release.yml@refs/tags/v<version>`.
  The snippets now pin that identity (verified against `api`, `front`, and `mcp` 0.1.38).

### Note
- Versions 0.1.20–0.1.37 were image-only releases without deployment-configuration changes;
  this entry covers the configuration delta since 0.1.19. The MCP agent server authenticates
  with a static Bearer project API key over HTTPS; inbound OAuth 2.1 for MCP clients is not
  part of this release.

## [0.1.19] — 2026-07-05

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to `ghcr.io/planvault/*:0.1.19` (image-only release; no deployment-configuration changes)

## [0.1.18] — 2026-07-05

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to `ghcr.io/planvault/*:0.1.18` (image-only release; no deployment-configuration changes)

## [0.1.17] — 2026-07-05

### Security
- OpenTelemetry Java agent upgraded to 2.26.1 (fixes CVE-2026-33701)
- API and front images rebuilt with fresh OS security patches (fixes CVE-2026-45447 among others)

### Added
- Optional policy consent gate flag `PLANVAULT_POLICY_ACKNOWLEDGEMENT_ENABLED`, passed through by `docker-compose.yml` and documented in `CONFIGURATION.md` / `.env.example` (default off / unchanged behavior)

### Changed
- Org members can approve or deny runtime tool approvals on their own sessions
- Default free plan org-ownership quota of `0` now blocks organization creation (previously untested edge)
- Default `PLANVAULT_VERSION` and `VERSION` pin to `ghcr.io/planvault/*:0.1.17`

### Note
- Versions 0.1.4–0.1.16 were image-only releases without deployment-configuration changes; this entry covers the configuration delta since 0.1.3.

## [0.1.3] — 2026-05-30

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to match `ghcr.io/planvault/*:0.1.3` release images

## [0.1.2] — 2026-05-30

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to match `ghcr.io/planvault/*:0.1.2` release images

## [0.1.1] — 2026-05-30

### Changed
- Default `PLANVAULT_VERSION` and `VERSION` pin to match `ghcr.io/planvault/*:0.1.1` release images

## [0.1.0] — initial public release

### Added
- `docker-compose.yml` single-host stack (PostgreSQL, Redis, Keycloak, LiteLLM, API, Jobs, edge nginx)
- `docker-compose.observability.yml` optional overlay (Grafana, Prometheus, Loki, Tempo, OTel Collector)
- `scripts/generate-secrets.sh` — generates random secrets into `.env`
- `scripts/render-keycloak-realm.sh` — renders Keycloak realm from template
- Public GHCR images (`ghcr.io/planvault/api`, `ghcr.io/planvault/front`) — no registry login required
