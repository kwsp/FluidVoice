import Foundation

/// Never fall back from SpeechAnalyzer to a different recognition service.
final class UnavailableOnDeviceSpeechProvider: TranscriptionProvider {
    var name: String { "Apple Speech Analyzer (requires macOS 26)" }
    var isAvailable: Bool { false }
    var isReady: Bool { false }

    private var error: NSError {
        NSError(domain: "OnDeviceSpeech", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Apple Speech Analyzer requires macOS 26. Choose a downloaded STT model.",
        ])
    }

    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
        throw self.error
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        throw self.error
    }
}
