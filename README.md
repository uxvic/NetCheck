# NetCheck

A tiny macOS **menu bar** app that tells you, at a glance, whether your internet is *actually* working — and how fast data is flowing right now.

It exists for one specific frustration: **a VPN that stays "connected" while your real internet is dead.** macOS shows you're online; nothing loads. NetCheck *actively verifies* reachability, so it catches that exact case (and captive-portal Wi-Fi, and plain disconnects) and can ping you the instant it happens.

```
  ↓2.4M ↑0.3M     ← live download / upload rate, always visible in the menu bar
       ●          ← green = online · red = offline / VPN-dead · amber = sign-in needed
```

## Features

- **Live ↓↑ throughput** in the menu bar, updating ~once a second.
- **Active reachability check** — distinguishes *Online* / *Offline* / **VPN-connected-but-no-internet** / *Captive portal* / *Checking*.
- **Disconnect & back-online notifications** (with a 2-strike rule so blips don't spam you).
- **Launch at login** (`SMAppService`).
- **Detail popover** — public IP, latency, active interface (Wi-Fi/Ethernet/VPN), and a live speed sparkline.
- **Customizable bar** — icon-only vs icon+speed, color-by-status.
- **Self-updating** via [Sparkle](https://sparkle-project.org) — new versions install themselves.
- Native Swift, un-sandboxed, lightweight. macOS 14+.

## Install (for users)

**Homebrew (recommended — installs with no Gatekeeper warning):**
```sh
brew tap uxvic/netcheck
brew install --cask netcheck
```

**Direct download:** grab `NetCheck-x.y.z.dmg` from [Releases](https://github.com/uxvic/NetCheck/releases), open it, drag NetCheck to Applications. The first launch is blocked because the app isn't notarized yet — open **System Settings → Privacy & Security**, scroll to the NetCheck prompt, and click **Open Anyway**. (One time only.)

---

## Build from source (developer)

> This repo is fully authorable on a Mac **without Xcode** (it uses [XcodeGen](https://github.com/yonaskolb/XcodeGen)). You only need Xcode to *compile/run*.

**Prerequisites (the machine with Xcode):**
```sh
brew install xcodegen           # generates the .xcodeproj from project.yml
# Xcode from the App Store; then:  sudo xcodebuild -license accept
```

**Build & run:**
```sh
git clone https://github.com/uxvic/NetCheck.git
cd NetCheck
xcodegen generate               # writes NetCheck.xcodeproj (git-ignored)
open NetCheck.xcodeproj          # ⌘R to run
```
In Xcode → target **NetCheck → Signing & Capabilities**, pick your team (a free Apple ID gives "Sign to Run Locally"). That's enough for local development.

### Project layout
```
project.yml                 XcodeGen spec (source of truth for the project)
App/                        Main.swift (@main), AppDelegate, Info.plist, entitlements
Monitoring/                 NetworkMonitor + workers (sampler, probe, path, IP, power)
MenuBar/                    StatusItemController, BarRenderer
UI/                         DetailPanel, SparklineView, SettingsView, PanelHostController
Services/                  Preferences, Notifier, LoginItem, UpdaterController (Sparkle)
scripts/sign_and_package.sh Build → sign → DMG → (optional) Sparkle-sign
.github/workflows/release.yml  Tag-triggered CI release
packaging/homebrew/        netcheck.rb cask (copy into the homebrew-netcheck tap repo)
```

---

## Releasing

Releases are produced by **GitHub Actions** on a tag push (free macOS runners have Xcode) — so you don't need either of your laptops on to ship.

**One-time setup (M4):**
1. Generate Sparkle EdDSA keys (on any Mac with the Sparkle tools):
   ```sh
   ./.sparkle/bin/generate_keys          # stores the private key in your Keychain, prints the public key
   ```
   - Put the **public key** into `App/Info.plist` → `SUPublicEDKey`.
   - Export the **private key** (`generate_keys -x private.pem`), add it as the GitHub repo secret **`SPARKLE_PRIVATE_KEY`**, then delete the local copy. **Back it up somewhere safe — lose it and you can never ship another auto-update.**
2. Create the tap repo `homebrew-netcheck` and copy `packaging/homebrew/netcheck.rb` to `Casks/netcheck.rb`.

**Each release:**
```sh
# bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in project.yml, commit, then:
git tag v1.0.1 && git push origin v1.0.1
```
CI builds the DMG, signs the appcast, and publishes a GitHub Release with `NetCheck-1.0.1.dmg` + `appcast.xml`. Running copies of NetCheck pick up the update automatically. Update `version` + `sha256` in the tap's cask.

### Auto-updates work without a paid Apple account
Sparkle verifies updates with **its own EdDSA signature** (not Apple's) and **strips the quarantine flag on install**, so an unsigned app updates itself with no Gatekeeper prompt. The `$99/yr` Apple Developer Program only improves the *first* download for non-technical users (notarization).

### Adding notarization later (one-line change)
Once you have the Developer ID cert, in `scripts/sign_and_package.sh` set `SIGN_IDENTITY="Developer ID Application: …"` and `NOTARIZE=1` (+ `NOTARY_PROFILE`). Nothing else — Sparkle, the appcast, the keys, the cask — changes.

## Verifying the VPN-dead-internet case
Connect your VPN, then block its egress (e.g. a Little Snitch/`pf` rule denying `captive.apple.com` + `gstatic.com`). The interface stays "connected" but the probe fails → NetCheck shows **VPN — No Internet** and notifies. Turn Wi-Fi off entirely → **Offline**. Reconnect → **Back online** notification.

## Cost
$0 to build, ship, and auto-update. Optional later: Apple Developer Program ($99/yr) for a zero-warning first launch.

## License
MIT © 2026 Victor Adedini. See [LICENSE](LICENSE).
