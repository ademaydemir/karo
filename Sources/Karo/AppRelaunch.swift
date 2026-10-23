import AppKit

/// Relaunches Karo from a given bundle location once the current process exits.
@MainActor
enum AppRelaunch {
    /// Starts Karo again from `url` once this process has exited, then quits.
    /// Waiting for the exit keeps two copies from running at the same time.
    static func relaunch(from url: URL = Bundle.main.bundleURL) {
        let path = url.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
