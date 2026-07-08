# fastlane

This directory holds App Store submission plumbing: the App Store listing
copy (`metadata/en-US/`) and a minimal set of lanes (`Fastfile`) for running
tests and shipping a TestFlight beta.

## What's here

```
fastlane/
├── Appfile                  # app identifier / Apple ID / team ID (placeholders)
├── Fastfile                 # lanes: generate_project, test, beta
├── README.md                 # this file
└── metadata/en-US/
    ├── name.txt              # "Hetzly"
    ├── subtitle.txt          # App Store subtitle (30-char limit)
    ├── description.txt       # full listing copy
    ├── keywords.txt          # comma-separated, 100-char limit total
    ├── privacy_url.txt       # PLACEHOLDER — see below
    └── release_notes.txt     # "What's New" copy for this version
```

`fastlane deliver` reads `metadata/en-US/*.txt` directly and uploads them as
the App Store Connect listing fields for the `en-US` locale — no extra
config needed for the metadata itself.

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
4. **`privacy_url.txt` is a placeholder.** It currently points at this
   repo's README security section, which is honest about what the app does
   but isn't a dedicated privacy-policy page. App Store Connect requires a
   privacy policy URL — replace this with a real hosted page (a GitHub
   Pages page rendering the same content works fine) before submission.
5. **Screenshots.** Not included here — see the "Screenshots" section in the
   top-level [README.md](../README.md#screenshots) for the exact `simctl`
   commands to generate them. Once captured, drop them under
   `fastlane/screenshots/en-US/` (gitignored) for `fastlane deliver` to pick
   up, or upload manually via App Store Connect.

## Lanes

```sh
cd fastlane  # or run `fastlane <lane>` from the repo root — either works

fastlane generate_project   # xcodegen generate
fastlane test                # HetznerKit swift test + HetzlyTests/HetzlyUITests
fastlane beta                # build + upload to TestFlight (needs signing, see above)
```

`test` is safe to run with no Apple Developer account at all — it never
touches App Store Connect. `beta` will fail fast with a clear signing error
until you've done the steps above; that's expected for a fresh clone.
