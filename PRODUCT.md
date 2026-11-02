# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos (native SwiftUI, macOS 13+)

## Users
TrueCloud subscribers who want to play on their cloud PC from a Mac.
They open the app, start the cloud PC, wait for Windows and Sunshine, then hand off to a fullscreen Moonlight stream.

## Product Purpose
A native Mac client for TrueCloud (prototype, shown to TrueCloud with their permission). It signs in, shows plan time, starts and shuts down the cloud PC,
pairs Moonlight automatically and launches the stream with the user's settings.
Success means: one click to start, one click to play, no manual pairing.

## Operating Context
- The app is open only before and after a session. During play, Moonlight owns the screen.
- Cloud PC states: Offline, Starting, Booting Sunshine, Ready, Pairing, Streaming, Shutting down.
- Stream settings change occasionally and lock while streaming.
- Requires Moonlight installed (`brew install --cask moonlight`).

## Brand Commitments
- Original icon and a teal/indigo theme; no TrueCloud artwork.
- Never present the app as an official TrueCloud release.

## Product Principles
1. Play first: the state of the cloud PC and the next action dominate.
2. Native Mac behaviour: standard controls, sidebar navigation, light and dark.
3. Tell the truth about time: plan time left, daily quota, what each destructive action does.
