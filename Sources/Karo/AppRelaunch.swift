import AppKit

/// Relaunches Karo from a given bundle location once the current process exits.
@MainActor
enum AppRelaunch {
    /// Starts Karo again from `url` once this process has exited, ejecting any disk image it
    /// ran from, then quits. Waiting for the exit keeps two copies from running at the same
    /// time; the disk image can only be ejected after Karo, which runs from it, has quit.
    /// - Parameter arguments: Launch arguments for the new instance, e.g. to open a window.
    static func relaunch(from url: URL = Bundle.main.bundleURL, ejecting diskImage: URL? = nil, arguments: [String] = []) {
        runAfterExit(ejecting: diskImage, opening: url, arguments: arguments)
    }

    /// Quits, then ejects `diskImage` once this process has exited, since Karo runs from it.
    static func quit(ejecting diskImage: URL?) {
        guard let diskImage else {
            NSApp.terminate(nil)
            return
        }
        runAfterExit(ejecting: diskImage, opening: nil)
    }

    /// Waits for this process to exit in a shell, then ejects and opens. Finder may hold the
    /// volume for a moment after Karo quits, so ejecting is retried.
    private static func runAfterExit(ejecting diskImage: URL?, opening url: URL?, arguments: [String] = []) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            disk="$1"; app="$2"; shift 2
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done
            if [ -n "$disk" ]; then
                for attempt in 1 2 3 4 5; do /usr/bin/hdiutil detach "$disk" -quiet && break; sleep 1; done
            fi
            [ -n "$app" ] && /usr/bin/open "$app" --args "$@"
            """,
            "karo-relaunch",
            diskImage?.path ?? "",
            url?.path ?? ""
        ] + arguments
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}
