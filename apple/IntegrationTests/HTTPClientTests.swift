import XCTest
@testable import VibeWatch

final class HTTPClientTests: XCTestCase {
    func testLocalWorkerPairReadAndRevoke() async throws {
        guard ProcessInfo.processInfo.environment["VIBEWATCH_HTTP_TEST"] == "1" else {
            throw XCTSkip("Run the VibeWatchHTTPTests scheme with cloud npm run test:server")
        }
        let server = URL(string:"http://127.0.0.1:8791")!
        let upload = "http-fixture-upload-token-not-a-real-secret"
        var create = URLRequest(url:server.appendingPathComponent("v1/pairings"))
        create.httpMethod = "POST"
        create.setValue("Bearer \(upload)",forHTTPHeaderField:"Authorization")
        create.setValue("application/json",forHTTPHeaderField:"Content-Type")
        create.httpBody = Data("{\"name\":\"Apple HTTP test\"}".utf8)
        let (data, response) = try await URLSession.shared.data(for:create)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,201)
        struct Pair:Decodable {let code:String}
        let code = try JSONDecoder().decode(Pair.self,from:data).code
        let pairing = try PairingRequest(link:"vibewatch://pair?server=http%3A%2F%2F127.0.0.1%3A8791&code="+code)
        let client = APIClient()
        let connection = try await client.redeem(pairing)
        let envelope = try await client.fetch(connection)
        XCTAssertEqual(envelope.snapshot.buckets.count,2)
        XCTAssertEqual(envelope.snapshot.buckets[0].primary?.remaining,72)
        XCTAssertNil(envelope.snapshot.buckets[1].primary)
        let store = SharedStore()
        guard try store.connection() == nil else { throw XCTSkip("Simulator already paired") }
        defer {try? store.saveConnection(nil);try? store.clearCache()}
        try store.saveConnection(connection)
        try store.save(envelope,for:connection)
        XCTAssertEqual(store.cached(for:connection),envelope)
        var revoke = URLRequest(url:server.appendingPathComponent("v1/devices/"+connection.deviceId))
        revoke.httpMethod = "DELETE"
        revoke.setValue("Bearer \(upload)",forHTTPHeaderField:"Authorization")
        let (_, revoked) = try await URLSession.shared.data(for:revoke)
        XCTAssertEqual((revoked as? HTTPURLResponse)?.statusCode,200)
        do {_ = try await client.fetch(connection);XCTFail("Revoked token accepted")}
        catch ClientError.unauthorized {} // Cached data must still exist after a failed fetch.
        XCTAssertEqual(store.cached(for:connection),envelope)
    }
}
