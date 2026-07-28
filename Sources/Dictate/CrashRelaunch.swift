//
//  CrashRelaunch.swift
//  Dictate
//
//  Come back after an abnormal exit.
//
//  Dictate lives in the menu bar and is used in bursts, so a crash is quiet: the
//  icon goes, nothing else changes, and the next time you hold the hotkey nothing
//  happens. macOS does not restart a login item that died, which means the app can
//  be gone for hours before anyone notices.
//
//  This is a backstop, not a fix — the crash it was written for is handled properly
//  in the audio path. It exists because "the app is missing" should cost seconds,
//  not a working session.
//

#if os(macOS)
import AppKit
import Darwin
import Synchronization
import os

enum CrashRelaunch {
    private static let log = Logger(subsystem: "Dictate", category: "CrashRelaunch")

    /// Marks a process that was started by this mechanism rather than by a person.
    static let marker = "--relaunched-after-crash"

    private static let historyKey = "dictate_crashRelaunches"
    /// More than this many crash-relaunches inside `loopWindow` means the app is failing
    /// at launch. Relaunching again would just spin, so we stop and leave it down.
    private static let loopLimit = 3
    private static let loopWindow: TimeInterval = 10 * 60
    /// A crash sooner than this after launch is a startup failure, not a session failure.
    private static let minimumUptime: TimeInterval = 60

    // Everything the handler touches is prepared here, at launch, because a signal handler
    // may not allocate, take locks, or call into Foundation. All it does is posix_spawn.
    private nonisolated(unsafe) static var spawnArgv: [UnsafeMutablePointer<CChar>?] = []
    private nonisolated(unsafe) static var launchedAt: UInt64 = 0
    private nonisolated(unsafe) static var timebaseNumer: UInt64 = 1
    private nonisolated(unsafe) static var timebaseDenom: UInt64 = 1
    private static let alreadyFiring = Atomic<Bool>(false)

    /// Arm the relaunch. Call once, as early in launch as possible.
    static func install() {
        recordThisLaunch()

        guard !isCrashLooping() else {
            log.error("crash-relaunched \(loopLimit, privacy: .public)x in the last 10 minutes — not arming, something is wrong at launch")
            return
        }
        // `open -n` needs a real .app; a `swift run` binary has nothing to reopen.
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }

        // Wait for this process to finish dying before reopening, or LaunchServices may
        // just wave at the corpse instead of starting anything.
        let command = "sleep 2; exec /usr/bin/open -n \"$0\" --args \(marker)"
        spawnArgv = ["/bin/sh", "-c", command, bundlePath, nil].map { $0.map { strdup($0) } ?? nil }

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        timebaseNumer = UInt64(timebase.numer)
        timebaseDenom = UInt64(timebase.denom)
        launchedAt = mach_absolute_time()

        NSSetUncaughtExceptionHandler { exception in
            CrashRelaunch.log.error("uncaught exception: \(exception.name.rawValue, privacy: .public) \(exception.reason ?? "", privacy: .public)")
            CrashRelaunch.fire()
        }

        for signalNumber in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(signalNumber) { received in
                CrashRelaunch.fire()
                // Hand the signal back to the default handler so macOS still writes the
                // crash report. Without it the failure would relaunch and vanish, which is
                // how a bug like this survives for months.
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }

    /// Spawn the replacement. Runs in signal context: no allocation, no Foundation, no locks.
    private nonisolated static func fire() {
        // An ObjC exception reaches us twice — once uncaught, then again as the SIGABRT it
        // turns into. One replacement is plenty.
        guard alreadyFiring.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged else { return }

        let elapsed = (mach_absolute_time() &- launchedAt) &* timebaseNumer / timebaseDenom
        guard Double(elapsed) / 1_000_000_000 > minimumUptime else { return }
        guard !spawnArgv.isEmpty else { return }

        var pid: pid_t = 0
        _ = spawnArgv.withUnsafeMutableBufferPointer { argv in
            posix_spawn(&pid, "/bin/sh", nil, nil, argv.baseAddress, nil)
        }
    }

    // MARK: - Crash-loop bookkeeping

    /// Note that this launch followed a crash, and forget ones old enough not to matter.
    private static func recordThisLaunch() {
        guard CommandLine.arguments.contains(marker) else { return }
        log.notice("started by crash relaunch")
        let cutoff = Date().addingTimeInterval(-loopWindow).timeIntervalSince1970
        var history = (UserDefaults.standard.array(forKey: historyKey) as? [Double] ?? [])
            .filter { $0 > cutoff }
        history.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    private static func isCrashLooping() -> Bool {
        let cutoff = Date().addingTimeInterval(-loopWindow).timeIntervalSince1970
        let history = (UserDefaults.standard.array(forKey: historyKey) as? [Double] ?? [])
            .filter { $0 > cutoff }
        return history.count >= loopLimit
    }
}
#endif
