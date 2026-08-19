// zac-watch-macos — macOS appearance watcher for zsh-appearance-control.
//
// Version: 2.2.1
//
// A tiny launchd agent. It listens for the system dark/light change and calls
// `appearance-dispatch dispatch <0|1>`. It knows nothing about the plugin, the
// cache file, tmux, or ZAC_IO_CMD: everything beyond "the appearance changed"
// is the dispatcher's business.
//
// Design notes:
//   - Foundation only. No AppKit, no NSApplication, no bundle, no Dock icon.
//   - The notification is only a trigger; the value is always re-read from the
//     user defaults, because the notification can arrive a moment before the
//     defaults are updated, and it can arrive in bursts.
//   - Dispatches are serialized on one queue and debounced, so a burst of
//     notifications produces exactly one dispatch.
//   - The whole environment is inherited by the child process. That is how
//     ZAC_IO_CMD, ZAC_CACHE_DIR and PATH reach the dispatcher: they are set in
//     the launchd plist, not parsed here.

import Foundation

let zacWatchVersion = "2.2.1"

let programName = "zac-watch-macos"

// MARK: - Logging

// launchd captures stdout/stderr (StandardOutPath / StandardErrorPath).
// Timestamps make the log usable when several changes happen in a day.
func logLine(_ message: String, toStderr: Bool = false) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(programName): \(message)\n"
    if toStderr {
        FileHandle.standardError.write(Data(line.utf8))
    } else {
        FileHandle.standardOutput.write(Data(line.utf8))
        // Unbuffered enough for a log file: stdout to a file is block-buffered,
        // and this process can live for weeks.
        fflush(stdout)
    }
}

func die(_ message: String, status: Int32 = 1) -> Never {
    logLine(message, toStderr: true)
    exit(status)
}

// MARK: - Ground truth on the OS side

/// Reads the current OS appearance.
///
/// `AppleInterfaceStyle` is absent in light mode and `"Dark"` in dark mode.
/// The synchronize call matters: without it a long-lived process can keep
/// serving the value it cached at launch.
func systemIsDark() -> Bool {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    let value = CFPreferencesCopyAppValue(
        "AppleInterfaceStyle" as CFString,
        kCFPreferencesAnyApplication
    ) as? String
    return value?.lowercased().hasPrefix("dark") ?? false
}

// MARK: - Configuration

func intEnv(_ name: String, default fallback: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Int(raw), value >= 0
    else { return fallback }
    return value
}

/// Locates `appearance-dispatch`.
///
/// `ZAC_DISPATCH` wins; otherwise the name is looked up in `PATH`, which is
/// only useful for interactive testing — a launchd agent should always set the
/// variable to an absolute path.
func resolveDispatcher() -> String {
    let env = ProcessInfo.processInfo.environment
    let fm = FileManager.default

    if let path = env["ZAC_DISPATCH"], !path.isEmpty {
        let expanded = (path as NSString).expandingTildeInPath
        guard fm.isExecutableFile(atPath: expanded) else {
            die("ZAC_DISPATCH is not an executable file: \(expanded)", status: 2)
        }
        return expanded
    }

    for dir in (env["PATH"] ?? "").split(separator: ":") where !dir.isEmpty {
        let candidate = "\(dir)/appearance-dispatch"
        if fm.isExecutableFile(atPath: candidate) { return candidate }
    }

    die(
        """
        ZAC_DISPATCH is not set and appearance-dispatch was not found in PATH.
        Set ZAC_DISPATCH to the absolute path of \
        zsh-appearance-control/bin/appearance-dispatch.
        """,
        status: 2
    )
}

// MARK: - Watcher

final class Watcher {
    private let dispatcherPath: String
    private let debounce: DispatchTimeInterval
    private let retryDelay: DispatchTimeInterval?
    private let queue = DispatchQueue(label: "works.zac.watch.dispatch")

    private var pending: DispatchWorkItem?
    /// Last value the dispatcher accepted. Only used to skip redundant forks;
    /// the dispatcher is idempotent on its own.
    private var lastApplied: Bool?
    private var retryScheduled = false

    init(dispatcherPath: String, debounceMs: Int, retryMs: Int) {
        self.dispatcherPath = dispatcherPath
        self.debounce = .milliseconds(debounceMs)
        self.retryDelay = retryMs > 0 ? .milliseconds(retryMs) : nil
    }

    /// Coalesces triggers: only the last one within the debounce window runs.
    func schedule(reason: String) {
        queue.async { [self] in
            pending?.cancel()
            let item = DispatchWorkItem { [self] in
                pending = nil
                run(isDark: systemIsDark(), reason: reason, isRetry: false)
            }
            pending = item
            queue.asyncAfter(deadline: .now() + debounce, execute: item)
        }
    }

    /// Runs one dispatch synchronously. Must be called on `queue`.
    private func run(isDark: Bool, reason: String, isRetry: Bool) {
        if lastApplied == isDark && !isRetry {
            logLine("\(reason): already \(isDark ? "dark" : "light"), skipped")
            return
        }

        let status = runDispatcher(dispatcherPath, isDark: isDark)
        if status == 0 {
            lastApplied = isDark
            retryScheduled = false
            logLine("\(reason): dispatched \(isDark ? "1 (dark)" : "0 (light)")")
            return
        }

        // A failed dispatch wrote nothing and signalled nobody (see the
        // ZAC_IO_CMD contract), so retrying is safe. Retry once only: a script
        // that is genuinely broken must not turn into a loop.
        logLine("\(reason): dispatcher exited \(status)", toStderr: true)
        lastApplied = nil
        guard let retryDelay, !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + retryDelay) { [self] in
            run(isDark: systemIsDark(), reason: "\(reason) (retry)", isRetry: true)
        }
    }

    func start() {
        // Ignore the default disposition first; the dispatch source owns them.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        for sig in [SIGTERM, SIGINT] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                logLine("received signal \(sig), exiting")
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: nil
        ) { [self] _ in
            schedule(reason: "notification")
        }

        // Sync at startup: launchd starts us at login and after a crash, and the
        // appearance may have changed while we were not running.
        schedule(reason: "startup")

        logLine("watching (dispatcher: \(dispatcherPath))")
        CFRunLoopRun()
    }

    private var signalSources: [DispatchSourceSignal] = []
}

/// Spawns the dispatcher and waits for it. The environment is inherited as is.
func runDispatcher(_ path: String, isDark: Bool) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["dispatch", isDark ? "1" : "0"]
    do {
        try process.run()
    } catch {
        logLine("cannot run \(path): \(error.localizedDescription)", toStderr: true)
        return 127
    }
    process.waitUntilExit()
    return process.terminationStatus
}

// MARK: - Entry point

func usage() {
    print("""
    usage: \(programName) [--once|--print|--version|--help]

      (no option)  Watch for appearance changes until killed (launchd mode).
      --once       Dispatch the current appearance once, then exit with the
                   dispatcher's exit status.
      --print      Print the current appearance as 0 or 1, then exit.

    Environment:
      ZAC_DISPATCH           Absolute path to bin/appearance-dispatch (required
                             unless it is in PATH).
      ZAC_WATCH_DEBOUNCE_MS  Coalescing window, default 150.
      ZAC_WATCH_RETRY_MS     Delay before the single retry of a failed dispatch,
                             default 3000. 0 disables the retry.

    Everything else in the environment (ZAC_IO_CMD, ZAC_CACHE_DIR, PATH, …) is
    passed through to the dispatcher unchanged.
    """)
}

switch CommandLine.arguments.dropFirst().first {
case .none:
    let watcher = Watcher(
        dispatcherPath: resolveDispatcher(),
        debounceMs: intEnv("ZAC_WATCH_DEBOUNCE_MS", default: 150),
        retryMs: intEnv("ZAC_WATCH_RETRY_MS", default: 3000)
    )
    watcher.start()

case "--once":
    exit(runDispatcher(resolveDispatcher(), isDark: systemIsDark()))

case "--print":
    print(systemIsDark() ? "1" : "0")

case "--version":
    print("\(programName) \(zacWatchVersion)")

case "--help", "-h":
    usage()

case .some(let arg):
    logLine("unknown argument: \(arg)", toStderr: true)
    usage()
    exit(2)
}
