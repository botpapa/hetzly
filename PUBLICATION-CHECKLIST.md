# Publication Checklist

A precise pre-publish gate for making this repository public on GitHub. Work through this in
order — the first item is a hard blocker; everything else should be done before or during the same
pass, but nothing below matters if the mascot-license issue isn't resolved first.

## 0. BLOCKER — Mascot asset licensing (do this first)

See [ASSETS-LICENSE.md](ASSETS-LICENSE.md) for the full explanation. Short version: the Hetzi mascot
sprite data (`Hetzly/Mascot/MascotFrameData+*.swift`) and, currently, **all four**
`Hetzly/Resources/Assets.xcassets/AppIcon*.appiconset/icon-1024.png` files are converted/rasterized
from Elthen's "2D Pixel Art Red Panda Sprites" pack, which permits use but **not redistribution**.
Publishing this repository publicly as-is redistributes those derived assets, which the license does
not allow.

- [ ] **Decision needed from the repo owner** — pick one:
  - [ ] **Option A: Obtain permission from Elthen** to redistribute the converted sprite data as
        part of an open-source repo. Keep written proof of that permission somewhere durable
        (linked from `ASSETS-LICENSE.md`).
  - [ ] **Option B: Swap to the CC0 fallback mascot.**
        ```sh
        python3 scripts/mascot-fallback/states.py
        # follow scripts/mascot-fallback/README.md to regenerate MascotFrameData+*.swift
        swift scripts/generate_icons.swift
        ```
        Then remove or repoint the "Mascot sprites by Elthen" credit in
        `Hetzly/Features/Settings/SettingsView.swift` (`aboutSection`) since it would no longer be
        accurate, and update `ASSETS-LICENSE.md` to describe the new source instead.
- [ ] Confirm **both** locations are addressed, not just one:
  - [ ] `Hetzly/Mascot/MascotFrameData+*.swift` (Swift source)
  - [ ] `Hetzly/Resources/Assets.xcassets/AppIcon*.appiconset/icon-1024.png` (baked PNGs — check
        with `cmp` that they're no longer byte-identical to Elthen-derived output, or that they've
        been regenerated from the new `app-icon.png` logo / the CC0 fallback)
- [ ] If keeping Elthen's sprites (Option A), verify the credit link in Settings → About still
      points somewhere correct (`AppLinks.mascotCreditURL` in `Hetzly/App/AppLinks.swift`).

**Do not proceed past this section until it's checked off.** Everything below is necessary but not
sufficient — this one is the actual legal blocker.

## 1. Replace the GitHub URL placeholder

`PLACEHOLDER-OWNER` is used consistently across the repo so it's a single find-and-replace once the
real GitHub org/user is known:

```sh
grep -rn "PLACEHOLDER-OWNER" .
```

At minimum this currently appears in:

- [ ] `Hetzly/App/AppLinks.swift` — `githubURL` and `privacyPolicyURL` (the single source of truth
      the app itself uses; update this file first, then everything below is just docs)
- [ ] `SECURITY.md` — the GitHub Security Advisories link
- [ ] `CONTRIBUTING.md` — the `git clone` example
- [ ] Any GitHub repo settings that reference the URL externally (App Store "Support URL" if it
      points at the repo, etc.)

After updating `AppLinks.swift`, rebuild and confirm Settings → About → "Star Hetzly on GitHub"
opens the real URL.

## 2. Add a hosted privacy-policy URL

`AppLinks.privacyPolicyURL` currently falls back to pointing at `SECURITY.md` in-repo, which is
serviceable but not a dedicated privacy policy page. App Store submission requires a reachable
privacy-policy URL.

- [ ] Decide where the privacy policy will be hosted (GitHub Pages off this repo, a standalone page,
      etc.) — Hetzly collects no data, so the policy itself can be short, but it needs a stable URL.
- [ ] Update `AppLinks.privacyPolicyURL` in `Hetzly/App/AppLinks.swift`.
- [ ] Update the App Store Connect listing's Privacy Policy URL field to match.

## 3. Confirm no secrets or tokens are committed anywhere in history

A clean working tree isn't enough — a secret committed and later removed is still in git history.

```sh
# Look for obvious token/secret patterns across the full history, not just HEAD
git log -p | grep -iE 'api[_-]?token|bearer |authorization:|secret|password' | less

# Fastlane / signing material specifically (these should never have been committed —
# .gitignore excludes them going forward, but check history predates that)
git log --all --full-history -- '*.p8' '*.p12' '*.mobileprovision' 'fastlane/.env*'

# Hetzner API tokens are typically long hex/base64-looking strings — spot-check anything
# that looks like a credential value rather than a variable name
git log -p -- Hetzly Packages HetzlyTests HetzlyUITests | grep -iE '"[A-Za-z0-9_-]{32,}"'
```

- [ ] Run the above and confirm no hits, or that every hit is a false positive (test fixture,
      obviously-fake placeholder value, etc.) — spot check, don't just eyeball the pattern match.
- [ ] If anything real turns up, it needs history rewriting (`git filter-repo` or similar) **and**
      the leaked credential needs to be revoked/rotated on the Hetzner side — a history rewrite
      alone does not un-leak an already-exposed token.

## 4. Confirm LICENSE year/owner

- [ ] `LICENSE` currently reads `Copyright (c) 2026 Hetzly contributors` — confirm this is the
      intended copyright holder (an individual name, an org, or "Hetzly contributors" as a
      collective) before publishing. If it should be a specific legal name instead, update it now —
      changing copyright attribution after the repo has external contributors is messier.

## 5. Decide whether to squash/clean history before the first public push

The current history includes milestone-tagged development commits (`M1`, `M2`, `M3`, `M4`, the
post-M4 feature wave, etc.) authored during active development. This is optional, not a blocker:

- [ ] Decide: keep full history as-is (useful narrative of how the app was built, matches
      `CONTRACTS.md`'s description of parallel workers), or squash to a smaller number of clean
      commits before the first public push. Either is defensible; just make the call deliberately
      rather than by default, since it's much harder to clean up after external forks/clones exist.

## 6. Repo metadata

- [ ] Set the GitHub repo **description** (short, matches the README's one-line summary).
- [ ] Add repo **topics** — suggested: `ios`, `swiftui`, `hetzner`, `hetzner-cloud`, `swift`,
      `ios26`, `open-source`.
- [ ] Set the repo **Support URL** / **website** field if applicable.
- [ ] Confirm the About section's "not affiliated with Hetzner" disclaimer is visible somewhere
      GitHub surfaces prominently (README top — already done) since this is a trademark-adjacent
      concern, not just a nicety.

## 7. Verify the CI badge

- [ ] `.github/workflows/ci.yml` exists and runs on `pull_request` and `push` to `main` — confirmed
      present as of this writing.
- [ ] Once the real GitHub owner/repo is known (see §1), add a CI status badge to the top of
      `README.md`:
      ```md
      [](https://github.com/PLACEHOLDER-OWNER/hetzly/actions/workflows/ci.yml)
      ```
      (replace `PLACEHOLDER-OWNER` at the same time as everything else in §1).
- [ ] Push once, confirm the workflow actually runs and goes green on the `macos-26` runner image
      referenced in `ci.yml` — the workflow has a comment noting `macos-26` may need to fall back to
      `macos-latest` + an explicit Xcode-select step if that image isn't available on the target
      GitHub plan/org yet.

## 8. Final sanity pass

- [ ] `xcodegen && xcodebuild build -project Hetzly.xcodeproj -scheme Hetzly -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO` succeeds from a clean clone.
- [ ] `swift test --package-path Packages/HetznerKit` passes.
- [ ] `xcodebuild test` (`HetzlyTests` + `HetzlyUITests`) passes.
- [ ] Screenshots: replace the placeholder HTML comments at the top of `README.md` with real
      captures (see README's [Screenshots](README.md#screenshots) section for the exact commands).
