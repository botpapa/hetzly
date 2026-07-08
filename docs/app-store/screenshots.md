# App Store screenshot capture guide

Exactly what to do to produce the `fastlane/screenshots/en-US/*.png` set used
by `fastlane deliver` / manual App Store Connect upload. Screenshots are
captured from the iOS Simulator, not staged mockups — same policy as the
`docs/screenshots/*.png` pair embedded in the top-level README.

## 1. Required device sizes (2026 App Store)

App Store Connect's iPhone screenshot matrix is keyed off display size, not
device model name. As of this app's target (iOS 26, Xcode 26):

| Requirement | Display size | Simulator device | Resolution (px) |
|---|---|---|---|
| **Primary — required** | 6.9" | **iPhone 17 Pro Max** | **1320 × 2868** |
| Fallback (optional, only if you want dedicated art for smaller-display listings rather than relying on Apple's automatic scaling) | 6.7"/6.5" | iPhone 17 Pro / iPhone 15 Plus-class simulator | varies by device |

**Capture the 6.9" set first — it's the one that's actually required.**
Apple auto-scales the 6.9" set down to satisfy smaller iPhone display
buckets, so the fallback sizes are only worth the extra time if you want
pixel-perfect (not scaled) art for those buckets. Always double-check the
current requirement matrix in App Store Connect → your app → App Store →
[locale] → iPhone Screenshots at submission time — Apple revises this list
periodically and this table can go stale.

If a 6.9"-class simulator isn't installed: Xcode → Settings → Platforms, or
`xcodebuild -downloadPlatform iOS`, then confirm with
`xcrun simctl list devicetypes | grep "17 Pro Max"`.

## 2. Boot the simulator

```sh
xcrun simctl boot "iPhone 17 Pro Max" 2>/dev/null || true
xcrun simctl bootstatus "iPhone 17 Pro Max" -b
xcrun simctl ui "iPhone 17 Pro Max" appearance dark   # Hetzly is dark-first; match the marketing screenshots
```

## 3. Build and install a Debug build

```sh
xcodegen generate
xcodebuild build \
  -project Hetzly.xcodeproj -scheme Hetzly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -derivedDataPath build

xcrun simctl install "iPhone 17 Pro Max" build/Build/Products/Debug-iphonesimulator/Hetzly.app
```

## 4. Fixture-mode launch flags (clean, deterministic data)

`Hetzly/App/UITestSupport.swift` (`#if DEBUG`-only, so it never ships in a
Release/TestFlight/App Store build) reads three launch-environment flags and,
if set, swaps in an in-memory SwiftData store + a canned-fixture
`HTTPTransport` instead of touching Keychain or the real network:

| Flag | Effect |
|---|---|
| `HETZLY_UITEST=1` | One seeded project ("Demo Project"), two fixture servers (`web-01` running, `worker-02` off). |
| `HETZLY_UITEST_MULTI=1` | Two seeded projects ("Production", "Staging"), each with its own two fixture servers (`web-01`/`worker-02` and `api-01`/`cache-02`). **Use this one for the Dashboard hero shot** — it's the multi-project view. |
| `HETZLY_UITEST_EMPTY=1` | No seeded data — onboarding screen. Not needed for the hero set below. |

`simctl launch` doesn't forward your shell's environment to the launched
process — prefix the variable with `SIMCTL_CHILD_` so `simctl` passes it
through:

```sh
xcrun simctl terminate "iPhone 17 Pro Max" com.hetzly.app 2>/dev/null || true
env SIMCTL_CHILD_HETZLY_UITEST_MULTI=1 xcrun simctl launch "iPhone 17 Pro Max" com.hetzly.app
```

The fixture router (`UITestTransport`/`UITestFixtures` in the same file)
answers `pricing`, `servers`, `servers/{id}`, `servers/{id}/metrics`,
`locations`, `images`, `server_types`, `ssh_keys`, `networks`, `firewalls`,
and `POST /servers` — i.e. it reliably covers **Dashboard, Server Detail
(both tabs), and the Create-Server wizard**. It does **not** seed volumes,
load balancers, DNS zones, floating/primary IPs, placement groups, Robot
accounts, Storage Box accounts, or manual cost entries, and it never
attempts a real SSH connection.

For the screens fixture mode can't reach — **Costs, Resources hub (fully
populated), Dedicated/Ordering, and the SSH terminal** — launch normally
(no `HETZLY_UITEST*` flag) against a real or disposable/demo Hetzner Cloud
project and Robot account, seeded with enough resources to look good in a
screenshot (a handful of named servers/volumes/firewalls, at least one
month of cost history if possible, one Robot server, and one reachable test
server — even a $4/mo CX22 — for the terminal shot with an SSH key already
added in Settings). Don't use real production infrastructure names/IPs in
submission screenshots.

## 5. The hero screenshot set (capture in this order)

| # | Screen | How to reach it | Caption (one line) |
|---|---|---|---|
| 1 | **Dashboard — multi-project** | Launch with `HETZLY_UITEST_MULTI=1`; lands here by default | See every project's servers and status at a glance |
| 2 | **Server detail — Control tab** | Tap a running server, "Control" tab (default) | Power, rebuild, rescue, backups, and console — all in one place |
| 3 | **Server detail — Analytics tab** | Same screen, tap "Analytics" | Live CPU, disk, and network graphs, right on your phone |
| 4 | **Create-server wizard** | Dashboard → "+" → walk to a populated step (e.g. server type selection) | Spin up a new server in a few taps |
| 5 | **Costs dashboard** | Costs tab, real/demo account with cost history | Know exactly what you're spending — computed on-device |
| 6 | **Resources hub** | Resources tab, real/demo account | Volumes, networks, firewalls, load balancers, DNS, and more |
| 7 | **Dedicated / Ordering** | Dedicated tab (needs a Robot account configured), or the order-review step under Dedicated → Order | Manage dedicated hardware, or order more |
| 8 | **SSH terminal** | Server detail → Terminal action, connected to a real reachable server | A real terminal, built in — no separate app needed |

Capture each with:

```sh
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/01-dashboard.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/02-server-control.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/03-server-analytics.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/04-create-server.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/05-costs.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/06-resources.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/07-dedicated.png
xcrun simctl io "iPhone 17 Pro Max" screenshot fastlane/screenshots/en-US/08-terminal.png
```

(Numeric prefixes just keep Finder/`ls` ordering matching the table above —
`fastlane deliver` itself doesn't care about filenames, only which folder
they're in.)

`fastlane/screenshots/` is gitignored. Once captured, either run
`fastlane deliver` (picks the folder up automatically) or drag the files
into App Store Connect → App Store → [locale] → iPhone Screenshots manually.

## 6. Optional: repeat for a fallback size

If you decide to also produce dedicated 6.5"/6.7" art rather than relying on
Apple's automatic scaling of the 6.9" set, repeat steps 2–5 with
`-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'` (or
whichever installed simulator matches the target display size) and drop the
output in `fastlane/screenshots/en-US/` alongside the 6.9" set — `deliver`
sorts by detected resolution, not filename.

## 7. Automating this later

`fastlane/Fastfile` has a `screenshots` lane that boots the 6.9" simulator,
builds, installs, and drives the four fixture-reachable screens (Dashboard,
Server Detail × 2 tabs, Create-Server wizard) automatically using the flags
above. It intentionally does **not** attempt Costs, Resources, Dedicated, or
the SSH terminal — those need real account data / a real server and are a
manual step per the table above.
