# App Store Connect submission guide

Step-by-step for taking Hetzly from "code builds" to "in review." Written
for whoever is actually holding the paid Apple Developer account — this repo
has no shared signing identity (see `fastlane/README.md`), so several steps
below need real account access that only that person has.

## 0. Prerequisite: Apple Developer Program membership must be active

`project.yml` has a standing comment (search `Program License Agreement`)
noting that, as of when it was written, the widgets extension's App Groups
capability couldn't be provisioned because **the latest Program License
Agreement was pending acceptance** at developer.apple.com. Nothing below
will work — no signing, no TestFlight, no submission — until:

1. Sign in at [developer.apple.com/account](https://developer.apple.com/account)
   and accept any pending agreement.
2. Confirm the membership is **Individual or Organization, paid, active**
   (not a free/Xcode-only account — those can't submit to the App Store).
3. Once accepted, restore the widget-embed wiring `project.yml` currently
   has commented out (the `# - target: HetzlyWidgets` line and its
   entitlements) — that's app-code, out of scope for this doc, but it's a
   real blocker for shipping widgets and worth flagging to whoever owns
   `project.yml`.

## 1. Create the app record

In [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Hetzly |
| Primary language | English (U.S.) |
| Bundle ID | `com.hetzly.app` — register it first under Certificates, Identifiers & Profiles → Identifiers if it isn't already; the WidgetKit extension's `com.hetzly.app.widgets` needs its own App ID too (App Group capability, App Groups container e.g. `group.com.hetzly.app`) |
| SKU | any unique internal string, e.g. `hetzly-ios` |
| User Access | Full Access (or restrict per your team) |

## 2. Fill in metadata from `fastlane/metadata/`

Every text field below has a corresponding file already written and
character-count-verified — copy/paste, or run `fastlane deliver` to push
them automatically (see §5).

| App Store Connect field | Source file |
|---|---|
| Name | `fastlane/metadata/en-US/name.txt` |
| Subtitle | `fastlane/metadata/en-US/subtitle.txt` |
| Promotional text | `fastlane/metadata/en-US/promotional_text.txt` |
| Description | `fastlane/metadata/en-US/description.txt` |
| Keywords | `fastlane/metadata/en-US/keywords.txt` |
| What's New in This Version | `fastlane/metadata/en-US/release_notes.txt` |
| Support URL | `fastlane/metadata/en-US/support_url.txt` **— TODO, see below** |
| Marketing URL (optional) | `fastlane/metadata/en-US/marketing_url.txt` **— TODO, see below** |
| Privacy Policy URL | `fastlane/metadata/en-US/privacy_url.txt` **— TODO, see below** |
| Primary category | `fastlane/metadata/primary_category.txt` (Developer Tools) |
| Secondary category | `fastlane/metadata/secondary_category.txt` (Utilities) |
| App Privacy questionnaire | see [`privacy-nutrition-label.md`](privacy-nutrition-label.md) — answer "Data Not Collected" |
| Screenshots | see [`screenshots.md`](screenshots.md) |

**TODO before you submit:** `privacy_url.txt`, `support_url.txt`, and
`marketing_url.txt` currently point at real GitHub URLs so nothing is
broken, but only `support_url.txt` (GitHub Issues) is a genuinely
appropriate destination as-is. `privacy_url.txt` points at a README section,
not a dedicated privacy policy — Apple requires an actual privacy policy
page; host the content of `privacy-nutrition-label.md` (or an equivalent
short policy) somewhere real (GitHub Pages is free and sufficient) and
update the file before submitting. See `fastlane/README.md` item 4–5 for the
full checklist.

## 3. Archive and upload a build

Two supported paths — pick whichever the person doing this is more
comfortable with. Both need the same prerequisite: **your own paid Apple
Developer Team ID wired into signing** (see `fastlane/README.md` — nothing
here has that configured by default, on purpose, since this is a public
repo).

### Path A — Xcode Organizer (manual, good for a one-off / first submission)

```sh
xcodegen generate
open Hetzly.xcodeproj
```

In Xcode: select the `Hetzly` scheme → Any iOS Device (or a connected
device) → **Product → Archive**. Once archived, Organizer opens
automatically — **Distribute App → App Store Connect → Upload**, choosing
your Team ID for automatic signing (or your configured manual profiles).
Repeat for the `HetzlyWidgets` embed once §0's App Groups capability is
provisioned.

### Path B — fastlane lanes (repeatable, good for CI or repeat betas)

```sh
cd fastlane   # or run from repo root — fastlane finds this directory either way

fastlane beta      # archive + upload to TestFlight
fastlane release   # push metadata/screenshots (and optionally submit for review) via `deliver`
```

- `beta` (`fastlane/Fastfile`) builds an app-store-export archive and uploads
  it to TestFlight via `upload_to_testflight`. It requires signing to be
  configured first — see `fastlane/README.md` for the exact steps
  (Appfile team ID, and either Xcode automatic signing or `match`).
- `release` runs `deliver` against everything in `fastlane/metadata/` (and
  `fastlane/screenshots/en-US/` once you've captured them per
  `screenshots.md`) to push App Store listing content. By default it does
  **not** submit for review (`submit_for_review: false`) — flip that only
  once you've verified the listing in App Store Connect's web UI and are
  ready to actually submit. It does not re-upload a binary; promote the
  TestFlight build you already validated instead (see §4).
- Both need an **App Store Connect API key** (recommended) or an
  interactive Apple ID session — see `fastlane/README.md` item 3.

## 4. TestFlight first

Don't submit for App Review straight from an upload. After `fastlane beta`
(or Organizer) finishes processing (a few minutes to ~1 hour):

1. App Store Connect → your app → **TestFlight** → confirm the build shows
   "Ready to Submit" (compliance/export questions answered — see
   `privacy-nutrition-label.md`'s Export Compliance section; if you're doing
   this per-build rather than via the `project.yml` Info.plist flag, answer
   the same way).
2. Add yourself (and anyone else) as an internal tester, install via the
   TestFlight app, and actually exercise the app against a real Hetzner
   account — Cloud dashboard, a server action, the create-server wizard,
   Costs, and the SSH terminal at minimum. This is your last chance to catch
   a signing/entitlement/App-Groups issue (see §0) before a reviewer does.
3. Once satisfied, go to **App Store** tab → your version → **Build** →
   select the TestFlight build you just validated.

## 5. Submit for App Review

App Store Connect → your app → **App Store** tab → the version you're
submitting → fill in (if not already done via `deliver`):

- **App Review Information** — see the reviewer-access notes below. This is
  the single most important field for this specific app to get right.
- **Version Release** — "Manually release this version" is the safer choice
  for a first submission (lets you pick the exact moment it goes live after
  approval).
- Confirm **Age Rating**, **Content Rights**, and the **Export Compliance**
  answer (§Export Compliance in `privacy-nutrition-label.md`) are filled in.
- **Add for Review**, then **Submit to App Review**.

### App Review notes — how a reviewer tests without a Hetzner account

Hetzly is *useless* without a Hetzner Cloud API token and/or Robot
credentials — there's no demo mode, no guest account, nothing server-side to
fall back on (no backend exists). A reviewer with zero context will get
stuck at onboarding. Two options, in order of preference:

**Option A — recommended: provide a real, scoped, read-only demo token.**
Before submitting:
1. Create a throwaway Hetzner Cloud project specifically for App Review
   (a couple of cheap/free-tier-eligible servers is enough to make the
   Dashboard, Server Detail, and Resources tabs non-empty).
2. Generate a **read-only** API token for that project (Hetzner Cloud
   Console → Security → API Tokens → Permissions: Read Only). Read-only
   means a reviewer tapping around can't accidentally power off, delete, or
   rebuild anything, and can't rack up charges.
3. In the **App Review Information → Notes** field, write something like:

   > Hetzly is a client for Hetzner Cloud/Robot infrastructure the user
   > already owns — there is no demo/guest mode and no backend of ours to
   > provide test data from. We've created a disposable Hetzner Cloud
   > project with a **read-only** API token for review purposes:
   >
   > Token: `<paste the read-only token here>`
   >
   > On first launch, tap "Add Project," paste this token, and you'll see a
   > small live project with a couple of servers. Because the token is
   > read-only, destructive actions (power off, rebuild, delete, etc.) will
   > correctly fail with a permission error from Hetzner's API — that's
   > expected, not a bug. The in-app SSH terminal needs a server reachable
   > from the internet with a password/key you'd have to supply separately;
   > we're happy to provide one on request if you'd like to test that
   > screen specifically.
   >
   > Not affiliated with Hetzner Online GmbH — Hetzly is an independent,
   > open-source client using Hetzner's published APIs.

   Rotate/revoke that token after the review concludes (or leave a small
   trickle of budget on the project — a read-only token can't spend
   anything on its own, only via what's already provisioned).
4. If you'd rather not expose even a read-only token to a reviewer
   indefinitely, note in the same message that you're available to rotate
   it on request and include a contact email.

**Option B — fallback: explain the fixture limitation.** If you genuinely
cannot provide credentials (e.g. no budget for a demo project), explain in
the Notes field that the app requires the user's own Hetzner account, link
to the public source (`Hetzly/App/UITestSupport.swift` shows exactly what
data a fixture-seeded build renders), and offer a short screen-recording
walkthrough as an attachment. This is materially weaker — reviewers are far
more likely to bounce an app they can't operate at all than one with a
working read-only demo — so treat Option A as the default and Option B as a
last resort.

Either way, **do not** ship a build with `HETZLY_UITEST`/`_MULTI`/`_EMPTY`
fixture mode reachable in Release — it's compiled out via `#if DEBUG` and
gated behind an explicit launch-environment flag specifically so this isn't
a risk, but it's worth a sanity check that nothing regressed that guarantee
before submitting.
