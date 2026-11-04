# Drag & drop improvements

Goal: make drag & drop do what the user means. Trigger: dragging a snapped window from the
left display onto the right display swapped it with the maximized window there instead of
just moving it (`SnapZoneTracker.findSwapTarget` took any snapped window under the pointer).

Workflow: Claude plans and reviews; Sonnet subagents write the code; `swift build` +
`swift test` after each step, then one commit per step.

## Steps

- [x] 1. fix: swap only on purpose — same display as the source slot, never with a window
      that fills the display, pointer must be in the target's central area (`SwapPolicy` in KaroCore + tests)
- [x] 2. feat: preview both sides of a swap (second overlay where the other window goes)
- [x] 3. feat: hold ⌥ to force a swap (bypasses step 1 rules; ignored when ⌥ is part of the modifier-drag combo)
- [x] 4. feat: Esc cancels the snap/swap for the rest of the drag
- [x] 5. feat: zone hysteresis so edge/corner zones do not flicker at their borders
- [x] 6. feat: snap at edges shared between displays after a short dwell (~0.4 s)
- [ ] 7. feat: bottom edge snaps to thirds between its corners
- [ ] 8. feat: fill the free region next to a snapped window after a dwell (~0.5 s)
- [ ] 9. feat: setting — a snapped window dragged to another display keeps its layout there (default off)
- [ ] 10. docs: Settings / Welcome / README texts (en + tr) for the new drag behaviour

## Decisions

- Swap rules live in pure KaroCore code so they are unit tested; AppKit glue stays in `SnapZoneTracker`.
- Dwell is required wherever a zone could surprise (shared display edges, empty-region fill).
- Cross-display layout keeping is opt-in, so "drop where I drop" stays the default.
