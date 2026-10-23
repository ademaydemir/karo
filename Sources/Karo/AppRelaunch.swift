import AppKit

/// Relaunches Karo from a given bundle location once the current process exits.
@MainActor
enum AppRelaunch {
    /// Starts Karo again from `url` once this process has exited, ejecting any disk image it
    /// ran from, then quits. Waiting for the exit keeps two copies from running at the same
    /// time; the disk image can only be ejected after Karo, which runs from it, has quit.
    static func relaunch(from url: URL = Bundle.main.bundleURL, ejecting diskImage: URL? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; [ -n \"$1\" ] && /usr/bin/hdiutil detach \"$1\" -quiet; /usr/bin/open \"$0\"",
            url.path,
            diskImage?.path ?? ""
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
