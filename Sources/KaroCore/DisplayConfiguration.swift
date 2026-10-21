import CoreGraphics

/// Identifies a set of connected displays and their arrangement, so window layouts can be
/// remembered per setup (e.g. "laptop alone" vs. "laptop + office monitor").
public enum DisplayConfiguration {
    public struct Descriptor: Equatable, Sendable {
        public var vendor: UInt32
        public var model: UInt32
        public var serial: UInt32
        public var frame: CGRect

        public init(vendor: UInt32, model: UInt32, serial: UInt32, frame: CGRect) {
            self.vendor = vendor
            self.model = model
            self.serial = serial
            self.frame = frame
        }
    }

    /// A stable key for the displays. Display IDs change between reconnects, so hardware
    /// identity is used instead, together with arrangement and resolution: the same monitor
    /// moved to the other side or at another resolution needs a different layout.
    public static func key(for displays: [Descriptor]) -> String {
        displays
            .map { display in
                let frame = display.frame.integral
                return "\(display.vendor)-\(display.model)-\(display.serial)"
                    + "@\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))"
            }
            .sorted()
            .joined(separator: "|")
    }
}

/// The last known window frames for each display configuration.
public struct LayoutMemory<WindowID: Hashable> {
    private var layouts: [String: [WindowID: CGRect]] = [:]
    /// Least recently recorded first.
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    public mutating func record(_ frames: [WindowID: CGRect], for configuration: String) {
        layouts[configuration] = frames
        order.removeAll { $0 == configuration }
        order.append(configuration)
        if order.count > capacity {
            layouts.removeValue(forKey: order.removeFirst())
        }
    }

    public func frames(for configuration: String) -> [WindowID: CGRect]? {
        layouts[configuration]
    }
}
