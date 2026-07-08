# Changelog

All notable changes to Hetzly are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Hetzly does not yet follow strict semantic versioning pre-1.0 — expect the shape of things to
settle further before a `1.0.0` tag.

## [0.1.0] — 2026-07-08

Initial public release. Built across four milestones by a small group of parallel contributors
against a shared module contract ([CONTRACTS.md](CONTRACTS.md)).

### Added

**Foundation (M1)**
- Project scaffold: XcodeGen-driven Xcode project, Swift 6 strict concurrency throughout, zero
  third-party dependencies.
- `HetznerKit` package: HTTP client core with pagination, rate limiting, and Hetzner-shaped error
  mapping; shared across Cloud and Robot.
- Design system: Liquid Glass components (`GlassCard`, `GlassChip`), color palette, spacing/radius
  scale, dark-first canvas background.
- Security primitives: Keychain storage (`ThisDeviceOnly`, non-synchronizable), biometric gate,
  privacy overlay, secure token entry field.
- Hetzi, the pixel-art mascot: Canvas-rendered sprite engine with an `idle`/`walk`/`run`/`sleep`/
  `alarm`/`celebrate`/`work`/`peek` state set.

**Cloud (M2)**
- Full Hetzner Cloud API coverage in `HetznerKit`: servers, volumes, networks, firewalls, load
  balancers, DNS zones, images, snapshots, floating IPs, primary IPs, placement groups, SSH keys,
  certificates, pricing.
- Guided create-server wizard (location → image → type → networking → SSH keys → review).
- Server detail: power actions, rescue mode, rebuild, resize, backups, protection locks, labels,
  console access, live CPU/disk/network metrics with sparklines.
- Dashboard: cross-project server rollup, cost burn card, attention section for servers needing a
  look, stale-while-revalidate snapshot caching.
- On-device SSH key generation (Ed25519, CryptoKit).

**Robot & cost dashboard (M3)**
- `RobotClient` in `HetznerKit`: serialized request queue, conservative rate budget (~150/h),
  5-minute response cache, single-attempt login policy — matching Hetzner Robot's stricter
  operational constraints.
- Dedicated server management: rename, reset (soft/hard/manual), Wake-on-LAN, rescue mode, boot
  configuration, reverse DNS.
- Dedicated server ordering: standard and server-market product catalogs, Face-ID-gated and
  double-confirmed order placement, transaction tracking.
- Cost engine (`HetznerKit/Pricing`): pure, deterministic month-to-date and projected-month cost
  aggregation across Cloud and Robot resources, computed entirely on-device.

**Polish & submission (M4)**
- Home Screen widgets (`HetzlyWidgets`): fleet status and top-servers-by-CPU, built from a capped
  on-device snapshot with no network access from the widget extension.
- Siri & Shortcuts support via App Intents: server status lookup, reboot, monthly cost query.
- Dashboard navigation for dedicated (Robot) servers, mascot single-instance and Reduce Motion
  rules audited across every screen, empty-state audit across every list screen.
- App-target unit and UI test targets (`HetzlyTests`, `HetzlyUITests`).
- App Store submission assets: metadata, fastlane lanes, CI test coverage.

### Known limitations

- Storage Box management and automatic cost pull-in are not yet implemented; Storage Box spend can
  be tracked manually via the Costs tab's manual entries.
- English only; no localization yet.
