import Foundation

/// Polls the Accessibility permission until it is granted.
///
/// macOS has no public notification for TCC changes, so polling is the reliable option.
/// Polling stops once permission is granted to keep idle CPU at zero; call `check()`
/// to re-evaluate later (for example when the menu opens).
@MainActor
public final class AccessibilityPermissionMonitor {
    public private(set) var isGranted: Bool
    private let onChange: @MainActor (Bool) -> Void
    private var pollingTask: Task<Void, Never>?

    public init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.isGranted = AccessibilityPermission.isGranted
        self.onChange = onChange
    }

    public func start() {
        guard !isGranted, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.check()
                if self.isGranted { break }
            }
            self?.pollingTask = nil
        }
    }

    public func check() {
        let granted = AccessibilityPermission.isGranted
        guard granted != isGranted else { return }
        isGranted = granted
        onChange(granted)
        if !granted { start() }
    }

    deinit {
        pollingTask?.cancel()
    }
}
