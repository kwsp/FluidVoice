import Foundation

@main
struct LocalNetworkTransportTests {
    static func main() async throws {
        let port = CommandLine.arguments[1]
        for value in ["http://localhost:\(port)/ok", "http://127.0.0.1:\(port)/ok", "http://[::1]:1234/v1"] {
            precondition(LocalOnlyNetworking.allows(value), value)
        }
        for value in ["http://localhost.evil.test", "http://localhost@evil.test", "http://10.1.2.3", "http://192.168.1.2", "http://127.1", "http://2130706433", "http://0.0.0.0", "http://%6cocalhost", "http://localhost:65536", "https://example.invalid"] {
            precondition(!LocalOnlyNetworking.allows(value), value)
        }
        let session = LocalOnlyNetworking.makeSession()
        defer { session.invalidateAndCancel() }
        for path in ["ok", "redirect", "redirect-external"] {
            guard let candidate = URL(string: "http://localhost:\(port)/\(path)") else {
                fatalError("Invalid loopback fixture URL")
            }
            let url = try LocalOnlyNetworking.validatedURL(candidate)
            precondition(url.host == "127.0.0.1")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("synthetic-private-text".utf8)
            request.setValue("Bearer synthetic-local-key", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            precondition((response as? HTTPURLResponse)?.statusCode == (path == "ok" ? 200 : 307))
        }
        print("PASS: local transport, destination validation, and redirect refusal")
    }
}
