import AppKit

/// Background for Karo's floating UI (switcher, snap preview): Liquid Glass on macOS 26
/// and later, the HUD material before.
@MainActor
enum GlassSurface {
    static func make(cornerRadius: CGFloat, tint: NSColor? = nil, content: NSView? = nil) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.contentView = content
            return glass
        }

        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        if let tint {
            material.layer?.backgroundColor = tint.cgColor
        }
        if let content {
            content.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                content.topAnchor.constraint(equalTo: material.topAnchor),
                content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
        }
        return material
    }
}
