# fastlane

This directory holds App Store submission plumbing: the App Store listing
copy (`metadata/en-US/`) and a minimal set of lanes (`Fastfile`) for running
tests and shipping a TestFlight beta.

## What's here

```
fastlane/
├── Appfile                        # app identifier / Apple ID / team ID (placeholders)
├── Fastfile                       # lanes: generate_project, test, beta, screenshots
├── README.md                       # this file
└── metadata/
    ├── primary_category.txt        # DEVELOPER_TOOLS
    ├── secondary_category.txt      # UTILITIES
    └── en-US/
        ├── name.txt                 # "Hetzly" (≤30 chars)
        ├── subtitle.txt              # App Store subtitle (≤30 chars)
        ├── description.txt           # full listing copy (≤4000 chars)
        ├── keywords.txt               # comma-separated, ≤100 chars total
        ├── promotional_text.txt        # ≤170 chars, editable without a new review
        ├── release_notes.txt           # "What's New" copy for this version
        ├── privacy_url.txt              # PLACEHOLDER — see below
        ├── support_url.txt               # PLACEHOLDER — see below
        └── marketing_url.txt              # PLACEHOLDER — see below (optional field)
```

`fastlane deliver` reads `metadata/*.txt` and `metadata/en-US/*.txt` directly
and uploads them as the App Store Connect listing fields (category ids are
top-level/not localized; everything else is per-locale) — no extra config
needed for the metadata itself. See
[`docs/app-store/submission-guide.md`](../docs/app-store/submission-guide.md)
for the full step-by-step submission walkthrough, and
[`docs/app-store/privacy-nutrition-label.md`](../docs/app-store/privacy-nutrition-label.md)
for the exact App Store Connect privacy-questionnaire answers.

## Before you submit: things that need YOUR details

This is a public, open-source repo with no shared Apple Developer account.
Nothing here can build a distributable, signable archive as-is — that's
intentional, not a bug. Before running `fastlane beta`:

1. **Apple Developer Team.** Edit `fastlane/Appfile` (or set
   `FASTLANE_APPLE_ID` / `FASTLANE_TEAM_ID` env vars) with your own Apple ID
   and Team ID.
2. **Code signing.** Hetzly has two bundle IDs that both need a distribution
   provisioning profile: `com.hetzly.app` (the app) and
   `com.hetzly.app.widgets` (the WidgetKit extension, `HetzlyWidgets`).
   `fastlane/Fastfile`'s `beta` lane has a commented-out `match` block —
   uncomment it and point `git_url:` at a private certificates repo you
   control, or configure Xcode automatic signing with your own team instead.
   Neither is wired up by default.
3. **App Store Connect API key** (recommended over an interactive Apple ID
   login for `upload_to_testflight`). Generate one in App Store Connect →
   Users and Access → Integrations → App Store Connect API, download the
   `.p8`, and either pass it via `api_key_path:` in the `beta` lane or set
   `APP_STORE_CONNECT_API_KEY_*` environment variables. **Never commit the
   `.p8` file** — `.gitignore` already excludes `fastlane/*.p8`.
4. **TODO — three URL placeholders.** `metadata/en-US/privacy_url.txt`,
   `support_url.txt`, and `marketing_url.txt` all currently point at real,
   working GitHub URLs (`github.com/botpapa/hetzly/...`) so `deliver` won't
   fail on a broken link, but none of them is a dedicated, purpose-built
   page:
   - `privacy_url.txt` → README security-model anchor. App Store Connect
     **requires** a privacy policy URL; a README section is honest but not
     a proper privacy policy. Replace with a real hosted page before
     submission — see
     [`docs/app-store/privacy-nutrition-label.md`](../docs/app-store/privacy-nutrition-label.md)
     for content you can host as that page (e.g. via GitHub Pages).
   - `support_url.txt` → GitHub Issues. Fine to keep as-is if you're okay
     with support requests as public issues; swap for a real support page
     / email if not.
   - `marketing_url.txt` → GitHub repo root. Optional field; replace with a
     real marketing site if/when one exists, or delete the file to omit it.
5. **Verify `github.com/botpapa/hetzly` is the real repo URL** before relying
   on the three files above, or update them to match wherever this project
   is actually hosted.
6. **Screenshots.** Not included here — see
   [`docs/app-store/screenshots.md`](../docs/app-store/screenshots.md) for
   the exact device sizes, fixture-mode launch flags, hero-screen list, and
   `simctl` commands. Once captured, drop them under
   `fastlane/screenshots/en-US/` (gitignored) for `fastlane deliver` to pick
   up, or upload manually via App Store Connect.
7. **Categories.** `metadata/primary_category.txt` /
   `secondary_category.txt` are set to `DEVELOPER_TOOLS` / `UTILITIES`.
   `deliver`'s category upload can be finicky — treat the App Store Connect
   web UI (App Information → Category) as the source of truth and verify it
   matches after any automated upload.

## Lanes

```sh
cd fastlane  # or run `fastlane <lane>` from the repo root — either works

fastlane generate_project   # xcodegen generate
fastlane test                # HetznerKit swift test + HetzlyTests/HetzlyUITests
fastlane beta                # build + upload to TestFlight (needs signing, see above)
fastlane screenshots          # capture the App Store screenshot set (see docs/app-store/screenshots.md)
```

`test` is safe to run with no Apple Developer account at all — it never
touches App Store Connect. `beta` will fail fast with a clear signing error
until you've done the steps above; that's expected for a fresh clone.
