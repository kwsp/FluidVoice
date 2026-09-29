@testable import FluidVoice_Debug
import Foundation
import XCTest

@MainActor
final class NetworkPrivacyTests: XCTestCase {
    func testImportedUpdateSettingCannotEnableChecks() {
        let defaults = UserDefaults.standard
        let key = "AutoUpdateCheckEnabled"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(true, forKey: key) // Simulate a persisted upstream preference.
        let settings = SettingsStore.shared
        XCTAssertFalse(settings.autoUpdateCheckEnabled)
        settings.autoUpdateCheckEnabled = true
        XCTAssertFalse(settings.autoUpdateCheckEnabled)
        XCTAssertFalse(settings.shouldCheckForUpdates())
    }

    func testUpdaterEntryPointsAreDisabled() async {
        let operations: [() async throws -> Void] = [
            { _ = try await SimpleUpdater.shared.checkForUpdate(owner: "example", repo: "disabled") },
            { try await SimpleUpdater.shared.checkAndUpdate(owner: "example", repo: "disabled") },
            { _ = try await SimpleUpdater.shared.fetchRecentReleaseNotes(owner: "example", repo: "disabled") },
            { _ = try await SimpleUpdater.shared.fetchRecentReleaseBuildOptions(owner: "example", repo: "disabled") },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("Upstream update entry point must be disabled")
            } catch SimpleUpdateError.disabledInFork {
                // Expected: no request, download, or installation is possible.
            } catch {
                XCTFail("Unexpected updater error: \(error)")
            }
        }
    }

    func testOnlyLiteralLoopbackOrLocalhostAreAllowed() throws {
        for address in ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1", "https://LOCALHOST:1234/v1"] {
            XCTAssertTrue(LocalOnlyNetworking.allows(address), address)
        }
        for address in ["https://api.openai.com/v1", "http://10.0.0.1/v1", "http://192.168.1.2/v1", "http://172.16.0.1/v1", "http://127.0.0.1.example.com", "http://localhost.example.com", "http://localhost@evil.example", "http://user:pass@127.0.0.1", "http://2130706433", "http://127.1", "http://0.0.0.0", "file:///tmp/test", "http://[::ffff:127.0.0.1]", "http://localhost:0", "http://localhost:65536", "http://%6cocalhost", "http://localhost/#fragment"] {
            XCTAssertFalse(LocalOnlyNetworking.allows(address), address)
        }
        let normalized = try LocalOnlyNetworking.validatedURL(XCTUnwrap(URL(string: "http://localhost:1234/v1")))
        XCTAssertEqual(normalized.host, "127.0.0.1")
    }

    func testImportedRemoteProviderCannotBuildInferenceRequest() {
        for streaming in [true, false] {
            for endpoint in ["https://api.openai.com/v1", "http://192.168.1.2:1234/v1", "https://example.com/responses"] {
                let config = LLMClient.Config(messages: [["role": "user", "content": "private transcript"]], model: "model", baseURL: endpoint, apiKey: "secret", streaming: streaming)
                XCTAssertThrowsError(try LLMClient.shared.buildRequest(config))
            }
        }
    }

    func testRemoteCatalogRejectedBeforeNetwork() async {
        do {
            _ = try await ModelRepository.shared.fetchModels(for: "custom", baseURL: "https://example.invalid/v1", apiKey: "secret")
            XCTFail("Remote catalog must be blocked")
        } catch {
            XCTAssertTrue(error is LocalOnlyNetworking.Failure)
        }
    }

    func testProviderSetupAndBuiltInListAreLocalOnly() {
        XCTAssertFalse(ProviderSetupDraft(name: "Remote", baseURL: "https://example.com/v1").isValid)
        XCTAssertTrue(ProviderSetupDraft(name: "Local", baseURL: "http://localhost:1234/v1").isValid)
        XCTAssertFalse(ModelRepository.shared.builtInProvidersList().contains { $0.id == "openai" })
        XCTAssertEqual(ModelRepository.shared.defaultBaseURL(for: "openai"), "")
    }

    func testLocalRequestKeepsPayloadAndNormalizesHost() throws {
        let config = LLMClient.Config(messages: [["role": "user", "content": "local transcript"]], model: "model", baseURL: "http://localhost:1234/v1", apiKey: "local-key", streaming: false)
        let request = try LLMClient.shared.buildRequest(config)
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-key")
        XCTAssertNotNil(request.httpBody)
    }

    func testLegacyTelemetryMigrationRemovesAllQueuesAndIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PrivacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["analytics-v2.sqlite3", "analytics-v2.sqlite3-wal", "analytics-v2.sqlite3-shm"] {
            try Data("old telemetry".utf8).write(to: directory.appendingPathComponent(name))
        }
        defaults.set("old-identity", forKey: "AnalyticsAnonymousInstallID")
        defaults.set(true, forKey: "ShareAnonymousAnalytics")
        defaults.set(123.0, forKey: "AnalyticsFirstOpenAt")
        try AnalyticsService.purgeLegacyTelemetry(directory: directory, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(defaults.object(forKey: "AnalyticsAnonymousInstallID"))
        XCTAssertFalse(defaults.bool(forKey: "ShareAnonymousAnalytics"))
        XCTAssertEqual(defaults.double(forKey: "AnalyticsFirstOpenAt"), 123.0)
        try AnalyticsService.purgeLegacyTelemetry(directory: directory, defaults: defaults)
    }

    func testImportedAnalyticsPreferenceCannotEnableCollection() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "ShareAnonymousAnalytics")
        defer { defaults.set(previous, forKey: "ShareAnonymousAnalytics") }
        defaults.set(true, forKey: "ShareAnonymousAnalytics")
        XCTAssertFalse(SettingsStore.shared.shareDetailedAnalytics)
        SettingsStore.shared.shareDetailedAnalytics = true
        XCTAssertFalse(SettingsStore.shared.shareDetailedAnalytics)
        XCTAssertFalse(defaults.bool(forKey: "ShareAnonymousAnalytics"))
    }
}
