# Hetzly — Pre-Publish Test Plan

Manual QA to run on a real device with **real tokens** before submitting to the App Store.
Everything below the fixtures has only been tested against canned data, so this is where real
bugs will surface. Work top to bottom; flag anything that doesn't match "Expect".

## ⚠️ Money & danger warnings

- **Creating a server costs money** (billed hourly). Use the cheapest type (CX22 ≈ €0.006/hr) and
  **delete it right after** — the whole test costs a few cents.
- **Ordering a Robot dedicated server is a real, binding purchase** with a setup fee. Walk the flow,
  but do **not** pass the final "arm + Face ID" gate unless you actually want the machine.
- **Delete / rebuild / rescale** are destructive. Only run them on the throwaway test server.

## Setup (do this first)

- [ ] In Hetzner Console, make a **throwaway project** for testing.
- [ ] Create a **Read & Write** token and a separate **Read-only** token in it.
- [ ] Have an **SSH public key** ready (or let Hetzly generate one).
- [ ] (Optional) Robot webservice user + a Storage Box, if you use those.

---

## A. Onboarding & projects

- [ ] Fresh launch with no projects → onboarding appears. Add the **Read & Write** project, leaving
      the name blank. **Expect:** validates, saves, and the name is derived from your server names
      (or "Project 1" if empty).
- [ ] Add a **second** project (your real one) via the Dashboard "＋ → Add Project".
- [ ] Settings → Accounts → rename a project, reorder them (Edit), and confirm both persist after
      relaunch.
- [ ] Add the **Read-only** token as a third project. Keep it for section K.

## B. Dashboard

- [ ] All projects' servers render under their sections, correct status dots, type chip, location
      flag, and a CPU sparkline.
- [ ] Burn card shows a **plausible monthly total** (see section H about grandfathered prices).
- [ ] Filter chips: tap a project → only its servers show; tap "All" → everything returns.
- [ ] **Search**: type part of a server name → results across all projects; clear → normal view.
- [ ] Pull to refresh works; the running mascot appears briefly.
- [ ] Long-press a server row → context menu: **Copy IPv4**, power actions, View Details. Copy an IP
      and paste it somewhere to confirm.

## C. Server detail — read side

- [ ] Tap a server → detail opens with the **Control / Analytics** segmented control.
- [ ] Hero card: status, **IPv4 and IPv6 both tap-to-copy** (paste both to confirm), type/cores/RAM/
      disk, datacenter, uptime.
- [ ] **Price row** shows a monthly figure. **Traffic row** shows out/in vs included.
- [ ] **Analytics tab**: CPU, network (In+Out), disk (Read+Write) charts render with real data.
      Press-and-hold then drag → scrub tooltip shows every series' value + time. A plain swipe on a
      chart **scrolls the page** (doesn't get stuck).

## D. Create-server wizard (spends a few cents)

- [ ] Dashboard "＋ → Create Server" → pick the R&W project.
- [ ] Step through Location → Image → Type (**pick CX22**) → Config. Live price updates in the footer.
- [ ] If you have no SSH key on the project, use the in-wizard **Add SSH Key** button.
- [ ] Config step shows a **summary** (location/image/type) and the CTA reads "Create Server · €…/mo".
- [ ] Create it. **Expect:** live progress, then success; if no SSH key was chosen, a **root password**
      is shown in a card. Copy it.
- [ ] The new server appears on the Dashboard. **Keep it — it's your throwaway for E and F.**

## E. Power & destructive actions (on the throwaway server)

- [ ] **Reboot** → confirm → progress card → completes; server returns to running.
- [ ] **Shut down** (ACPI) → server goes to off; **Power on** → back to running.
- [ ] **Reset root password** → new password shown → confirm it's saved under **Credentials** on the
      Control tab (Face-ID reveal).
- [ ] **Enable backups** (mentions +20%) then disable. **Create a snapshot** → appears in the list →
      delete it.
- [ ] **Rescue mode** → enable (pick your SSH key or password) → one-time password shown → disable.
- [ ] **Rescale** → pick a bigger type → the chained shutdown → resize → power-on runs step by step.
      (Then rescale back down if you like — note disk can't shrink.)
- [ ] **Rebuild** from an image → destructive confirm → completes.
- [ ] **Protection**: toggle delete protection on → the Delete row is locked/explained → toggle off.
- [ ] **Delete** the throwaway server → type-the-name confirm + Face ID → it disappears. (Do this
      **after** section F.)

## F. SSH terminal (needs a reachable server + valid credential)

> This is the least-tested feature — SSH was never run against a real server before you.

- [ ] On the throwaway server (or any server with your key installed), tap **Terminal**.
- [ ] **Expect:** connects and shows a live shell prompt; type `ls`, `uptime` — output appears.
- [ ] Resize / rotate → terminal reflows. Close → disconnects.
- [ ] **If it fails:** it must show a clear message within ~25s (not spin forever). Note which:
      "authentication failed" (key not on server / password login disabled — normal for Hetzner) vs
      "unreachable" (firewall/port 22). Tell me the exact message.

## G. Resources CRUD (use the throwaway project)

- [ ] Resources tab → pick the project. Each category loads.
- [ ] **Volumes**: create a small volume → attach to the throwaway server → detach → delete.
- [ ] **Firewalls**: create one, add an inbound rule (SSH 22 from your IP via the CIDR chips) → apply
      to a server → remove → delete.
- [ ] **SSH Keys**: **generate on device** → reveal & save the private key → verify it's in the list →
      delete (and confirm the private-key export is Face-ID gated).
- [ ] **Networks / Primary IPs / Floating IPs / DNS / Load Balancers / Certificates / Placement
      Groups**: at least open each, create+delete one cheap item where practical, confirm errors (if
      any) are human-readable.

## H. Costs & the grandfathered-price override

- [ ] Costs tab: totals across projects; the donut breakdown; per-project sections.
- [ ] If you have a **grandfathered server** (paying less than the current list price): open it →
      tap the **Price row** (or the edit-price in Costs) → enter what you **actually** pay → confirm
      the Dashboard burn, Costs total, and donut all update to your real number.
- [ ] Add a **manual/dedicated fixed cost** → appears in "All" scope.
- [ ] **Export CSV** and **Share image** from the Costs toolbar menu — both produce a file/image.
- [ ] Invoices row → opens the Hetzner portal in the in-app browser (your login stays with Hetzner).

## I. Robot / dedicated (only if you use Robot)

- [ ] Settings → add a **Robot webservice** account (note: **one** wrong login = the 3-strikes
      warning; get the credentials right).
- [ ] A **Dedicated** tab appears. List/detail render; traffic shown as-is.
- [ ] **Reset** sheet explains sw/hw/man in plain language; **Wake-on-LAN**; **rescue** shows the
      one-time password; **rDNS** edit; **vSwitch** and **failover** screens open.
- [ ] **Failover switch routing** → always Face-ID gated (don't reroute production unless intended).
- [ ] **Ordering** (⚠️ real money): browse the **server market** and **standard** products, open a
      product, review screen. **Stop at the arm toggle** unless you truly want to buy. Confirm the
      403 "ordering not enabled" explainer if your account has ordering off.

## J. Storage Boxes (only if you use them)

- [ ] Settings → add a Storage Box account. Resources → Storage → list/detail, usage bar.
- [ ] Toggle a protocol (SMB/SSH/WebDAV) → confirm it applies. Snapshots list; create + delete one.
      Subaccounts; a password reset shows the generated password once.

## K. Cross-cutting

- [ ] **Read-only token**: switch to the read-only project and try a power action → **Expect:** clear
      "your token is read-only — replace it with a Read & Write token" message **with an Update Token
      button**, not a raw error. Tap it, paste a R&W token → the project recovers.
- [ ] **Offline**: enable Airplane Mode → open Dashboard/Resources/Dedicated → **Expect:** last-known
      data still shows with an "Offline — showing cached data" chip, not a blank screen.
- [ ] **Notifications**: start a reboot, then background the app → **Expect:** a local notification
      when it completes (permission prompt appears the first time). Best-effort — iOS may not always
      grant the background window.
- [ ] **Widgets**: (skip if the widget target is still disabled) add the small + medium widgets; a
      widget tap deep-links into the app.
- [ ] **Deep links / Siri**: try the "Reboot <server>", "Server status", "Monthly cost" Shortcuts.
- [ ] **Face ID**: Settings → require Face ID for destructive actions ON → a delete now prompts Face
      ID. App-switcher privacy shield hides content (and returns instantly on unlock).
- [ ] **Light mode**: Settings → Appearance → System, then set the phone to Light → the app is legible
      (dark is the intended hero, but light shouldn't be broken).
- [ ] **Dynamic Type / VoiceOver**: bump text size very large → nothing critical truncates; a quick
      VoiceOver sweep of the Dashboard reads sensibly.

## L. Cleanup

- [ ] Delete the throwaway server (if not already) and any test volumes/firewalls/keys/IPs.
- [ ] Optionally remove the throwaway project + tokens from both Hetzly and the Hetzner Console.

---

### What to report back
For anything that fails: the **screen**, the **exact on-screen text**, and what you **expected**.
The highest-value feedback is on **write actions**, the **SSH terminal**, **Robot**, and
**notifications** — none of those were ever exercised against the real API before you.
