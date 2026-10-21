# Tessera

Windows-style window management for macOS: drag windows to screen edges and corners to snap them into halves and quarters, place them with keyboard shortcuts, and switch between individual windows with ⌥Tab.

Written in pure Swift (AppKit + SwiftUI), no third-party dependencies, no telemetry.

> **Status:** early development (M0 — project skeleton). See [docs/PRODUCT_ANALYSIS.md](docs/PRODUCT_ANALYSIS.md) for scope and roadmap.

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

All window shortcuts can be changed or removed in **Settings… (⌘,)** from the menu bar icon, along with launch at login, drag-snapping sensitivity and the gap between windows.

While the switcher is open: ⌥← / ⌥→ to move, ⌥Esc to cancel, or click a window.

Drag a window to a screen edge or corner to snap it; hold ⇧ while dragging to skip snapping. After snapping to a half or a third, Snap Assist offers your other windows for the free side.

Hold ⌃⌥ and drag anywhere inside a window to move it, or right-drag to resize it from the nearest corner (the keys can be changed in Settings).

When you connect or disconnect a display, Tessera puts windows back where they were the last time you used that display setup. Turn off macOS's own "Drag windows to screen edges to tile" (System Settings → Desktop & Dock) so the two do not compete.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ / Swift 6 toolchain (for building)

## Building

```bash
scripts/run.sh            # build build/Tessera.app (debug) and launch it
scripts/build-app.sh release
swift test
```

To open Settings on a given tab at launch (handy when working on the UI):

```bash
open build/Tessera.app --args -ShowSettingsTab shortcuts
```

Tessera needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility) to move other apps' windows.

### Code signing during development

macOS ties the Accessibility permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would have to be granted again after each rebuild. To avoid that, copy `Signing.local.env.example` to `Signing.local.env` and set your Apple Development identity:

```bash
security find-identity -v -p codesigning
```

If the permission gets stuck, reset it with `tccutil reset Accessibility dev.ademaydemir.Tessera`.

## Localization

Tessera is available in English and Turkish. It follows the macOS language, or the language chosen in Settings → General.

User-facing text is written in English in the code (`String(localized:)`, SwiftUI literals) and translated in the String Catalog `Support/Localizable.xcstrings`. After adding or changing text, pull the new strings into the catalog, then add translations (Xcode's catalog editor works, or edit the JSON):

```bash
scripts/update-strings.sh
```

`scripts/build-app.sh` compiles the catalog into the app bundle.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/TesseraCore` | Platform-independent logic (actions, layout math), unit-tested |
| `Sources/TesseraAccessibility` | Wrappers around the macOS Accessibility API |
| `Sources/Tessera` | Menu bar app |
| `Support/Info.plist` | App bundle metadata |
| `scripts/` | Bundling and run scripts |

## License

[MIT](LICENSE)
