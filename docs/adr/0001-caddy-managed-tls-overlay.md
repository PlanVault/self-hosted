# ADR 0001: Caddy Managed TLS Overlay

## Status

Accepted

## Context

The public self-hosted package already supports two TLS patterns:

- customer-managed ingress, load balancer, or reverse proxy in front of `edge`;
- `direct_tls`, where operators mount existing certificates into `edge-tls`.

Some pilot deployments need a simpler public-host HTTPS path with automatic
certificates, while the package must remain focused on single-host Docker
Compose and avoid becoming a general ingress platform.

## Decision

Ship an optional `docker-compose.caddy.yml` overlay using Caddy as a managed TLS
reverse proxy in front of the existing `edge` service.

Caddy was chosen for the first overlay because it keeps configuration small,
handles ACME automatically, and does not require Docker labels or a broader
routing model. Traefik remains a reasonable future option if the package needs
more dynamic routing or multi-service ingress features.

## Consequences

- Operators can run public HTTPS pilots without manually provisioning
  certificates.
- Caddy must bind host ports 80 and 443, so `HTTP_PORT` for the base `edge`
  service should be moved away from 80 when the overlay is enabled.
- Customer-managed ingress remains the preferred enterprise pattern when the
  platform already provides WAF, centralized certificate management, or
  identity-aware proxying.
- The overlay does not change the supported topology: internal services remain
  on the private Compose network.
