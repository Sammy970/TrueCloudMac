# TrueCloud for Mac

A native macOS client for [TrueCloud](https://truecloud.in), the cloud-PC service built on Sunshine and Moonlight.
It signs in, shows your plan and cloud PC state, starts and stops the PC, pairs Moonlight by itself and launches the stream.

> Independent prototype made to show TrueCloud, with their permission. It is not an official release and is not published anywhere.
> "TrueCloud" belongs to its owners. The app icon and theme are original; the accent is teal and indigo.

Forked from the AntCloud Mac client's UI and Moonlight driving; everything service-specific is rewritten for TrueCloud.

## What it does

- **Sign in** with email and password (Firebase Auth, TrueCloud's own project). The password is never stored; only the refresh token is, in the Keychain.
- **Home**: greeting, plan card (plan name, time left, daily quota, renewal), a drawn monitor with the rig state
  (Offline, Starting, Booting Sunshine, Ready, Streaming) and a four-step track (Power on, Boot, Sunshine, Play).
- **Start Cloud PC**, then **Play**: starts the VM, polls until Sunshine answers, pairs Moonlight if needed (random PIN handed to Sunshine
  through the dashboard), and opens the stream in Moonlight (app "Desktop").
- **Shut Down** (confirm), **Force Stop** and **Unpair All Devices** (both behind the More menu, with confirmation).
- **Endpoint picker** A2 or A4 (both `host:35450`); the choice is remembered.
- **Stream** settings (resolution, aspect, FPS, bitrate, fullscreen, HEVC), **Network** check (round trip to the gateway plus download speed),
  **Controllers** pane, in-stream **overlay** (time left, latency, Moonlight shortcuts).
- Errors are readable: wrong password, expired session (refresh, then sign in again), no plan time, VM locked while being built, cooldown.

Google sign-in (which the website also has) is not implemented. Use "Forgot password?" once to add a password to a Google-created account.

## Requirements

- macOS 13+, Xcode toolchain for building.
- [Moonlight](https://moonlight-stream.org) (`brew install --cask moonlight`), or build with `--bundle-moonlight`.

## Build and run

```sh
export DEVELOPER_DIR=$(ls -d /Applications/Xcode*.app | head -1)/Contents/Developer
swift build -c release          # or:
scripts/build-app.sh            # builds build/TrueCloud.app (signed with your Apple Development cert if present, else ad-hoc)
scripts/build-app.sh --bundle-moonlight --adhoc
scripts/make-release.sh         # dist/TrueCloud-<version>-mac.zip, ad-hoc signed
open build/TrueCloud.app
```

## Tests

```sh
swift test
```

`Tests/KitTests` covers the networking module `TrueCloudKit` with fixtures (Firestore parsing, RSC parsing, Server Action request shapes,
the action-id resolver, Firebase request/response and error mapping, stale-id retry) and two **read-only live checks**: the resolver
against the live rig page and `getVmStatus`. They skip when offline. No test calls start, shutdown, stop, unpair or sendPin.

## Preview mode (debug builds)

`TRUECLOUD_PREVIEW=login` or `home:<phase>[:stream|network|about|controllers|sample|notice|confirm-shutdown|confirm-force|confirm-unpair]`
(phases: checking, idle, starting, booting, ready, pairing, streaming, shutting) renders a state with a fake profile and no network.
`TRUECLOUD_APPEARANCE=light` for light mode, `TRUECLOUD_SNAPSHOT=<file.png>` saves the window and quits (`TRUECLOUD_SNAPSHOT_DELAY=<s>` to wait longer).
Screenshots are in `.github/screenshots`.

## How it talks to TrueCloud

| Need | How |
|---|---|
| Sign in / refresh | Firebase REST (`identitytoolkit` signInWithPassword, `securetoken` refresh) with the web app's public API key |
| Profile and plan | Firestore REST `users/<uid>` with the ID token (node, vmid, moonlight_ip, sunshine_port, plan, time) |
| VM status | Server Action `getVmStatus(node, vmid, sunshine_port)`, no auth |
| Start, shutdown, force stop | Server Actions `startVm`, `shutdownVm`, `stopVm` with `(node, vmid, idToken)` |
| Pair PIN, unpair | Server Actions `sendPin(sunshine_port, pin, idToken)`, `unpairAllDevices(sunshine_port, idToken)` |
| Streaming | Moonlight CLI: `Moonlight pair <host>:35450 --pin N`, `Moonlight stream <host>:35450 Desktop ...` |

Server Action ids change on every TrueCloud deploy, so `ActionResolver` reads them from the rig page's JavaScript
(`createServerReference("<id>", …, "<name>")`), caches them, and re-resolves after a failed call. The ids seen on 2026-11-02 are the fallback.

## Layout

- `Sources/Kit`: `TrueCloudKit` (Foundation only): Firebase, Firestore, RSC parsing, ActionResolver, RigAPI.
- `Sources/Shared`: app logic and views (AuthStore, SessionService, themes in `PlatformStyles.swift`, Login, session views, About).
- `Sources/Mac`: window, panes, Moonlight driver, overlay, controllers.
- `scripts`: `build-app.sh`, `make-release.sh`, `make-icon.swift` (draws the icon), `update-controller-db.sh`.
