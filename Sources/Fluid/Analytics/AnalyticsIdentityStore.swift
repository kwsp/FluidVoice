import Foundation

/// Persists the anonymous analytics ID across app updates.
final class AnalyticsIdentityStore {
    nonisolated static let shared = AnalyticsIdentityStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let anonymousInstallID = "AnalyticsAnonymousInstallID"
        static let firstOpenAt = "AnalyticsFirstOpenAt"
    }

    private init() {}

    /// Returns whether this is the first recorded launch.
    @discardableResult
    nonisolated func ensureFirstOpenRecorded() -> Bool {
        if self.defaults.object(forKey: Keys.firstOpenAt) == nil {
            self.defaults.set(Date().timeIntervalSince1970, forKey: Keys.firstOpenAt)
            return true
        }
        return false
    }

    nonisolated var firstOpenAt: Date? {
        let timestamp = self.defaults.double(forKey: Keys.firstOpenAt)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
}
