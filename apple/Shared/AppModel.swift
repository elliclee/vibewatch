import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

@MainActor
final class AppModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var connection: Connection?
    @Published private(set) var envelope: SnapshotEnvelope?
    @Published private(set) var isRefreshing = false
    @Published var message: String?
    @Published var watchStatus = "等待手表连接"
    @Published var preferredBucket = ""
    private let store = SharedStore()
    private var session: WCSession?

    override init() {
        super.init()
        reloadLocal()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    private func reloadLocal() {
        do {
            #if os(iOS)
            try store.migrateLegacyPhoneStorage()
            #endif
            connection = try store.connection()
            envelope = connection.flatMap { store.cached(for: $0) }
            preferredBucket = store.preferredBucket
        } catch { message = error.localizedDescription }
    }
    func refresh() async {
        guard !isRefreshing else { return }
        reloadLocal()
        guard let current = connection else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let value = try await APIClient().fetch(current)
            guard connection == current, try store.connection() == current else { return }
            try store.save(value, for: current)
            envelope = store.cached(for: current)
            message = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            guard connection == current else { return }
            message = "\(error.localizedDescription) 已有数据会保留采集时间。"
        }
    }
    func pair(_ pairing: PairingRequest) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        do {
            let value = try await APIClient().redeem(pairing)
            try store.saveConnection(value)
            try store.clearCache()
            connection = value
            envelope = nil
            preferredBucket = ""
            store.preferredBucket = ""
            store.configurationRevision = Date().timeIntervalSince1970
            message = nil
            synchronizeWatch()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            message = error.localizedDescription
            isRefreshing = false
            return
        }
        isRefreshing = false
        await refresh()
    }
    func disconnect() {
        do {
            try store.saveConnection(nil)
            try store.clearCache()
            connection = nil
            envelope = nil
            store.configurationRevision = Date().timeIntervalSince1970
            synchronizeWatch()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { message = error.localizedDescription }
    }
    func selectBucket(_ id: String) {
        preferredBucket = id
        store.preferredBucket = id
        store.configurationRevision = Date().timeIntervalSince1970
        synchronizeWatch()
        WidgetCenter.shared.reloadAllTimelines()
    }
    func synchronizeWatch() {
        #if os(iOS)
        guard let session, session.activationState == .activated else {
            watchStatus = "配置将在手表连接后同步"
            return
        }
        guard session.isPaired else { watchStatus = "尚未配对 Apple Watch"; return }
        guard session.isWatchAppInstalled else { watchStatus = "请在手表安装 VibeWatch"; return }
        do {
            var context: [String: Any] = ["revision": store.configurationRevision,
                                         "preferredBucket": preferredBucket, "paired": connection != nil]
            if let connection { context["connection"] = try JSONEncoder().encode(connection) }
            try session.updateApplicationContext(context)
            watchStatus = "配置已交给系统，等待手表接收"
        } catch { watchStatus = "手表同步失败，可稍后重试" }
        #endif
    }
    private func receive(_ context: [String: Any]) async {
        #if os(watchOS)
        guard let revision = context["revision"] as? Double, revision >= store.configurationRevision,
              let paired = context["paired"] as? Bool else { return }
        do {
            let incoming: Connection?
            if paired {
                guard let data = context["connection"] as? Data else { throw ClientError.invalidResponse }
                incoming = try JSONDecoder().decode(Connection.self, from: data)
                guard let incoming, PairingRequest.validServer(incoming.server) else { throw ClientError.invalidPairing }
            } else { incoming = nil }
            let changed = try store.connection() != incoming
            try store.saveConnection(incoming)
            if changed { try store.clearCache() }
            store.preferredBucket = context["preferredBucket"] as? String ?? ""
            store.configurationRevision = revision
            reloadLocal()
            WidgetCenter.shared.reloadAllTimelines()
            await refresh()
        } catch { message = error.localizedDescription }
        #endif
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            #if os(iOS)
            self.synchronizeWatch()
            #else
            await self.receive(session.receivedApplicationContext)
            #endif
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in await self.receive(applicationContext) }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.synchronizeWatch() }
    }
    #endif
}
