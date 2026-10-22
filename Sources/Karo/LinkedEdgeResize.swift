import AppKit
import KaroAccessibility
import KaroCore
import OSLog

/// A resize gesture session that moves neighbouring windows along with the resized window's shared edges.
///
/// Translucent glass panels preview the positions of all linked neighbours while the drag is in progress.
/// When the gesture completes, each linked window and the resized window are fitted and recorded as adjusted.
@MainActor
final class LinkedEdgeResize {
    private struct LinkedWindow {
        let windowID: CGWindowID
        let window: AXWindow
        let initialFrame: CGRect
        var edges: [(edge: SharedEdges.Edge, draggedEdge: SharedEdges.Edge)]
    }

    let window: AXWindow
    let windowID: CGWindowID
    let initialFrame: CGRect
    private var draggedEdges: [SharedEdges.Edge]
    private let placer: WindowPlacer
    private let preview = EdgeResizePreview()
    private let logger = Logger(subsystem: "dev.ademaydemir.Karo", category: "drag")
    private var linkedWindows: [LinkedWindow]
    private var linkedEdgesByDraggedEdge: [SharedEdges.Edge: [SharedEdges.LinkedEdge<CGWindowID>]]

    /// nil when no window shares any of `draggedEdges` with the resized window — nothing to link,
    /// unless `allowEmpty` is true to allow adding dragged edges later during the gesture.
    init?(
        window: AXWindow,
        windowID: CGWindowID,
        initialFrame: CGRect,
        draggedEdges: [SharedEdges.Edge],
        placer: WindowPlacer,
        allowEmpty: Bool = false
    ) {
        guard !draggedEdges.isEmpty else { return nil }
        self.window = window
        self.windowID = windowID
        self.initialFrame = initialFrame
        self.draggedEdges = []
        self.placer = placer
        self.linkedWindows = []
        self.linkedEdgesByDraggedEdge = [:]

        link(edges: draggedEdges, isLate: false)
        guard allowEmpty || !linkedWindows.isEmpty else { return nil }

        logger.debug("Entering .resizing: window \(windowID, privacy: .public), moved edges \(self.draggedEdges, privacy: .public), linked windows \(self.linkedWindows.count, privacy: .public)")
    }

    /// Links windows along edges that started moving after the gesture began, e.g. a corner drag whose
    /// press looked like a straight edge. Edges already being dragged are ignored.
    func addDraggedEdges(_ edges: [SharedEdges.Edge]) {
        var newEdges: [SharedEdges.Edge] = []
        for edge in edges {
            if !draggedEdges.contains(edge) && !newEdges.contains(edge) {
                newEdges.append(edge)
            }
        }
        guard !newEdges.isEmpty else { return }
        link(edges: newEdges, isLate: true)
    }

    private func link(edges: [SharedEdges.Edge], isLate: Bool) {
        draggedEdges.append(contentsOf: edges)

        let others = WindowServer.windows().filter { $0.id != windowID }
        let candidates = others.enumerated().map { (id: $0.offset, frame: $0.element.bounds) }

        for draggedEdge in edges {
            let linked = SharedEdges.linkedEdges(of: initialFrame, edge: draggedEdge, among: candidates, gap: placer.gap)
            var resolvedEdges: [SharedEdges.LinkedEdge<CGWindowID>] = []
            for item in linked {
                let info = others[item.id]
                let otherID = info.id
                if let index = linkedWindows.firstIndex(where: { $0.windowID == otherID }) {
                    linkedWindows[index].edges.append((edge: item.edge, draggedEdge: draggedEdge))
                    resolvedEdges.append(SharedEdges.LinkedEdge(id: otherID, frame: item.frame, edge: item.edge))
                } else if let otherWindow = AXWindow.window(ofApplication: info.processIdentifier, matching: info.bounds) {
                    linkedWindows.append(LinkedWindow(
                        windowID: otherID,
                        window: otherWindow,
                        initialFrame: item.frame,
                        edges: [(edge: item.edge, draggedEdge: draggedEdge)]
                    ))
                    resolvedEdges.append(SharedEdges.LinkedEdge(id: otherID, frame: item.frame, edge: item.edge))
                }
            }
            if !resolvedEdges.isEmpty {
                linkedEdgesByDraggedEdge[draggedEdge] = resolvedEdges
            }
            if isLate {
                logger.debug("Late edge added: window \(self.windowID, privacy: .public), edge \(draggedEdge, privacy: .public), linked \(resolvedEdges.count, privacy: .public)")
            }
        }
    }

    /// Moves the previews to where the linked windows will go for this frame of the resized window.
    /// - Returns: the resized window's frame with each dragged edge clamped so no window drops below the minimum.
    @discardableResult
    func update(draggedFrame: CGRect) -> CGRect {
        guard !linkedWindows.isEmpty else {
            preview.hide()
            return draggedFrame
        }
        let (clampedDragged, _, targets) = layout(draggedFrame: draggedFrame)
        preview.show(targets)
        return clampedDragged
    }

    /// Hides the previews and fits every linked window (and the resized window if it was clamped) once,
    /// recording them as adjusted, exactly as the current mouse-up code does.
    func finish(finalFrame: CGRect) {
        preview.hide()
        guard !linkedWindows.isEmpty else { return }
        let (clampedDraggedFrame, isClamped, targets) = layout(draggedFrame: finalFrame)

        var finalDraggedFrame = finalFrame
        if isClamped {
            do {
                let display = ScreenGeometry.displays().first { $0.visibleFrame.intersects(clampedDraggedFrame) }
                finalDraggedFrame = try placer.fit(window, to: clampedDraggedFrame, within: display?.visibleFrame ?? clampedDraggedFrame)
            } catch {
                logger.error("Fitting clamped dragged window failed: \(String(describing: error), privacy: .public)")
            }
        }

        for (index, item) in linkedWindows.enumerated() {
            let target = targets[index]
            do {
                let display = ScreenGeometry.displays().first { $0.visibleFrame.intersects(target) }
                let actual = try placer.fit(item.window, to: target, within: display?.visibleFrame ?? target)
                placer.recordAdjustment(of: item.window, from: item.initialFrame, to: actual)
            } catch {
                logger.error("Resizing a linked window failed: \(String(describing: error), privacy: .public)")
            }
        }

        placer.recordAdjustment(of: window, from: initialFrame, to: finalDraggedFrame)
    }

    /// Hides the previews without touching any window.
    func cancel() {
        preview.hide()
    }

    /// Where every window ends up for the dragged window's current frame: the dragged frame with each
    /// moved edge clamped to the line every linked window can follow, and each linked window's target.
    private func layout(draggedFrame: CGRect) -> (dragged: CGRect, isClamped: Bool, targets: [CGRect]) {
        var clampedLines: [SharedEdges.Edge: CGFloat] = [:]
        var isClamped = false
        var clampedDragged = draggedFrame

        for draggedEdge in draggedEdges {
            let proposed = draggedEdge.coordinate(in: draggedFrame)
            let clamped = SharedEdges.clampedLine(
                proposed,
                edge: draggedEdge,
                of: initialFrame,
                linked: linkedEdgesByDraggedEdge[draggedEdge] ?? [],
                gap: placer.gap
            )
            clampedLines[draggedEdge] = clamped
            if abs(clamped - proposed) > 0.5 {
                isClamped = true
                clampedDragged = SharedEdges.moving(
                    clampedDragged,
                    edge: draggedEdge,
                    draggedEdge: draggedEdge,
                    toLine: clamped,
                    gap: placer.gap
                )
            }
        }

        var targets: [CGRect] = []
        targets.reserveCapacity(linkedWindows.count)
        for item in linkedWindows {
            var target = item.initialFrame
            for (edge, draggedEdge) in item.edges {
                guard let line = clampedLines[draggedEdge] else { continue }
                target = SharedEdges.moving(target, edge: edge, draggedEdge: draggedEdge, toLine: line, gap: placer.gap)
            }
            targets.append(target)
        }

        return (dragged: clampedDragged, isClamped: isClamped, targets: targets)
    }
}
