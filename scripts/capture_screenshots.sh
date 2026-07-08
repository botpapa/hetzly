#!/usr/bin/env bash
#
# capture_screenshots.sh — quick dev-loop screenshot capture for the
# repo's docs/screenshots/*.png (embedded in README.md), distinct from the
# fastlane/screenshots/ App Store submission pipeline documented in
# fastlane/README.md and the README's "## Screenshots" section.
#
# What this captures automatically (no manual navigation required):
#   - docs/screenshots/dashboard.png        — multi-project Dashboard, via
#     the HETZLY_UITEST_MULTI fixture seed (two projects, four fixture
#     servers, no network/Keychain involved — see Hetzly/App/UITestSupport.swift).
#   - docs/screenshots/single-project.png   — single-project Dashboard, via
#     the HETZLY_UITEST fixture seed.
#
# Both land on the Dashboard tab because that's where RootView/MainTabView
# opens by default on a fresh launch — no scripted navigation needed.
#
# What this does NOT capture (out of scope for this script):
#   - Server detail, Costs, Resources, Dedicated, Settings, or any other
#     screen reached by tapping into the app. Getting there deterministically
#     needs either manual navigation (launch via this script's build, then
#     drive the simulator by hand and re-run just the `simctl io screenshot`
#     step) or a dedicated XCUITest that navigates and calls
#     `XCUIScreen.main.screenshot()` — neither is wired up here.
#   - Light-mode screenshots: `xcrun simctl ui <device> appearance light`
#     changes the *simulator's* system appearance, but Hetzly's own
#     `AppSettings.appearance` defaults to "dark" regardless of the system
#     setting (Settings → Appearance must be set to "System" inside the app
#     first, which — again — needs manual navigation or a scripted UI test).
#     Light-mode rendering is instead verified by HetzlyTests/LightModeRenderTests.swift
#     and the "Appearance: Light" #Previews added across key screens.
#
# Usage:
#   ./scripts/capture_screenshots.sh
#
# Requires: Xcode 26 + the "iPhone 17 Pro" (iOS 26.5) simulator runtime,
# already true of any machine following this repo's "## Building" section.

set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_NAME="iPhone 17 Pro"
DEVICE_OS="26.5"
BUNDLE_ID="com.hetzly.app"
OUTPUT_DIR="docs/screenshots"
DERIVED_DATA="build"

echo "==> Resolving simulator UDID for '${DEVICE_NAME}' (iOS ${DEVICE_OS})"
DEVICE_UDID=$(
  xcrun simctl list devices available -j |
    /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
target_runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + "'"${DEVICE_OS}"'".replace(".", "-")
for runtime, devices in data["devices"].items():
    if runtime != target_runtime:
        continue
    for d in devices:
        if d["name"] == "'"${DEVICE_NAME}"'":
            print(d["udid"])
            sys.exit(0)
sys.exit(1)
'
)

if [ -z "${DEVICE_UDID}" ]; then
  echo "error: could not find '${DEVICE_NAME}' on iOS ${DEVICE_OS}. Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "    -> ${DEVICE_UDID}"

echo "==> Booting simulator (no-op if already booted)"
xcrun simctl boot "${DEVICE_UDID}" 2>/dev/null || true
xcrun simctl bootstatus "${DEVICE_UDID}" -b

echo "==> xcodegen"
xcodegen generate

echo "==> Building Hetzly (Debug, default signing) for the simulator"
xcodebuild build \
  -project Hetzly.xcodeproj \
  -scheme Hetzly \
  -configuration Debug \
  -destination "id=${DEVICE_UDID}" \
  -derivedDataPath "${DERIVED_DATA}" \
  | xcbeautify 2>/dev/null || xcodebuild build \
  -project Hetzly.xcodeproj \
  -scheme Hetzly \
  -configuration Debug \
  -destination "id=${DEVICE_UDID}" \
  -derivedDataPath "${DERIVED_DATA}"

APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/Hetzly.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "error: expected build output at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Installing"
xcrun simctl install "${DEVICE_UDID}" "${APP_PATH}"

mkdir -p "${OUTPUT_DIR}"

capture() {
  local flag_name="$1"
  local output_file="$2"
  local label="$3"

  echo "==> Launching with ${flag_name}=1 for ${label}"
  xcrun simctl terminate "${DEVICE_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  env "SIMCTL_CHILD_${flag_name}=1" xcrun simctl launch "${DEVICE_UDID}" "${BUNDLE_ID}"

  # Give the fixture-seeded launch time to build its in-memory store,
  # construct AppContainer, and render the Dashboard's first frame.
  sleep 4

  echo "==> Screenshot -> ${OUTPUT_DIR}/${output_file}"
  xcrun simctl io "${DEVICE_UDID}" screenshot "${OUTPUT_DIR}/${output_file}"
}

capture "HETZLY_UITEST_MULTI" "dashboard.png" "multi-project Dashboard"
capture "HETZLY_UITEST" "single-project.png" "single-project Dashboard"

xcrun simctl terminate "${DEVICE_UDID}" "${BUNDLE_ID}" 2>/dev/null || true

echo "==> Done. Captured:"
ls -la "${OUTPUT_DIR}"/*.png
