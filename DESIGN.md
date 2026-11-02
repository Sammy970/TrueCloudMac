# Design

World: **Native Mac pro.** Reads like a first-party Apple utility (System Settings, Screen Sharing), with a teal accent and indigo as its partner.

- **Structure:** `NavigationSplitView`. Sidebar: Cloud PC, Stream, Network, Controllers, About, with an account footer (initial avatar, name, plan, time left, menu).
- **Appearance:** follows the system. All colours are semantic except the theme tokens in `PlatformStyles.swift`:
  `tcAccent` (teal), `tcAccentLight`, `tcAccentDeep`, `tcIndigo`, `tcScreenTop/Bottom` (monitor interior).
- **Status colours** carry meaning only: green ready or streaming, orange working, red destructive.
- **Signature move:** the *display hero*, a drawn monitor whose screen renders the cloud PC state (dark glass when off, a scanning shimmer
  with uptime while booting, a teal screen with a play glyph when ready, a live dot when streaming). Under it, a four-step track:
  Power on, Boot, Sunshine, Play.
- **Home order:** greeting, plan card, monitor, state text, track, uptime/CPU/RAM chips, the one primary action, Shut Down and More,
  endpoint picker (A2/A4), stream summary.
- **Dialogs** (confirmations and notices) are in-window glass cards over a dimmed backdrop, so they are part of the window, not system alerts.
- **Login:** a drifting aurora of teal and indigo under a hidden title bar; the form sits on a glass card; Sign In is the accent-gradient pill.
- **Motion:** staggered reveals, power-on flash, crossfade between screen states, the track fills segment by segment. Reduce Motion turns it into fades.
- **Icon:** original cloud with a play triangle on a teal-to-indigo tile, drawn by `scripts/make-icon.swift`.
