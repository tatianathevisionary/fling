# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Remote pages under the app grid — Arrows (the d-pad), Touchpad (drag for
  arrows, click = OK, right-click = Back, middle-click = Home), Numbers
  (digits, channel ±, Input, Guide, Info, Settings; the Mac's digit keys
  type digits while it is open) and Media (previous / rewind / play-pause /
  fast-forward / next, stop, subtitles, audio track, colour buttons). The
  choice is remembered.
- Favourite apps per TV: right-click a chip to move, rename or remove it;
  "+" adds the app open on the TV, a catalog app or a package, or restores
  the default set. Apps without a known app link are marked, and when the
  TV doesn't open one the panel says so.
- Scenes — named steps (turn on, open an app, TV volume, a remote button,
  wait, sleep timer, turn off, optionally "switch to this TV first") with an
  editor window; run them from the remote's "⋯" menu or the menu-bar icon's
  right-click menu.
- Sleep timer (15 min – 2 h) with a "the TV turns off in N min" strip, and
  explicit Turn on / Turn off using the one-way WAKEUP / SLEEP keys.

## [1.0.0] - 2026-08-29

### Added

- Menu bar panel that casts the current Chrome or Safari tab to a
  Chromecast / Google TV, with playback controls, artwork, progress, and a
  debounced stream-volume slider.
- System-wide ⌘⇧C shortcut that casts the frontmost browser tab.
- Clipboard URL casting.
- Resume-from-position casting: an in-page probe reads the tab's actual
  player and the cast starts where the video left off; blob-based players
  are cast via their sniffed HLS/DASH manifest.
- Full TV remote over a dependency-free Android TV Remote protocol v2
  implementation: one-time PIN pairing, power, d-pad with Back/Home,
  instant volume and mute, and typed text into the TV's focused field.
- App launcher with hardware-verified deep links (YouTube, Netflix,
  Prime Video, Disney+, Spotify, Plex, Tubi) and foreground-app highlighting.
- Voice search: the Mac microphone streams to the TV's voice input.
- Scroll-to-navigate: trackpad and mouse-wheel gestures over the open panel
  drive the TV's d-pad, with momentum ignored and steps rate-limited.
- CEC "One Touch Play" wake that powers the TV on without pairing.
- Multi-TV support with per-device pairing and a device switcher.
- One-command installers — a curl script and `npx github:damionrashford/fling`
  — that assemble the app from the repo-served universal binary with no
  Gatekeeper prompts.
- Session diagnostics log at `~/Library/Logs/Fling.log`.

[unreleased]: https://github.com/damionrashford/fling/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/damionrashford/fling/releases/tag/v1.0.0
