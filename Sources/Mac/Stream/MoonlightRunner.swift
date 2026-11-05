import Foundation
import TrueCloudKit

/// Drives the upstream Moonlight macOS app through its command line
/// (`Moonlight pair <host> --pin N` and `Moonlight stream <host> <app> ...`).
final class MoonlightRunner {
    private var current: Process?

    /// Bundled copy (TrueCloud.app/Contents/Resources/Moonlight.app) wins over an installed one.
    static func locate() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Moonlight.app"),
            URL(fileURLWithPath: "/Applications/Moonlight.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Moonlight.app"),
        ].compactMap { $0 }
        return candidates
            .map { $0.appendingPathComponent("Contents/MacOS/Moonlight") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isRunning: Bool { current?.isRunning ?? false }

    /// True if Moonlight's saved hosts include `host` with a pinned server certificate.
    /// Running `pair` against an already-paired host pops an "already paired" dialog, so we skip it.
    static func isPaired(host: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.moonlight-stream.Moonlight") else { return false }
        let count = defaults.integer(forKey: "hosts.size")
        guard count > 0 else { return false }
        // Moonlight keeps a host's address and port in separate keys (`manualaddress` and `manualport`), and TrueCloud
        // tells accounts on one gateway apart by port. Compare both, or a second account on the same gateway name
        // would look already paired and its pairing would be skipped.
        let parts = host.split(separator: ":")
        let bare = parts.first.map(String.init) ?? host
        let port = parts.dropFirst().first.flatMap { Int($0) }
        return (1...count).contains { i in
            guard let cert = defaults.data(forKey: "hosts.\(i).srvcert"), !cert.isEmpty else { return false }
            return ["manual", "local", "remote"].contains { kind in
                guard let address = defaults.string(forKey: "hosts.\(i).\(kind)address"), address == host || address == bare else { return false }
                let stored = defaults.integer(forKey: "hosts.\(i).\(kind)port")
                return port == nil || stored == 0 || stored == port
            }
        }
    }

    /// Runs `pair` and waits for it to exit. Moonlight reports "already paired" as a failure,
    /// so callers should not treat a non-zero status as fatal — `stream` will fail clearly if unpaired.
    /// The Moonlight pair command often never exits after the host accepts the pairing, so once its
    /// last request (the pair challenge) has been sent and the host has had a moment, it is closed.
    func pair(host: String, pin: String) async throws -> Int32 {
        try await run(["pair", host, "--pin", pin], watcher: UnpairedWatcher(marker: "phrase=pairchallenge", grace: 6))
    }

    /// Runs `stream` and waits until the Moonlight window closes. If Moonlight reports that the host
    /// doesn't know this Mac (the rig was re-provisioned or its pairings were cleared), it is closed
    /// right away and `notPaired` is true so the caller can pair and try again.
    func stream(_ args: [String]) async throws -> (status: Int32, notPaired: Bool) {
        let watcher = UnpairedWatcher()
        let status = try await run(args, watcher: watcher)
        return (status, watcher.sawNotPaired)
    }

    func terminate() {
        current?.terminate()
        current = nil
    }

    private func run(_ args: [String], watcher: UnpairedWatcher? = nil) async throws -> Int32 {
        guard let executable = Self.locate() else {
            throw TCError.server("Moonlight was not found. Install it from moonlight-stream.org or with `brew install --cask moonlight`.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let watcher {
            // Moonlight prints "Redirecting log output to <file>" and then logs there. A dialog would
            // otherwise sit open waiting for a click, so the log is the only place to notice the problem.
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = pipe
            watcher.start(reading: pipe) { [weak process] in process?.terminate() }
        }
        current = process
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            process.terminate()
        }
    }
}


/// Spots Moonlight's "has not been paired" message in the log file it writes for a run.
private final class UnpairedWatcher: @unchecked Sendable {
    /// Text to look for in Moonlight's output and its log file, and how long to wait after seeing it.
    let marker: String
    let grace: TimeInterval
    init(marker: String = "has not been paired", grace: TimeInterval = 0) {
        self.marker = marker
        self.grace = grace
    }

    private let lock = NSLock()
    private var found = false
    private var timer: DispatchSourceTimer?

    var sawNotPaired: Bool { lock.withLock { found } }

    func start(reading pipe: Pipe, onFound: @escaping @Sendable () -> Void) {
        var logPath: String?
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            if let range = text.range(of: "/tmp/Moonlight-"), let end = text[range.lowerBound...].firstIndex(of: "\n") {
                logPath = String(text[range.lowerBound..<end]).trimmingCharacters(in: .whitespaces)
            }
            if let self, text.contains(self.marker) { self.hit(onFound) }
        }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, let path = logPath, let data = FileManager.default.contents(atPath: path) else { return }
            if String(decoding: data, as: UTF8.self).contains(self.marker) { self.hit(onFound) }
        }
        timer.resume()
        self.timer = timer
    }

    private func hit(_ onFound: @escaping @Sendable () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { found = true }
            return !found
        }
        if first {
            timer?.cancel()
            if grace > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + grace) { onFound() } } else { onFound() }
        }
    }
}
