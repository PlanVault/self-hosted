# ADR 0002: MCP sidecar as two optional Compose profiles from one image

- Status: Accepted
- Date: 2026-09-03

## Context

PlanVault speaks Model Context Protocol (MCP) in two directions:

1. **Inbound** — PlanVault is an MCP server. Cursor, Claude Code and Claude Desktop connect
   with a project API key scoped to `hrn:project:mcp:execute` and see exactly four tools
   (`discover_capabilities`, `execute`, `check_status`, `provide_input`) that drive the whole
   governed tool catalog. Approvals are never granted over MCP; the client receives an
   `approval_url` into the console.
2. **Outbound** — PlanVault is an MCP client. Third-party MCP servers are registered per
   organisation over stdio or Streamable HTTP. The `stdio`, `bearer` and `headers` auth modes
   are handled by the API process itself. The `oauth` mode (OAuth 2.1 authorization code +
   PKCE, client registration CIMD → preconfigured → DCR) needs the official MCP SDK, which is
   Node-only.

Upstream ships both directions from **one Node image**, `ghcr.io/planvault/mcp`, selected at
runtime by `SIDECAR_ROLES` (`inbound`, `outbound`, or both). The official SDK being Node-only
justified a new *runtime*, not a second *deploy unit*; the number of deploy units follows
security and scaling boundaries, not the number of protocols.

The self-hosted stack must keep its rules: `edge` is the only service with host ports, every
other service stays on the private Docker network, and a deployment that does not use a
feature must not have to run its container.

## Decision

1. **Two services, one image, two profiles.**
   - `mcp` (profile `mcp`): `SIDECAR_ROLES=inbound`, listens on `:8877 /mcp`, private network
     only.
   - `outbound-connectors` (profile `mcp_outbound`): `SIDECAR_ROLES=outbound`, listens on
     `:8878 /connectors/*`, private network only, shared bearer
     `OUTBOUND_CONNECTORS_INTERNAL_TOKEN`.
   - The two roles never share a listener or a router. Running them as separate containers
     keeps process-level isolation between a **public** surface (per-request end-user Bearer)
     and an **internal** surface (shared internal bearer), which is the shape upstream
     recommends for hardened deployments.
2. **Inbound MCP is routed through `edge`** at `location = /mcp` instead of publishing `:8877`
   on the host. This keeps the single-entry-point rule, reuses the customer's TLS/ingress and
   Caddy overlay unchanged, and means the public MCP URL is simply `${BASE_URL}/mcp`. The
   upstream is resolved at request time through Docker's embedded DNS (`resolver 127.0.0.11`)
   so nginx starts even when the optional `mcp` service is not running; a request then fails
   with 502 rather than breaking the whole edge.
3. **Feature flags and profiles are paired, not merged.** The API-side flags
   (`PLANVAULT_MCP_ENABLED`, `PLANVAULT_OUTBOUND_CONNECTORS_ENABLED`) stay explicit `.env`
   values passed to both `api` and `jobs`; the containers are started by Compose profiles.
   `scripts/preflight-check.sh` warns when a flag and its profile disagree. An operator
   therefore cannot accidentally expose the MCP façade by starting a container, nor run the
   API with a feature pointed at a sidecar that does not exist.
4. **The outbound shared bearer is always generated** by `scripts/generate-secrets.sh`, even
   when the profile is off, so enabling OAuth MCP servers later is a flag flip rather than a
   secret rotation across two services.
5. **Both flags default to `false`** and both profiles are off by default. A deployment that
   ignores this ADR behaves exactly as before 0.1.38.

## Consequences

- One extra image to pull, verify (Cosign) and review (SBOM) when either profile is enabled:
  `ghcr.io/planvault/mcp:${PLANVAULT_VERSION}`. `README.md` and `docs/security-artifacts.md`
  list it next to `api` and `front`.
- `BASE_URL` must be `https` before enabling `mcp_outbound`: the OAuth redirect URI and the
  CIMD client document are derived from it, and the API refuses to start otherwise
  (`http://localhost` is tolerated for a local trial).
- The MCP agent server authenticates with a static Bearer project API key over HTTPS. Inbound
  OAuth 2.1 for MCP clients is an upstream roadmap item and will arrive as a new image version,
  not as a Compose change.
- `redis` is already mandatory in this stack, which the MCP façade requires for idempotency;
  no new stateful service is introduced.
- Rollback: remove the profiles from `COMPOSE_PROFILES`, set both flags to `false`,
  `docker compose up -d --remove-orphans`. No schema or data migration is tied to these
  profiles.
