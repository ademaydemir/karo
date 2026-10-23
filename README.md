<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Karo app icon">
</p>

<h1 align="center">Karo</h1>

<p align="center">
  Window management for macOS.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-informational" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
</p>

## Snap

Drag a window to a screen edge or corner to fill a half or a quarter. Karo then suggests windows for the free space.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-snap-dark.gif">
  <img src="docs/images/scene-snap-light.gif" width="664" alt="A window is dragged to the left edge and snaps to the left half; Karo suggests windows for the right half">
</picture>

## Place with the keyboard

| | |
|---|---|
| Left / right half | ⌃ + ⌥ + ← / ⌃ + ⌥ + → |
| Maximize | ⌃ + ⌥ + ↩ |
| Restore | ⌃ + ⌥ + ⌫ |

Quarters, thirds and more are in Settings, where every shortcut can be changed.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-keyboard-dark.gif">
  <img src="docs/images/scene-keyboard-light.gif" width="664" alt="A window jumps to the left half, the right half, full screen and back as shortcuts are pressed">
</picture>

## Switch between windows

⌘ + Tab shows one icon per app. Karo's ⌥ + Tab shows every window, and right-click offers quick actions.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/scene-switcher-dark.gif">
  <img src="docs/images/scene-switcher-light.gif" width="664" alt="Karo's switcher shows each window, fans out two browser windows and opens a ring of quick actions">
</picture>

## Install

Download the `.dmg` from the [latest release](https://github.com/ademaydemir/karo/releases/latest), open it and drag Karo to Applications. Karo needs macOS 14 or later and runs on Apple silicon and Intel Macs.

On first launch Karo asks for Accessibility permission, which it needs to move other apps' windows. It checks for updates once a day and asks before installing one.

## License

[MIT](LICENSE)
