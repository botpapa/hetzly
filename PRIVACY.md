# Privacy Policy

**Effective date:** 2026-07-09

Hetzly is designed so that this policy can be short and absolute.

## Hetzly does not collect any data.

- **No backend.** Hetzly has no server of its own. Every network request the app makes goes directly from your device to Hetzner's official API endpoints (`api.hetzner.cloud`, `api.hetzner.com`, `robot-ws.your-server.de`), or, for the in-app SSH terminal, directly from your device to the server you choose to connect to. Nothing is routed through, logged by, or stored on any infrastructure operated by the app's developer.
- **No analytics, no tracking, no advertising, no crash-reporting SDKs.** The app contains no third-party analytics or telemetry of any kind.
- **No account.** You never create an account with us. You authenticate directly with Hetzner using your own API tokens.

## What is stored, and where

- **Your Hetzner API tokens and Robot / Storage Box credentials** are stored only in the device's **Keychain**, marked *this device only* and non-synchronizable. They are never written to logs, URLs, iCloud, analytics, or ordinary app storage, and never transmitted anywhere except to Hetzner in the `Authorization` header of your own API requests.
- **Non-secret cached data** (e.g. a snapshot of your server list for fast cold launches, your manually-entered per-server prices) is stored locally on the device only. It is not secret and never leaves the device.
- **SSH host-key fingerprints** you have trusted are stored locally (fingerprints only, never key material) to detect host-key changes.

All of this data stays on your device and is removed when you delete the app or the relevant account within it.

## Your data with Hetzner

Your use of the Hetzner APIs and your Hetzner account are governed by [Hetzner's own privacy policy](https://www.hetzner.com/legal/privacy-policy) and terms. Hetzly is an independent third-party client and is not affiliated with Hetzner Online GmbH.

## Contact

Questions about this policy: open an issue at https://github.com/botpapa/hetzly.
