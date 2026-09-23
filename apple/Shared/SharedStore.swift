import Foundation
import Security

struct SharedStore {
    enum Scope { case shared, legacyPhone }
    var scope: Scope = Bundle.main.object(forInfoDictionaryKey: "VibeWatchPrivatePhoneStorage") as? Bool == true ? .legacyPhone : .shared
    static var groupID: String { Bundle.main.object(forInfoDictionaryKey: "VibeWatchAppGroup") as? String ?? "group.dev.vibewatch.shared" }
    private var defaults: UserDefaults {
        scope == .shared ? UserDefaults(suiteName: Self.groupID)! : .standard
    }
    var preferredBucket: String {
        get { defaults.string(forKey: "preferredBucket") ?? "" }
        nonmutating set { defaults.set(newValue, forKey: "preferredBucket") }
    }
    var configurationRevision: Double {
        get { defaults.double(forKey: "configurationRevision") }
        nonmutating set { defaults.set(newValue, forKey: "configurationRevision") }
    }
    private var keychainQuery: [String: Any] {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "VibeWatch", kSecAttrAccount as String: "connection"]
        var query = base
        let key = scope == .shared ? "VibeWatchKeychainGroup" : "VibeWatchLegacyKeychainGroup"
        if let group = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
    func connection() throws -> Connection? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ClientError.storage }
        return try JSONDecoder().decode(Connection.self, from: data)
    }
    func saveConnection(_ connection: Connection?) throws {
        guard let connection else {
            let status = SecItemDelete(keychainQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.storage }
            return
        }
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(keychainQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError.storage }
    }
    private func cacheURL() throws -> URL {
        let container: URL
        if scope == .shared {
            guard let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID) else { throw ClientError.storage }
            container = shared
        } else {
            container = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            .appendingPathComponent("VibeWatch", isDirectory: true)
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        }
        return container.appendingPathComponent("snapshot.json")
    }
    // Called only by the iPhone app. Extensions never search another access group.
    // Remove the old credential only after the shared write succeeds; never overwrite
    // an already-paired shared connection, and never resurrect it after disconnect.
    func migrateLegacyPhoneStorage() throws {
        guard scope == .shared else { return }
        let legacy = SharedStore(scope: .legacyPhone)
        if let old = try legacy.connection() {
            if try connection() == nil {
                try saveConnection(old)
                preferredBucket = legacy.preferredBucket
                configurationRevision = legacy.configurationRevision
                if let envelope = legacy.cached(for: old) { try save(envelope, for: old) }
            }
            try legacy.saveConnection(nil)
        }
        try legacy.clearCache()
    }
    private struct Cache: Codable {
        let server: URL
        let deviceId: String
        let envelope: SnapshotEnvelope
    }
    func cached(for connection: Connection) -> SnapshotEnvelope? {
        guard let url = try? cacheURL(), let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.server == connection.server, cache.deviceId == connection.deviceId else { return nil }
        return cache.envelope
    }
    func save(_ envelope: SnapshotEnvelope, for connection: Connection) throws {
        let url = try cacheURL()
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { url in
            do {
                guard try self.connection() == connection else { throw ClientError.connectionChanged }
                if let current = cached(for: connection), current.snapshot.collectedAt > envelope.snapshot.collectedAt { return }
                let data = try JSONEncoder().encode(Cache(server: connection.server, deviceId: connection.deviceId, envelope: envelope))
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { writeError = error }
        }
        if let error = coordinatorError ?? writeError as NSError? { throw error }
    }
    func clearCache() throws {
        let url = try cacheURL()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
