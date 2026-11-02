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
        return (1...count).contains { i in
            let addresses = ["manualaddress", "localaddress", "remoteaddress"]
                .compactMap { defaults.string(forKey: "hosts.\(i).\($0)") }
            let cert = defaults.data(forKey: "hosts.\(i).srvcert")
            let bare = host.split(separator: ":").first.map(String.init) ?? host
            return addresses.contains { $0 == host || $0 == bare } && !(cert?.isEmpty ?? true)
        }
    }

    /// Runs `pair` and waits for it to exit. Moonlight reports "already paired" as a failure,
    /// so callers should not treat a non-zero status as fatal — `stream` will fail clearly if unpaired.
    func pair(host: String, pin: String) async throws -> Int32 {
        try await run(["pair", host, "--pin", pin])
    }

    /// Runs `stream` and waits until the Moonlight window closes.
    func stream(_ args: [String]) async throws -> Int32 {
        try await run(args)
    }

    func terminate() {
        current?.terminate()
        current = nil
    }

    private func run(_ args: [String]) async throws -> Int32 {
        guard let executable = Self.locate() else {
            throw TCError.server("Moonlight was not found. Install it from moonlight-stream.org or with `brew install --cask moonlight`.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
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
