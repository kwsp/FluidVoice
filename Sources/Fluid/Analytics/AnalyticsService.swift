import Foundation

/// Inert upstream compatibility facade. This fork never collects or sends analytics.
final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    func bootstrap() {
        Self.purgeLegacyTelemetry()
    }

    func setDetailedAnalyticsEnabled(_ enabled: Bool) {}

    func recordAppActivity() {}

    func recordUsage(
        mode: AnalyticsUsageMode,
        transcriptionModel: AnalyticsModelDescriptor? = nil,
        aiModel: AnalyticsModelDescriptor? = nil
    ) {}

    func recordModelUsage(
        role: AnalyticsModelRole,
        mode: AnalyticsUsageMode,
        descriptor: AnalyticsModelDescriptor
    ) {}

    func recordBetaDictationPerformance(
        fluidModel: AnalyticsFluidIntelligenceModel?,
        tokensPerSecond: Double?
    ) {}

    func recordInsertionLatency(
        path: AnalyticsInsertionPath,
        outcome: AnalyticsInsertionOutcome,
        requestMilliseconds: Int,
        readyMilliseconds: Int?,
        toggleStopMilliseconds: Int?
    ) {}

    func recordOnboardingStarted(origin: AnalyticsOnboardingOrigin) {}

    func recordOnboardingStepViewed(_ step: AnalyticsOnboardingStep, origin: AnalyticsOnboardingOrigin) {}

    func recordOnboardingStepCompleted(
        _ step: AnalyticsOnboardingStep,
        outcome: AnalyticsOnboardingOutcome,
        origin: AnalyticsOnboardingOrigin,
        completesFlow: Bool = false
    ) {}

    func recordOnboardingTryoutAttemptStarted(startMethod: AnalyticsOnboardingTryoutStartMethod) {}

    func recordOnboardingTryoutAttemptResult(
        outcome: AnalyticsOnboardingTryoutOutcome,
        failureStage: AnalyticsOnboardingTryoutFailureStage? = nil
    ) {}

    func finishOnboardingTryout(
        outcome: AnalyticsOnboardingTryoutOutcome,
        failureStage: AnalyticsOnboardingTryoutFailureStage? = nil
    ) {}

    func skipOnboardingTryout(origin: AnalyticsOnboardingOrigin) {}

    func recordModelDownloadStarted(
        id: UUID,
        descriptor: AnalyticsModelDescriptor,
        source: AnalyticsModelDownloadSource
    ) {}

    func recordModelDownloadFinished(
        id: UUID,
        descriptor: AnalyticsModelDescriptor,
        source: AnalyticsModelDownloadSource,
        outcome: AnalyticsModelDownloadOutcome,
        duration: TimeInterval?
    ) {}

    /// Retry on every launch: no migration marker may hide a failed deletion.
    private static func purgeLegacyTelemetry() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let directory = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FluidVoice")
            .appendingPathComponent("Analytics", isDirectory: true)
        do {
            try Self.purgeLegacyTelemetry(directory: directory, defaults: .standard)
        } catch {
            DebugLogger.shared.warning("Could not remove legacy telemetry: \(error.localizedDescription)", source: "Privacy")
        }
    }

    static func purgeLegacyTelemetry(directory: URL, defaults: UserDefaults) throws {
        defaults.removeObject(forKey: "AnalyticsAnonymousInstallID")
        defaults.set(false, forKey: "ShareAnonymousAnalytics")
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

}

final nonisolated class DetailedAnalyticsConsentGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    var currentGeneration: UInt64 {
        self.lock.withLock { self.generation }
    }

    func advance() -> UInt64 {
        self.lock.withLock {
            self.generation &+= 1
            return self.generation
        }
    }

    func accepts(_ generation: UInt64) -> Bool {
        self.lock.withLock { generation == self.generation }
    }
}
