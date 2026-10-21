<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Karo app icon">
</p>

<h1 align="center">Karo</h1>

<p align="center">
  Windows-style window management for macOS.<br>
  Snap windows to edges and corners, place them from the keyboard, and switch between every window with ⌥Tab.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-informational" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
</p>

<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-snap-dark.gif">
  <img src="docs/images/scene-snap-light.gif" width="664" alt="A window is dragged to the left edge, snaps to the left half, and Snap Assist offers windows for the right half">
</picture>
</p>

Pure Swift (AppKit + SwiftUI), no third-party dependencies, no telemetry: nothing leaves your Mac.

> **Status:** in active development; there is no signed release yet, so build it from source (below). See [docs/PRODUCT_ANALYSIS.md](docs/PRODUCT_ANALYSIS.md) for scope and roadmap.

## Features

### Drag to snap, with Snap Assist

Drag a window to a screen edge or corner to fill a half or a quarter; the top edge maximizes, and a preview shows where it will go. Hold ⇧ while dragging to move freely. After snapping, Snap Assist offers your other windows for every free area at once, with a live preview of the result.

### Place windows from the keyboard

Halves, quarters, thirds, two thirds, maximize, center, restore and moving between displays. The shortcuts are Rectangle-compatible and can all be changed.

<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-keyboard-dark.gif">
  <img src="docs/images/scene-keyboard-light.gif" width="664" alt="A window jumps to the left half, the right half, full screen and back as shortcuts are pressed">
</picture>
</p>

### Every window in ⌥Tab, not just every app

macOS's ⌘Tab shows one icon per app, so two Safari windows are one icon. Karo's ⌥Tab shows every window, with live previews. An app's windows share a deck that fans out when you reach it, or browse them in Cover Flow. Right-click a window for quick actions: left or right half, maximize, next display, minimize, close, hide or quit the app.

<p align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-switcher-dark.gif">
  <img src="docs/images/scene-switcher-light.gif" width="664" alt="macOS's app switcher shows app icons; Karo's switcher shows each window, fans out a deck of two browser windows and opens a ring of quick actions">
</picture>
</p>

### And more

- **Swap and shared edges.** Drag a snapped window onto another to swap them. Resize along an edge two windows share, and the neighbour follows.
- **Move from anywhere.** Hold ⌃⌥ and drag anywhere inside a window to move it, or right-drag to resize it from the nearest corner.
- **Layout memory.** Connect or disconnect a display, and windows go back to where they were the last time you used that setup.
- **Multiple displays,** including separate Spaces per display: on a display without the Dock, windows use the full height.
- **At home on macOS.** A menu bar app (the icon can be hidden), Liquid Glass on macOS 26, English and Turkish.

## First launch

Karo opens a short welcome guide that asks for its permissions:

| Permission | Needed for |
|---|---|
| **Accessibility** (required) | Moving and resizing other apps' windows |
| **Screen Recording** (optional) | Live window previews in the switcher and Snap Assist. Karo never records or saves the screen. Restart Karo after allowing it. |

Karo lives in the menu bar. Open the guide again from the menu bar icon (**Welcome Guide…**), and everything else from **Settings… (⌘,)**. If you hide the menu bar icon in Settings, open Karo again from Finder or Spotlight to get to Settings.

macOS 15 and later have their own edge tiling, which reacts to the same drags. Turn off "Drag windows to screen edges to tile" in System Settings → Desktop & Dock so only Karo snaps; the guide and Settings point this out when it is on.

## Default shortcuts

Rectangle-compatible, so switching over keeps your muscle memory.

| Action | Shortcut |
|---|---|
| Left / right half | ⌃⌥← / ⌃⌥→ |
| Top / bottom half | ⌃⌥↑ / ⌃⌥↓ |
| Top left / top right / bottom left / bottom right | ⌃⌥U / ⌃⌥I / ⌃⌥J / ⌃⌥K |
| Left / center / right third | ⌃⌥D / ⌃⌥F / ⌃⌥G |
| Left / right two thirds | ⌃⌥E / ⌃⌥T |
| Maximize | ⌃⌥↩ |
| Center | ⌃⌥C |
| Restore | ⌃⌥⌫ |
| Next / previous display | ⌃⌥⌘→ / ⌃⌥⌘← |
| Switch windows (hold ⌥, release to switch) | ⌥Tab / ⌥⇧Tab (in Cover Flow, also swipe sideways) |

While the switcher is open: ⌥← / ⌥→ to move, ⌥Esc to cancel, or click a window.

### A gap below windows on an external display?

With "Displays have separate Spaces" on, macOS reserves room for the Dock on every display. Karo ignores that reservation on displays without the Dock, but apps built with AppKit (Safari, Mail, Finder…) still limit their own height to it, leaving a strip at the bottom. To remove it, turn on "Automatically hide and show the Dock", or turn off "Displays have separate Spaces" (both in System Settings → Desktop & Dock; the latter needs a log out).

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ / Swift 6 toolchain (for building)

## Building

```bash
scripts/run.sh            # build build/Karo.app (debug) and launch it
scripts/build-app.sh release
swift test
```

To open Settings on a given tab at launch (handy when working on the UI):

```bash
open build/Karo.app --args -ShowSettingsTab shortcuts
```

The animations in this README are recorded from the welcome guide; after changing it, record them again with `scripts/readme-images.sh` (debug builds only, uses Karo's Screen Recording permission).

To see the welcome guide again as on first launch: `defaults delete dev.ademaydemir.Karo hasShownWelcome`.

### Code signing during development

macOS ties the Accessibility permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would have to be granted again after each rebuild. To avoid that, copy `Signing.local.env.example` to `Signing.local.env` and set your Apple Development identity:

```bash
security find-identity -v -p codesigning
```

If the permission gets stuck, reset it with `tccutil reset Accessibility dev.ademaydemir.Karo`.

## Localization

Karo is available in English and Turkish. It follows the macOS language, or the language chosen in Settings → General.

User-facing text is written in English in the code (`String(localized:)`, SwiftUI literals) and translated in the String Catalog `Support/Localizable.xcstrings`. After adding or changing text, pull the new strings into the catalog, then add translations (Xcode's catalog editor works, or edit the JSON):

```bash
scripts/update-strings.sh
```

`scripts/build-app.sh` compiles the catalog into the app bundle.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/KaroCore` | Platform-independent logic (actions, layout math), unit-tested |
| `Sources/KaroAccessibility` | Wrappers around the macOS Accessibility API |
| `Sources/Karo` | Menu bar app |
| `Support/Info.plist` | App bundle metadata |
| `Support/AppIcon.icon` | App icon; open it in Icon Composer (comes with Xcode) to edit |
| `scripts/` | Bundling and run scripts |

## License

[MIT](LICENSE)
