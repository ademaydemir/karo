import AppKit
import TesseraAccessibility
import TesseraCore

/// Applies placement actions to windows and remembers frames for `.restore`.
@MainActor
final class WindowPlacer {
    var gap: CGFloat = 0
    /// Called after a window was placed by any means (keyboard, menu, drag, switcher), e.g.
    /// to offer Snap Assist.
    var onPlace: (_ window: AXWindow, _ action: WindowAction, _ frame: CGRect, _ display: Display) -> Void = { _, _, _, _ in }
    private var history = FrameHistory<WindowIdentity>()

    /// Applies an action to the focused window on the display it mostly overlaps.
    func apply(_ action: WindowAction) throws {
        try apply(action, to: AXWindow.focused())
    }

    /// Applies an action to a given window, e.g. one chosen in the window switcher.
    func apply(_ action: WindowAction, to window: AXWindow) throws {
        if action == .restore {
            guard let frame = history.takeRestoreFrame(for: window.identity) else { return }
            try window.setFrame(frame)
            return
        }

        let currentFrame = try window.frame()
        let displays = ScreenGeometry.displays()
        guard let index = DisplaySelector.indexOfDisplay(
            containing: currentFrame, among: displays.map(\.visibleFrame)
        ) else { return }

        if action == .nextDisplay || action == .previousDisplay {
            guard let destination = DisplayOrdering.index(
                adjacentTo: index, among: displays.map(\.frame), backward: action == .previousDisplay
            ) else { return }
            try move(window, from: currentFrame, between: displays[index], and: displays[destination])
            return
        }
        try place(window, action, from: currentFrame, on: displays[index])
    }

    /// Snapped windows keep their proportions on the new display; free-floating windows keep their size.
    private func move(_ window: AXWindow, from currentFrame: CGRect, between source: Display, and destination: Display) throws {
        let isSnapped = history.isPlaced(window.identity, at: currentFrame)
        let target = isSnapped
            ? LayoutCalculator.scaled(currentFrame, from: source.visibleFrame, to: destination.visibleFrame)
            : LayoutCalculator.translated(currentFrame, from: source.visibleFrame, to: destination.visibleFrame)
        let actual = try fit(window, to: target, within: destination.visibleFrame)
        if isSnapped {
            history.recordPlacement(of: window.identity, from: currentFrame, to: actual)
        }
    }

    /// Target frame for an action, e.g. for previewing a snap before it happens.
    func targetFrame(for action: WindowAction, currentFrame: CGRect, on display: Display) -> CGRect? {
        LayoutCalculator.frame(for: action, in: display.visibleFrame, currentFrame: currentFrame, gap: gap)
    }

    /// - Parameter announces: Whether to call `onPlace`; Snap Assist passes `false` for the
    ///   window it places itself, so it does not offer itself again.
    func place(
        _ window: AXWindow,
        _ action: WindowAction,
        from currentFrame: CGRect,
        on display: Display,
        announces: Bool = true
    ) throws {
        guard let target = targetFrame(for: action, currentFrame: currentFrame, on: display) else { return }
        let actual = try fit(window, to: target, within: display.visibleFrame)
        history.recordPlacement(of: window.identity, from: currentFrame, to: actual)
        if announces {
            onPlace(window, action, actual, display)
        }
    }

    /// Moves and resizes a window to `target` and copes with apps that will not take that
    /// exact size.
    /// - Returns: The frame the window ended up with.
    @discardableResult
    func fit(_ window: AXWindow, to target: CGRect, within visibleFrame: CGRect) throws -> CGRect {
        try window.setFrame(target)
        var actual = try window.frame()

        // A minimum size makes the window larger than asked; keep it on the display.
        if actual.width > target.width + 1 || actual.height > target.height + 1 {
            actual = LayoutCalculator.clamped(actual, to: visibleFrame)
            try window.setPosition(actual.origin)
            return actual
        }

        // Step sizes (Terminal rows and columns) make it slightly smaller. On outer edges,
        // search for the next step up; see `StepSizeFitting`.
        let widthShortfall = target.width - actual.width
        let heightShortfall = target.height - actual.height
        var extraWidth: CGFloat? = StepSizeFitting.isStepShortfall(widthShortfall)
            && StepSizeFitting.canGrowRight(target, in: visibleFrame) ? widthShortfall : nil
        var extraHeight: CGFloat? = StepSizeFitting.isStepShortfall(heightShortfall)
            && StepSizeFitting.canGrowDown(target, in: visibleFrame) ? heightShortfall : nil
        guard StepSizeFitting.isStepShortfall(widthShortfall) || StepSizeFitting.isStepShortfall(heightShortfall) else {
            return actual
        }
        while extraWidth != nil || extraHeight != nil {
            try window.setSize(CGSize(width: target.width + (extraWidth ?? 0), height: target.height + (extraHeight ?? 0)))
            let size = try window.frame().size
            if let extra = extraWidth {
                extraWidth = size.width >= target.width - 0.5 ? nil : StepSizeFitting.nextExtra(after: extra)
            }
            if let extra = extraHeight {
                extraHeight = size.height >= target.height - 0.5 ? nil : StepSizeFitting.nextExtra(after: extra)
            }
        }

        // Whatever is still short leans on the inner edges, next to the neighbouring windows.
        let size = try window.frame().size
        let aligned = StepSizeFitting.alignedOrigin(for: size, in: target, visibleFrame: visibleFrame)
        let origin = CGPoint(
            x: size.width < target.width - 0.5 ? aligned.x : target.minX,
            y: size.height < target.height - 0.5 ? aligned.y : target.minY
        )
        try window.setPosition(origin)
        return CGRect(origin: origin, size: size)
    }

    /// Gives a snapped window its pre-snap size back when the user starts dragging it away,
    /// keeping the grab point at the same relative position under the cursor.
    func restoreSizeForDrag(of window: AXWindow, currentFrame: CGRect, cursor: CGPoint) throws {
        guard let original = history.takeRestoreFrame(for: window.identity, ifSizeMatches: currentFrame.size) else {
            return
        }
        let grabRatio = (cursor.x - currentFrame.minX) / currentFrame.width
        let origin = CGPoint(x: (cursor.x - grabRatio * original.width).rounded(), y: currentFrame.minY)
        try window.setFrame(CGRect(origin: origin, size: original.size))
    }
}
