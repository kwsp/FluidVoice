import Foundation

/// The sole HTTP transport for AI inference, model catalogs, and provider checks.
/// Model downloads and the (separately audited) updater do not use this transport.
nonisolated enum LocalOnlyNetworking {
    enum Failure: LocalizedError {
        case remoteEndpoint
        var errorDescription: String? {
            "Only AI servers on this Mac are allowed. Use localhost, 127.0.0.1, or [::1]."
        }
    }

    static func validatedURL(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              parts.fragment == nil,
              let host = parts.host?.lowercased(),
              ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host),
              parts.percentEncodedHost?.contains("%") == false
        else { throw Failure.remoteEndpoint }
        if let port = parts.port, !(1...65535).contains(port) { throw Failure.remoteEndpoint }
        // Never resolve even the name localhost via DNS or /etc/hosts.
        if host == "localhost" { parts.host = "127.0.0.1" }
        guard let result = parts.url else { throw Failure.remoteEndpoint }
        return result
    }

    static func allows(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (try? validatedURL(url)) != nil
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0, "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0]
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    static let session = makeSession()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            // Fail closed even for local redirects, so no payload or key is forwarded.
            completionHandler(nil)
        }
    }
}
