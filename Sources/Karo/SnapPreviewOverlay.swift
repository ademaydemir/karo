import AppKit

/// The translucent rectangle that shows where a dragged window will land.
@MainActor
final class SnapPreviewOverlay {
    private let panel: NSPanel

    /// - Parameter tintAlpha: Strength of the accent tint; a fainter one marks a secondary preview.
    init(tintAlpha: CGFloat = 0.18) {
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
            tint: NSColor.controlAccentColor.withAlphaComponent(tintAlpha)
        )
    }

    /// - Parameter frame: Target frame in Accessibility coordinates.
    /// - Parameter fadeDuration: How long the appearance fade takes, in seconds. A slow fade
    ///   makes an overlay seem to fill in while its dwell runs.
    func show(_ frame: CGRect, fadeDuration: Double = 0.12) {
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
                context.duration = fadeDuration
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}
