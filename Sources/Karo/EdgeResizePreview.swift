import AppKit

/// Translucent, blurred glass overlays covering neighbouring windows while an edge is being
/// dragged, previewing the size they will take without making slow live Accessibility calls.
@MainActor
final class EdgeResizePreview {
    private var panels: [NSPanel] = []

    /// Displays translucent previews for each target frame in Accessibility coordinates.
    func show(_ frames: [CGRect]) {
        while panels.count < frames.count {
            panels.append(makePanel())
        }

        for (index, frame) in frames.enumerated() {
            let appKitFrame = ScreenGeometry.appKitFrame(fromAccessibility: frame)
            let panel = panels[index]
            if panel.isVisible {
                panel.setFrame(appKitFrame, display: true)
            } else {
                panel.setFrame(appKitFrame, display: false)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
        }

        if panels.count > frames.count {
            for index in frames.count..<panels.count {
                panels[index].orderOut(nil)
            }
        }
    }

    /// Orders all preview panels out.
    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        panel.contentView = GlassSurface.make(
            cornerRadius: 12,
            tint: NSColor.controlAccentColor.withAlphaComponent(0.12)
        )
        return panel
    }
}
