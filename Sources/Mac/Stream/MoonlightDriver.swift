import Foundation

/// macOS stream driver: pairs and streams through the Moonlight CLI.
@MainActor
final class MoonlightDriver: StreamDriver {
    private let moonlight = MoonlightRunner()

    func run(host: String, settings: StreamSettings, session: SessionService) async throws {
        let skippedPairing = MoonlightRunner.isPaired(host: host)
        if skippedPairing {
            Log.info("[moonlight] \(host) already paired, skipping pair")
        } else {
            try await pair(host: host, session: session)
        }
        try Task.checkCancellation()

        session.markStreaming()
        let args = settings.moonlightStreamArgs(host: host)
        Log.info("[moonlight] \(args.joined(separator: " "))")
        var result = try await moonlight.stream(args)
        Log.info("[moonlight] stream exited with \(result.status)")

        // The rig no longer knows this Mac (re-provisioned, or "Unpair devices"): pair and retry once.
        if result.notPaired, !Task.isCancelled {
            Log.info("[moonlight] host says it isn't paired, pairing and retrying")
            session.markPairing()
            try await pair(host: host, session: session)
            try Task.checkCancellation()
            session.markStreaming()
            result = try await moonlight.stream(args)
            Log.info("[moonlight] stream exited with \(result.status)")
        }
    }

    func stop() {
        moonlight.terminate()
    }

    /// Starts `Moonlight pair` with a random PIN and, in parallel, hands that PIN to Sunshine through
    /// TrueCloud's dashboard until it is accepted.
    private func pair(host: String, session: SessionService) async throws {
        let pin = String(format: "%04d", Int.random(in: 1000...9999))
        let submitPin = Task {
            try await Task.sleep(for: .seconds(2))
            for _ in 0..<10 where !Task.isCancelled {
                if await session.submitPairingPIN(pin) { return }
                try await Task.sleep(for: .seconds(3))
            }
        }
        defer { submitPin.cancel() }
        Log.info("[moonlight] pair \(host)")
        let status = try await moonlight.pair(host: host, pin: pin)
        Log.info("[moonlight] pair exited with \(status) (non-zero is expected if already paired)")
    }
}
