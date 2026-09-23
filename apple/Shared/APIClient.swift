import Foundation

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct APIClient {
    var configuration: URLSessionConfiguration = .ephemeral
    private func request(server: URL, path: String, method: String, token: String? = nil, body: Data? = nil) async throws -> Data {
        guard PairingRequest.validServer(server) else { throw ClientError.invalidPairing }
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let config = configuration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw ClientError.unauthorized
        case 404: throw ClientError.noSnapshot
        case 410: throw ClientError.pairingExpired
        default: throw ClientError.http(http.statusCode)
        }
        guard data.count <= 65536 else { throw ClientError.invalidResponse }
        return data
    }
    func redeem(_ pairing: PairingRequest) async throws -> Connection {
        struct Result: Decodable { let token: String; let deviceId: String }
        let data = try await request(server: pairing.server, path: "v1/pairings/redeem", method: "POST",
                                     body: JSONEncoder().encode(["code": pairing.code]))
        let result = try JSONDecoder().decode(Result.self, from: data)
        guard result.token.count == 64, UUID(uuidString: result.deviceId) != nil else { throw ClientError.invalidResponse }
        return Connection(server: pairing.server, token: result.token, deviceId: result.deviceId)
    }
    func fetch(_ connection: Connection) async throws -> SnapshotEnvelope {
        let data = try await request(server: connection.server, path: "v1/snapshot", method: "GET", token: connection.token)
        let envelope = try JSONDecoder().decode(SnapshotEnvelope.self, from: data)
        guard envelope.snapshot.schemaVersion == 1, !envelope.snapshot.buckets.isEmpty,
              envelope.snapshot.collectedAt <= Date().timeIntervalSince1970 + 60 else { throw ClientError.invalidResponse }
        return envelope
    }
}
