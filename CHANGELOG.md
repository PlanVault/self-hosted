# Changelog

All notable changes to this deployment configuration will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Images follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
