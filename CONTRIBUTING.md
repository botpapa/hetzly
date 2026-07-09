# Contributing to Hetzly

Thanks for your interest in contributing. Hetzly is a small, opinionated
codebase — please read this before opening a PR.

## Dev setup

Requirements: macOS with Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
# TODO(release): replace botpapa with the real GitHub org/user — see AppLinks.swift
git clone https://github.com/botpapa/hetzly.git
cd hetzly
xcodegen
open Hetzly.xcodeproj
```

The `.xcodeproj` is generated, not committed. Re-run `xcodegen` whenever
`project.yml` changes or you add/remove files (xcodegen globs `Hetzly/` and
picks up new files automatically, but the project needs regenerating for
Xcode to see them).

To iterate on the API layer without opening Xcode:

```sh
swift build --package-path Packages/HetznerKit
swift test  --package-path Packages/HetznerKit
```

## The dependency rule

Hetzly ships with **no third-party dependencies**, with one deliberate,
narrowly-scoped exception: the in-app SSH terminal
(`Hetzly/Features/Terminal/`) uses
[`apple/swift-nio-ssh`](https://github.com/apple/swift-nio-ssh) and
[`migueldeicaza/SwiftTerm`](https://github.com/migueldeicaza/SwiftTerm) —
implementing an SSH client and a terminal emulator from scratch was judged
out of scope, unlike everything else in the app. Everywhere else — the core
app, HetznerKit, the design system, the mascot engine — is Apple frameworks
and the Swift standard library only.

This is deliberate: it keeps the supply chain auditable and the binary lean,
and matches the app's "your credentials never leave this device, through
code you can read end to end" promise. PRs that add a package dependency
outside the Terminal feature will not be merged; if you think a new
exception is warranted (for the Terminal feature or otherwise), open an
issue to discuss it first — do not add a `packages:` entry to `project.yml`
speculatively.

## Swift 6 strict concurrency

The whole project builds in Swift 6 language mode with
`SWIFT_STRICT_CONCURRENCY = complete`. New code must compile cleanly under
strict concurrency — no `@unchecked Sendable` without a comment justifying
why it's safe.

Other house rules (see [CONTRACTS.md](CONTRACTS.md) for the full list):

- No force unwraps (`!`), `try!`, or `fatalError` in app-target code (tests
  may use them).
- No `print` / `os_log` / `Logger` of tokens, `Authorization` headers, or
  credential-bearing response bodies.
- Every SwiftUI view file ends with a `#Preview` that includes
  `.preferredColorScheme(.dark)` — Hetzly is dark-first.
- iOS 26 Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass)`) — no hand-rolled blur approximations.

## Tests

`Packages/HetznerKit` is UI-free and the primary place we expect test
coverage: aim for **≥80%** coverage on request building, response decoding,
pagination, rate limiting, and error mapping. App-target code (SwiftUI
views, DI wiring) is not held to the same bar, but non-trivial logic
(view models, formatters, cost calculations) should still be tested where it
can be pulled out of a view — see `HetzlyTests` for app-target unit tests and
`HetzlyUITests` for end-to-end UI flows.

Run the **full test suite** before opening a PR:

```sh
# Package tests (fast, no simulator needed)
swift test --package-path Packages/HetznerKit

# App-target unit + UI tests (needs a booted/available simulator)
xcodegen
xcodebuild test \
  -project Hetzly.xcodeproj \
  -scheme Hetzly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

This is the same sequence CI runs on every PR and push to `main` (see
`.github/workflows/ci.yml`) — a green local run doesn't guarantee CI passes
(different runner, different simulator availability), but it catches the
vast majority of issues before you push.

## PR checklist

Before opening a PR, please confirm:

- [ ] Every new/changed SwiftUI screen has a dark-mode `#Preview`.
- [ ] No force unwraps, `try!`, or `fatalError` introduced in app-target code.
- [ ] No secret logging — the CI grep guard
      (`! grep -rn --include='*.swift' -E '(print|os_log|Logger).*[Aa]uthorization' Hetzly Packages`)
      passes locally.
- [ ] `swift test --package-path Packages/HetznerKit` passes.
- [ ] `xcodebuild test` passes for the `Hetzly` scheme (`HetzlyTests` + `HetzlyUITests`).
- [ ] `xcodegen` was re-run and the project builds in Xcode 26.
- [ ] No new third-party dependency was added outside `Hetzly/Features/Terminal/`
      (see [The dependency rule](#the-dependency-rule)).

## Reporting security issues

Do not open a public issue for a security vulnerability — see
[SECURITY.md](SECURITY.md).
