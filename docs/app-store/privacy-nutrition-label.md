# App privacy nutrition label — exact App Store Connect answers

This is the walkthrough for App Store Connect's **App Privacy** questionnaire
(App Store Connect → your app → App Privacy) and the **Export Compliance**
question asked at build-upload time. Answer it exactly as below; the
justification for each answer is spelled out so whoever submits can defend
it if App Review asks a follow-up question.

## Bottom line

**Data collection: "Data Not Collected."** Select this at the top of the App
Privacy page. You will not need to fill in any data-type/purpose grid at
all — "Data Not Collected" is a single declaration, not a category you leave
empty.

## Why this is the correct answer, not just the easy one

Apple's own definition of "collect" is: *transmitting data off the device in
a way that's accessible beyond the current session*, e.g. to a server, an
SDK, or a third party. Walk through everything Hetzly does:

1. **No backend of its own.** There is no Hetzly server anywhere. The app
   talks directly to Hetzner's own APIs
   (`api.hetzner.cloud`, `api.hetzner.com`, `robot-ws.your-server.de`) using
   the user's own API token / Robot credentials, which the user typed in
   themselves. Hetzner is a service the user already has a direct
   relationship with and explicitly configured — this is the user directing
   the app to talk to their own account, not Hetzly collecting anything.
2. **No analytics SDK.** Grep the dependency graph: `Packages/HetznerKit`
   and the app target have zero third-party dependencies outside the
   Terminal feature's `NIOSSH`/`SwiftTerm` (an SSH protocol implementation
   and a terminal emulator — see project.yml's `packages:` comment). Neither
   of those talks to anything but the user's own configured server. There is
   no Firebase, no Sentry/Crashlytics, no ad SDK, no A/B testing SDK — none
   of the usual vectors that would force a "data linked to you" or "data
   used to track you" answer.
3. **No crash reporter.** Crashes are whatever Xcode Organizer / TestFlight
   collects automatically at the OS level (Apple's own pipeline, covered by
   Apple's own privacy disclosures, not Hetzly's).
4. **SSH terminal is device → the user's own server.** The built-in terminal
   (`Hetzly/Features/Terminal/`) opens a direct SSH connection from the
   user's device to a server *the user chose and owns/controls*, using
   credentials the user supplied. Nothing about that session is visible to
   Hetzly or any third party — it's exactly as private as any other SSH
   client (Terminal.app, PuTTY, etc.), which is why other SSH client apps on
   the App Store also carry a "Data Not Collected" label.
5. **Tokens/credentials live in Keychain only.** Cloud API tokens and Robot
   credentials are stored via `KeychainStore`
   (`Hetzly/Security/KeychainStore.swift`) with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never in `UserDefaults`,
   never synced to iCloud, never logged (CI enforces a grep guard against
   logging `Authorization` headers or credential bodies — see
   `SECURITY.md`).
6. **No background telemetry.** There's no periodic phone-home. Every
   network call is either user-initiated (pull-to-refresh, opening a screen,
   an explicit action) or a capped, on-device widget snapshot that itself
   only talks to Hetzner's API, not to Hetzly.

None of this data ever reaches a Hetzly-controlled or third-party server, so
there is nothing to disclose under any of Apple's categories (Contact Info,
Health & Fitness, Financial Info, Location, Browsing History, Identifiers,
Usage Data, Diagnostics, etc.) — hence "Data Not Collected."

## If App Review pushes back / asks for clarification

Reviewers occasionally flag apps that clearly make network requests (visible
in a packet capture) but declare "Data Not Collected," assuming a mismatch.
If asked, the accurate response is: *"Hetzly makes network requests only to
Hetzner's own API endpoints and to servers the user explicitly configures
(their own Hetzner infrastructure, addressed by the user's own API token),
and via direct SSH to servers the user owns. Hetzly has no backend of its
own and no analytics/crash/ad SDK of any kind. No data is collected by the
developer or shared with any third party."* Point to the public source
(`Hetzly/Security/`, `Packages/HetznerKit/`) if asked to substantiate this —
the whole point of the zero-dependency rule (`CONTRIBUTING.md`) is that this
claim is independently verifiable, not just asserted.

## Export compliance (`ITSAppUsesNonExemptEncryption`)

`project.yml` currently sets `ITSAppUsesNonExemptEncryption: false`, which
answers "No" to App Store Connect's "Does your app use encryption?" /
qualifies it for the standard exemption without needing an uploaded export
document per build.

**Rationale:** Hetzly uses only standard, publicly documented, non-proprietary
cryptography:
- **HTTPS/TLS** to Hetzner's APIs, via `URLSession` — Apple's own networking
  stack, using the OS's built-in TLS implementation.
- **SSH**, via `swift-nio-ssh` (`NIOSSH`), implementing the standard SSH
  protocol (RFC 4251–4254) with standard algorithms — not a proprietary or
  self-designed cipher.

Apps that incorporate encryption *only* via such standard, publicly
available implementations typically qualify for the Category 5 Part 2
"standard/mass-market encryption" exemption under the U.S. EAR, which is
what `ITSAppUsesNonExemptEncryption: false` represents to Apple.

**One thing to re-verify before this specific submission:** earlier builds
of this rationale likely predate the SSH terminal feature. HTTPS-only apps
almost always sail through as exempt; a full interactive SSH *client* is a
more clearly "encryption is the point" feature than "app happens to use
HTTPS to call an API," so:
- When you get to the **Encryption** question in App Store Connect during
  build submission, answer "Yes, uses encryption" → "Uses only encryption
  that is exempt from export documentation requirements per Category 5,
  Part 2" (standard/non-proprietary algorithms only, no custom crypto).
  This should keep `false` accurate.
- If this is the **first submission of any Hetzly build that includes the
  SSH terminal**, budget a few minutes to re-read Apple's current
  [export compliance guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/export-compliance-information/)
  and confirm the exemption still applies to your legal understanding —
  this document is not legal advice, and export-control rules are the one
  area here worth a second, informed look rather than copy-pasting.
- A one-time self-classification report to BIS/NSA is sometimes still
  required for exempt mass-market encryption products even when Apple's
  Info.plist flag says "exempt from *documentation* requirements" — that's
  a separate, outside-of-Xcode compliance step, not something this repo can
  automate. If in doubt, consult counsel; this is genuinely the one place
  in this app where "read the source, it's fine" isn't a substitute for
  that.

## Quick reference for the App Store Connect UI

| Question | Answer |
|---|---|
| Does your app collect data? | **No — Data Not Collected** |
| Does your app use encryption? | **Yes** |
| Does it qualify for an export compliance exemption? | **Yes** — standard/non-proprietary algorithms only (TLS via `URLSession`, SSH via `swift-nio-ssh`), no custom cryptography |
| `ITSAppUsesNonExemptEncryption` in Info.plist | `false` (already set in `project.yml`) |
