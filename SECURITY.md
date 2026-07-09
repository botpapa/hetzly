# Security Policy

Hetzly manages API tokens that grant full control over your Hetzner Cloud
projects and Robot (dedicated server) account. This document describes the
security model and how to report problems.

## How tokens are stored

- Cloud API tokens and Robot credentials are written to the iOS **Keychain**
  via `KeychainStore` (`Hetzly/Security/KeychainStore.swift`) using
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the item is decryptable
  only on this device, only while unlocked, and is **not** included in
  iCloud Keychain sync or device backups that carry Keychain data.
- Tokens are held in memory only as long as needed for an in-flight request
  and are never written to `UserDefaults`, disk caches, or logs.
- Reading or revealing a stored token, and any destructive action (deleting
  a server, resetting a Robot server, disabling rescue mode, ordering a
  dedicated server, etc.), is gated behind `BiometricGate` — Face ID / Touch
  ID with device passcode fallback. Order placement is gated unconditionally,
  regardless of the destructive-actions setting, and is additionally
  double-confirmed on a review screen before biometrics are requested.
- Robot's own login form enforces a conservative **single login attempt**
  policy in the app: we deliberately do not retry a failed Robot
  username/password submission automatically. Hetzner's Robot web login
  locks out an account after a small number of failed attempts, and Robot
  does not support scoped tokens the way Cloud does — a retry loop client-side
  risks tripping that lockout on the user's behalf. Failures are surfaced
  immediately so the user can correct input by hand.
- All Robot requests are **serialized through a single queue** inside
  `RobotClient` (`Packages/HetznerKit/Sources/HetznerKit/RobotAPI/RobotClient.swift`)
  — never more than one in-flight Robot request at a time — with a
  conservative ~150 requests/hour token-bucket budget and a 5-minute response
  cache on GETs. There is no background polling of Cloud or Robot; every
  fetch is either explicit (pull-to-refresh, opening a screen) or a
  deliberately capped background snapshot for Home Screen widgets.
- App content is blurred behind `PrivacyOverlay`
  (`Hetzly/Security/PrivacyOverlay.swift`) whenever the app leaves the
  foreground (`scenePhase != .active`), so server names, IPs, and account
  balances aren't visible in the iOS app switcher.
- Short-lived sensitive values copied to the clipboard (a freshly revealed
  Robot rescue password, a generated SSH private key) go through
  `SensitivePasteboard` (`Hetzly/Security/SensitivePasteboard.swift`), which
  marks the pasteboard item `.localOnly` and sets an automatic expiration
  (default 60s) rather than leaving it there indefinitely.

## What never happens

- **No logging of secrets.** Authorization headers, bearer tokens, and Robot
  credentials are never passed to `print`, `os_log`, or `Logger`. CI enforces
  this with a grep guard over `Hetzly` and `Packages` (see
  `.github/workflows/ci.yml`).
- **No third-party servers.** The app talks directly to
  `api.hetzner.cloud` and `robot-ws.your-server.de` (Hetzner's own APIs).
  There is no Hetzly backend, no analytics endpoint, no crash reporter.
- **No App Transport Security exceptions.** Hetzly ships with ATS defaults —
  no `NSAllowsArbitraryLoads`, no per-domain exceptions. All traffic is TLS.
- **No telemetry.** No usage analytics, no crash reporting SDKs. The app and
  `HetznerKit` have no third-party dependencies; the sole exception is the
  optional in-app SSH terminal (`Hetzly/Features/Terminal/`), which uses
  Apple's [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) and
  [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — both permissively
  licensed (Apache 2.0 / MIT). See [CONTRIBUTING.md](CONTRIBUTING.md#the-dependency-rule).

## Reporting a vulnerability

Please report security issues privately via
[GitHub Security Advisories](https://github.com/botpapa/hetzly/security/advisories/new)
<!-- TODO(release): replace botpapa with the real GitHub org/user — see AppLinks.swift -->
for this repository rather than opening a public issue. Include the affected
version/commit, reproduction steps, and impact. We aim to acknowledge reports
within a few days.

Please do not report suspected vulnerabilities in the Hetzner Cloud or Robot
APIs themselves here — those should go to Hetzner directly.
