# Click latency in other apps

Goal: Karo must not slow clicks in other apps. Trigger: switching chats in WhatsApp and Messages
(both Mac Catalyst) stutters while Karo runs.

Diagnosis (from code and logs, not reproduced live): every left click ran synchronous
Accessibility calls against the clicked app, on the same main thread that serves the active
event tap, so mouse events waited for the busy app.

Workflow: Sonnet subagents write the code; `swift build` + `swift test` after each step, then
one commit per step, on branch `fix/click-latency`.

- [x] 1. fix: no Accessibility calls on mouse down; identify the window through the window server and resolve it only once it really moves or resizes
- [ ] 2. fix: run the modifier-drag event tap on its own thread; only the modifier combo or an active gesture reaches the main thread (`ModifierDragPolicy` in KaroCore + tests)
- [ ] 3. fix: timeout on the system-wide hit test; layout memory scan off the main thread
- [ ] 4. Verify in the real app (user relaunches Karo)

Decisions:

- Fixing the click path, not removing the per-app AX observers: WhatsApp stayed fast with its Accessibility runtime still loaded after Karo quit.

---

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
- [x] 7. feat: bottom edge snaps to thirds between its corners
- [x] 8. feat: fill the free region next to a snapped window after a dwell (~0.5 s)
- [x] 9. feat: setting — a snapped window dragged to another display keeps its layout there (default off)
- [x] 10. docs: Settings / Welcome / README texts (en + tr) for the new drag behaviour

## Decisions

- Swap rules live in pure KaroCore code so they are unit tested; AppKit glue stays in `SnapZoneTracker`.
- Dwell is required wherever a zone could surprise (shared display edges, empty-region fill).
- Cross-display layout keeping is opt-in, so "drop where I drop" stays the default.
