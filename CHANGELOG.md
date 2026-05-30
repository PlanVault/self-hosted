# Changelog

All notable changes to this deployment configuration will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Images follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
