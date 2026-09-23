import XCTest
@testable import VibeWatch

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var responseData = Data()
    static var observedRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observedRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class ClientTests: XCTestCase {
    private let connection = Connection(server: URL(string:"https://vibewatch.example")!, token: "test-only-reader-token", deviceId: "00000000-0000-0000-0000-000000000001")
    private func sample(at time: Double) -> SnapshotEnvelope {
        SnapshotEnvelope(snapshot: QuotaSnapshot(schemaVersion:1, collectedAt:time, ordinaryUsageAllowed:nil,
            buckets:[QuotaBucket(limitId:"codex",limitName:nil,primary:QuotaWindow(usedPercent:20,windowDurationMins:300,resetsAt:time+300),secondary:nil)]),receivedAt:time+1)
    }
    private func client(status: Int, data: Data = Data()) -> APIClient {
        StubProtocol.status = status
        StubProtocol.responseData = data
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(configuration: config)
    }
    func testReadRequestAuthenticationAndContract() async throws {
        let expected = sample(at:Date().timeIntervalSince1970 - 5)
        let value = try await client(status:200,data:JSONEncoder().encode(expected)).fetch(connection)
        XCTAssertEqual(value,expected)
        XCTAssertEqual(StubProtocol.observedRequest?.url?.path,"/v1/snapshot")
        XCTAssertEqual(StubProtocol.observedRequest?.httpMethod,"GET")
        XCTAssertEqual(StubProtocol.observedRequest?.value(forHTTPHeaderField:"Authorization"),"Bearer test-only-reader-token")
    }
    func testServerErrorsAndUnknownSchemaAreNotSuccessfulRefreshes() async throws {
        for status in [401,404,500] {
            do { _ = try await client(status:status).fetch(connection); XCTFail("HTTP error was accepted") }
            catch { XCTAssertTrue(error is ClientError) }
        }
        let invalid = Data("{\"snapshot\":{\"schemaVersion\":2,\"collectedAt\":1,\"buckets\":[]},\"receivedAt\":2}".utf8)
        do { _ = try await client(status:200,data:invalid).fetch(connection); XCTFail("Unknown schema was accepted") }
        catch { XCTAssertTrue(error is ClientError) }
    }
    func testPairingReceivesOnlyReaderConfiguration() async throws {
        let data = try JSONEncoder().encode(["token":String(repeating:"a",count:64),"deviceId":connection.deviceId])
        let pairing = try PairingRequest(link:"vibewatch://pair?server=https%3A%2F%2Fvibewatch.example&code=" + String(repeating:"b",count:64))
        let value = try await client(status:200,data:data).redeem(pairing)
        XCTAssertEqual(value.deviceId,connection.deviceId)
        XCTAssertEqual(value.server,connection.server)
        XCTAssertEqual(StubProtocol.observedRequest?.httpMethod,"POST")
        XCTAssertNil(StubProtocol.observedRequest?.value(forHTTPHeaderField:"Authorization"))
    }
    func testPrivateReleaseRetainsExistingPairingWithoutMigration() throws {
        guard SharedStore().scope == .legacyPhone else { throw XCTSkip("Shared-storage build") }
        let legacy = SharedStore(scope: .legacyPhone), store = SharedStore()
        guard try legacy.connection() == nil else { throw XCTSkip("Simulator is already paired") }
        defer { try? legacy.saveConnection(nil); try? legacy.clearCache() }
        try legacy.saveConnection(connection)
        try legacy.save(sample(at: 200), for: connection)
        try store.migrateLegacyPhoneStorage()
        XCTAssertEqual(try store.connection(), connection)
        XCTAssertEqual(store.cached(for: connection), sample(at: 200))
        XCTAssertEqual(try legacy.connection(), connection)
    }
    func testSharedKeychainAndCacheIsolation() throws {
        let store = SharedStore()
        // Never replace a developer's existing paired device in this simulator.
        guard try store.connection() == nil else { throw XCTSkip("Simulator is already paired") }
        defer { try? store.saveConnection(nil); try? store.clearCache() }
        try store.saveConnection(connection)
        XCTAssertEqual(try store.connection(),connection)
        try store.save(sample(at:200),for:connection)
        try store.save(sample(at:100),for:connection)
        XCTAssertEqual(store.cached(for:connection)?.snapshot.collectedAt,200)
        let cacheURL: URL
        if store.scope == .legacyPhone {
            cacheURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false).appendingPathComponent("VibeWatch/snapshot.json")
        } else {
            cacheURL = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID))
                .appendingPathComponent("snapshot.json")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
        let cacheText = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertFalse(cacheText.contains(connection.token), "Credentials must remain in Keychain")
        let other = Connection(server:URL(string:"https://other.example")!,token:"other-test-token",deviceId:connection.deviceId)
        XCTAssertNil(store.cached(for:other))
        try store.saveConnection(other)
        XCTAssertThrowsError(try store.save(sample(at:300),for:connection))
        try store.clearCache()
        XCTAssertNil(store.cached(for:other))
    }

    func testUpgradeMigratesPrivatePairingAndDoesNotResurrectAfterDisconnect() throws {
        guard SharedStore().scope == .shared else { throw XCTSkip("Phone widgets are deferred") }
        let store = SharedStore(), legacy = SharedStore(scope: .legacyPhone)
        guard try store.connection() == nil, try legacy.connection() == nil else { throw XCTSkip("Simulator is already paired") }
        let oldPreferred = legacy.preferredBucket, preferred = store.preferredBucket
        let oldRevision = legacy.configurationRevision, revision = store.configurationRevision
        defer {
            try? legacy.saveConnection(nil); try? store.saveConnection(nil)
            try? legacy.clearCache(); try? store.clearCache()
            legacy.preferredBucket = oldPreferred; store.preferredBucket = preferred
            legacy.configurationRevision = oldRevision; store.configurationRevision = revision
        }
        try legacy.saveConnection(connection)
        legacy.preferredBucket = "codex"
        legacy.configurationRevision = 1234
        try legacy.save(sample(at: 200), for: connection)
        XCTAssertNil(try store.connection(), "Shared access group must not match the legacy private item")
        try store.migrateLegacyPhoneStorage()
        XCTAssertEqual(try store.connection(), connection)
        XCTAssertEqual(store.cached(for: connection), sample(at: 200))
        XCTAssertEqual(store.preferredBucket, "codex")
        XCTAssertEqual(store.configurationRevision, 1234)
        XCTAssertNil(try legacy.connection())
        XCTAssertNil(legacy.cached(for: connection))
        try store.saveConnection(nil); try store.clearCache()
        try store.migrateLegacyPhoneStorage()
        XCTAssertNil(try store.connection(), "Disconnect must not restore a build 6 credential")
    }

    func testMigrationDoesNotOverwriteNewSharedPairing() throws {
        guard SharedStore().scope == .shared else { throw XCTSkip("Phone widgets are deferred") }
        let store = SharedStore(), legacy = SharedStore(scope: .legacyPhone)
        guard try store.connection() == nil, try legacy.connection() == nil else { throw XCTSkip("Simulator is already paired") }
        defer { try? legacy.saveConnection(nil); try? store.saveConnection(nil); try? legacy.clearCache(); try? store.clearCache() }
        let other = Connection(server: URL(string: "https://other.example")!, token: "new-test-token", deviceId: connection.deviceId)
        try legacy.saveConnection(connection)
        try legacy.save(sample(at: 200), for: connection)
        try store.saveConnection(other)
        try store.save(sample(at: 300), for: other)
        try store.migrateLegacyPhoneStorage()
        XCTAssertEqual(try store.connection(), other)
        XCTAssertEqual(store.cached(for: other), sample(at: 300))
        XCTAssertNil(try legacy.connection())
        XCTAssertNil(store.cached(for: connection))
    }

}
