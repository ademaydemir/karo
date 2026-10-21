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

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ / Swift 6 toolchain (for building)

## Building

```bash
scripts/run.sh            # build build/Tessera.app (debug) and launch it
scripts/build-app.sh release
swift test
```

Tessera needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility) to move other apps' windows.

### Code signing during development

macOS ties the Accessibility permission to the app's code signature. An ad-hoc signature changes on every build, so the permission would have to be granted again after each rebuild. To avoid that, copy `Signing.local.env.example` to `Signing.local.env` and set your Apple Development identity:

```bash
security find-identity -v -p codesigning
```

If the permission gets stuck, reset it with `tccutil reset Accessibility dev.ademaydemir.Tessera`.

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
