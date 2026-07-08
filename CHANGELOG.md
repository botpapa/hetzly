# Changelog

All notable changes to Hetzly are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Hetzly does not yet follow strict semantic versioning pre-1.0 — expect the shape of things to
settle further before a `1.0.0` tag.

## [Unreleased]

Everything built since the M4 milestone tag, in one multi-project overhaul.

### Added

- **Multi-project UX overhaul**: any number of Cloud projects, Robot accounts, and Storage Box
  accounts side by side, with a cross-account Dashboard rollup, search, and quick actions; project
  names can now be derived automatically from server naming.
- **Live-API compatibility pass**: fixes for multi-series charts (In/Out and Read/Write no longer
  joined into one path), correctness fixes surfaced by exercising the app against real Hetzner
  accounts rather than fixtures alone, and token-recovery flows for expired/revoked credentials.
- **Storage Boxes**: a full feature module (`Hetzly/Features/StorageBoxes/`) — account management,
  usage/quota visibility, subaccounts, snapshots, and access configuration.
- **Robot vSwitch + failover IP routing**: list/create/update/delete vSwitches, attach/detach
  servers, and switch failover IP routing, surfaced as new sections in the Dedicated tab.
- **CSV export**: `CostsCSVExporter` builds a CSV (project, name, kind, monthly projected, MTD,
  currency) from the cost dashboard, shared via a toolbar menu alongside the existing image share
  card.
- **Adaptive light mode**: the design system now supports a light appearance in addition to the
  original dark-first canvas; Appearance in Settings offers Dark/System.
- **Chart scroll/scrub fix**: a UIKit hold-to-scrub gesture recognizer replaces the earlier
  SwiftUI-only approach so chart-origin scrolling behaves correctly during drag.
- **Red panda mascot redraw**: Hetzi's sprites were redrawn and then replaced again with converted
  frame data derived from Elthen's "2D Pixel Art Red Panda Sprites" pack — see
  [ASSETS-LICENSE.md](ASSETS-LICENSE.md) for the licensing terms that come with that swap (asset
  redistribution is restricted; resolve before publishing).
- **UX polish waves**: Settings simplified into four sections (Accounts, Security, Appearance,
  About) with accounts merged into one kind-subgrouped list; a tightened create-server wizard;
  dashboard search and quick actions.
- **In-app SSH terminal**: an opt-in full terminal (`Hetzly/Features/Terminal/`) to Cloud and Robot
  servers, built on `apple/swift-nio-ssh` and `migueldeicaza/SwiftTerm` — the app's first
  third-party dependencies, scoped to this one feature (see
  [CONTRIBUTING.md](CONTRIBUTING.md#the-dependency-rule)).
- **Manual price overrides**: `DedicatedPriceStore`/`DedicatedPriceSheet` let the cost dashboard
  reflect grandfathered/legacy per-server pricing that Hetzner's API doesn't expose, stored
  on-device only.
- New app icon: replaced with the project's own red panda logo (`app-icon.png`), generated into the
  asset catalog via `scripts/generate_icons.swift`.
- Centralized outbound links (`Hetzly/App/AppLinks.swift`) — GitHub and privacy-policy URLs now
  live in one place ahead of public release.

### Fixed

- Dashboard chart scroll/scrub behavior on chart origin drag.
- Multi-series chart lines no longer incorrectly join In/Out and Read/Write into a single path.
- Various live-API response shape mismatches surfaced only against real Hetzner accounts.

### Changed

- README, SECURITY.md, and CONTRIBUTING.md corrected: the app is no longer "zero third-party
  dependencies" — see the Added section above and
  [CONTRIBUTING.md](CONTRIBUTING.md#the-dependency-rule).

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
