# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Karo is a macOS 14+ menu bar app for window management: drag snapping, keyboard placement, an ⌥Tab window switcher, Snap Assist, Dock previews, and per-display layout memory. It is a Swift package with no Xcode project. The UI is in English, with Turkish translations.

## Commands

```sh
swift build                                   # compile all targets
swift test                                    # run the KaroCoreTests suite (Swift Testing)
swift test --filter SwapPolicyTests           # one suite; append /<test name> for a single test
./scripts/build-app.sh debug                  # wrap into a signed build/Karo.app (release: universal binary)
./scripts/run.sh                              # rebuild build/Karo.app, quit the running Karo, open the new one
./scripts/update-strings.sh                   # add new String(localized:) keys to Support/Localizable.xcstrings
/usr/bin/log stream --level debug --predicate 'subsystem == "dev.ademaydemir.Karo" AND category == "drag"'
```

- Only `swift build` and `swift test` run without Accessibility permission. To check real window behaviour, build the app and launch it; there are no UI tests.
- `scripts/` and `Signing.local.env.example` are git-ignored, so they are local only. Signing reads `Signing.local.env` (`KARO_SIGN_IDENTITY`); `release.sh` also needs `KARO_RELEASE_IDENTITY` and `KARO_NOTARY_PROFILE`.
- `update-strings.sh` reformats the whole xcstrings catalog. Afterwards restore the catalog's existing formatting so the diff shows only the new keys, then add the `tr` translation for every new key by hand. `build-app.sh` compiles the catalog into `en.lproj` and `tr.lproj`.

## Architecture

There are three targets, layered:

- **KaroCore**: pure logic with no AppKit or Accessibility. It covers actions and layout math (`WindowAction`, `LayoutCalculator`), display selection, zone detection, swap and free-region rules, switcher ordering, radial-menu geometry, and `KaroSettings` (Codable; new fields must use `decodeIfPresent` so old saved settings still decode). This is the only target with tests. Decisions that can be expressed without AppKit belong here, with tests.
- **KaroAccessibility**: thin wrappers over `AXUIElement` (`AXWindow`, permission, focus and Dock observers).
- **Karo**: the AppKit and SwiftUI app. `AppDelegate` builds every controller and pushes `SettingsStore` changes into them.

Cross-cutting facts that need several files to see:

- **Coordinates:** Accessibility and `CGWindowList` use a top-left origin; AppKit uses bottom-left. Convert with `CoordinateConverter.flip` using the primary screen's height. KaroCore geometry is in Accessibility coordinates.
- **Placement:** `WindowPlacer` is the single path for moving windows (keyboard, menu, drag, switcher). It keeps the frame history for Restore, and its `onPlace` callback triggers Snap Assist.
- **Dragging:** `DragSnapController` (title-bar drags) and `ModifierDragController` (modifier + drag from anywhere, using a CGEvent tap) both feed `SnapZoneTracker`. The tracker decides zone, swap, or free region and shows `SnapPreviewOverlay`. During a drag the AX frame is stale, so live geometry comes from `WindowServer` (CGWindowList). macOS 15+ edge tiling competes with this (`SystemTiling`).
- **Window list:** `WindowCatalog` is the shared most-recently-used window list for the switcher, Snap Assist, layout memory, and Dock previews. It also owns window preview capture, which needs Screen Recording permission; titles do too.
- **Floating UI:** panels are `NSPanel`s hosting SwiftUI, on top of `GlassSurface` (`NSGlassEffectView` on macOS 26, `NSVisualEffectView` before).

## Conventions

- **Shared interactions live in one place.** Right-click-to-open, hover and close grace, and hit testing are written once in a central component that screens only call. Examples are the `View.radialMenu(...)` modifier in `RadialMenuInteraction.swift` and `SecondaryClickClaiming` with `FirstMouseHostingView.swallowsSecondaryClicks` in `SwitcherPanel.swift`. Fix or extend the central component; don't re-implement the behaviour per screen.
- **Mouse path:** Make no Accessibility calls on a plain click or anywhere the event tap waits. The clicked app's main thread is busy with that click, so use `WindowServer` until the press is really a move or resize. The tap runs on its own thread and reaches the main thread only for the configured modifier combination or an active gesture (`ModifierDragPolicy`).
- **Commit messages:** Conventional Commits in English (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`). Make one commit per completed step.
- **Long tasks:** track progress and decisions in `PLAN.md` at the repo root.
- **Workflow:** Claude plans and reviews; coding goes to lower-model (Sonnet/Haiku) subagents. Run `swift build` and `swift test` after each step, then commit before moving on. Don't delegate to Gemini.
- **README:** keep the English section and the Turkish `<details>` section in sync. GIFs in `docs/images` are recorded by `scripts/readme-images.sh` (DEBUG build, `-CaptureReadmeAssets`).
