import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.mir.SimpleNoteTaker", category: "subprocess")

/// Tracks every child `Process` we spawn so we can SIGTERM them on app quit.
/// macOS doesn't kill orphaned child processes when the parent exits — they
/// get re-parented to launchd and keep running, which is how a transcription
/// can keep pinning the GPU after the app is closed.
final class SubprocessRegistry: @unchecked Sendable {
    static let shared = SubprocessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.terminateAll()
        }
    }

    /// Registers `process` and wires its `terminationHandler` to auto-unregister
    /// on natural exit. Callers should call this before `process.run()`.
    func track(_ process: Process) {
        let id = ObjectIdentifier(process)
        lock.lock()
        processes[id] = process
        lock.unlock()
        let existing = process.terminationHandler
        process.terminationHandler = { [weak self] proc in
            self?.untrack(proc)
            existing?(proc)
        }
    }

    private func untrack(_ process: Process) {
        let id = ObjectIdentifier(process)
        lock.lock()
        processes.removeValue(forKey: id)
        lock.unlock()
    }

    private func terminateAll() {
        lock.lock()
        let active = Array(processes.values)
        lock.unlock()
        guard !active.isEmpty else { return }
        log.info("terminating \(active.count, privacy: .public) child process(es) on app quit")
        for proc in active where proc.isRunning {
            proc.terminate()
        }
    }
}
