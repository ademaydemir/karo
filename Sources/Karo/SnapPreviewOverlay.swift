import AppKit

/// The translucent rectangle that shows where a dragged window will land.
@MainActor
final class SnapPreviewOverlay {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
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

        // A light accent tint keeps the target readable over busy window content.
        panel.contentView = GlassSurface.make(
            cornerRadius: 14,
            tint: NSColor.controlAccentColor.withAlphaComponent(0.18)
        )
    }

    /// - Parameter frame: Target frame in Accessibility coordinates.
    func show(_ frame: CGRect) {
        let appKitFrame = ScreenGeometry.appKitFrame(fromAccessibility: frame)
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(appKitFrame, display: true)
            }
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

    func hide() {
        panel.orderOut(nil)
    }
}
