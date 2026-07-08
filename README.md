# Hetzly

A premium, open-source iOS client for Hetzner Cloud & Robot — zero backend, zero dependencies, zero telemetry.

> **Not affiliated.** Hetzly is an independent third-party app, not affiliated with or endorsed by Hetzner Online GmbH. "Hetzner" is a trademark of Hetzner Online GmbH.

<!-- screenshot: dashboard-dark.png -->
<!-- screenshot: server-detail-dark.png -->
<!-- screenshot: create-server-wizard-dark.png -->
<!-- screenshot: robot-servers-dark.png -->
<!-- screenshot: cost-dashboard-dark.png -->

## Why

Hetzner's own mobile experience is a web view. Hetzly is a native SwiftUI app built for iOS 26, with Liquid Glass UI, dark-first design, and no server of its own sitting between you and the Hetzner API. Your API tokens never leave your device.

## Features

- **Cloud — full coverage**: servers, volumes, networks, firewalls, load balancers, images, snapshots, floating IPs, primary IPs, placement groups, SSH keys, and a guided **create-server wizard**.
- **Robot — dedicated servers**: server management, rescue mode, reset, and **ordering new dedicated servers** directly from the app.
- **Cost dashboard**: spend across Cloud and Robot resources, computed entirely on-device from live resource + pricing data — nothing is sent to a third-party billing service.
- **Storage Boxes** — planned for phase 2.
- **Mascot**: a small pixel-art companion that reacts to what's happening in your infrastructure.

## Security model

- API tokens are stored in the iOS **Keychain** with `ThisDeviceOnly` accessibility and are **non-synchronizable** — they never go to iCloud Keychain, never leave the device.
- Sensitive actions (viewing/editing tokens, destructive operations) are gated behind **Face ID / Touch ID** with passcode fallback.
- **No telemetry, no analytics, no crash reporters.** The app makes network requests to the Hetzner Cloud and Robot APIs only — direct device-to-Hetzner, nothing in between.
- App Store privacy label: **Data Not Collected**.
- See [SECURITY.md](SECURITY.md) for the full model and how to report a vulnerability.

## Building

Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen
open Hetzly.xcodeproj
```

The `.xcodeproj` is generated from [`project.yml`](project.yml) and is **not** committed — re-run `xcodegen` any time `project.yml` or the file layout changes.

To build and test the API layer directly:

```sh
swift test --package-path Packages/HetznerKit
```

## Project structure

```
.
├── project.yml                  # XcodeGen spec — source of truth for the Xcode project
├── Hetzly/                      # App target
│   ├── App/                     # App entry point, DI container, root view
│   ├── DesignSystem/            # Colors, spacing, glass components, shared views
│   ├── Features/                # Feature modules (Cloud, Robot, dashboard, onboarding, ...)
│   ├── Mascot/                  # Pixel-art mascot rendering
│   ├── Security/                # Keychain, biometrics, privacy overlay
│   ├── Store/                   # Local app state / persistence
│   └── Resources/               # Asset catalog, Info.plist
├── Packages/
│   └── HetznerKit/              # UI-free SPM package: Hetzner Cloud + Robot API client
└── .github/workflows/           # CI
```

## Roadmap

- **M1 — Scaffold**: project skeleton, design system, security primitives, HetznerKit core (this milestone).
- **M2 — Cloud read + write**: full Cloud resource browsing, server actions, create-server wizard.
- **M3 — Robot + cost dashboard**: dedicated server management and ordering, on-device cost aggregation.
- **M4 — Polish**: Storage Boxes, mascot states, accessibility pass, App Store submission.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

Hetzner runs an [Open Source & Cloud Native program](https://www.hetzner.com/unternehmen/open-source-cloud-native/) that provides cloud resources to qualifying open-source projects; contributions and sponsorship inquiries related to that program are welcome via GitHub issues.
