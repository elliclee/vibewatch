import Foundation

struct QuotaWindow: Codable, Equatable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?

    var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        return 100 - usedPercent
    }
    var durationLabel: String {
        guard let minutes = windowDurationMins else { return "窗口未知" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)天" }
        if minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }
    func awaitingReset(at date: Date, collectedAt: TimeInterval) -> Bool {
        guard let resetsAt else { return false }
        return collectedAt < resetsAt && date.timeIntervalSince1970 >= resetsAt
    }
}
struct QuotaBucket: Codable, Identifiable, Equatable, Sendable {
    let limitId: String
    let limitName: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    var id: String { limitId }
    var name: String {
        let label = limitName ?? limitId
        return label.lowercased() == "codex" ? "Codex" : label
    }
    // Presence describes the payload, not a subscription's entitlement to unlimited usage.
    // Keep an existing window with unknown percentage; only absent windows are omitted.
    var displayWindow: QuotaWindow? { primary ?? secondary }
}
struct QuotaSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let collectedAt: TimeInterval
    let ordinaryUsageAllowed: Bool?
    let buckets: [QuotaBucket]
    var usage: LocalUsage? = nil
    static let staleInterval: TimeInterval = 600
    var collectedDate: Date { Date(timeIntervalSince1970: collectedAt) }
    func isStale(at date: Date) -> Bool { date.timeIntervalSince1970 - collectedAt >= Self.staleInterval }
    func bucket(preferred: String?) -> QuotaBucket? {
        if let preferred, !preferred.isEmpty { return buckets.first { $0.limitId == preferred } }
        return buckets.first { $0.limitId == "codex" } ?? buckets.first
    }
    func status(at date: Date) -> String {
        if isStale(at: date) { return "数据已过期" }
        if ordinaryUsageAllowed == false { return "普通额度不可用" }
        if buckets.contains(where: { b in [b.primary, b.secondary].compactMap { $0 }.contains { $0.awaitingReset(at: date, collectedAt: collectedAt) } }) {
            return "重置待更新"
        }
        return "最近采集"
    }
    func transitionDates(after now: Date) -> [Date] {
        let resets = buckets.flatMap { [$0.primary?.resetsAt, $0.secondary?.resetsAt].compactMap { $0 } }
        let usageBoundary = usage.map { [$0.periodEnd] } ?? []
        return Array(Set([collectedAt + Self.staleInterval] + resets + usageBoundary))
            .filter { $0 > now.timeIntervalSince1970 }
            .sorted().map { Date(timeIntervalSince1970: $0) }
    }
}
struct UsageHour: Codable, Equatable, Sendable {
    let start: TimeInterval
    let tokens: Int64
}
struct LocalUsage: Codable, Equatable, Sendable {
    let periodStart: TimeInterval
    let periodEnd: TimeInterval
    let utcOffsetMinutes: Int
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let hours: [UsageHour]
    let source: String
    let partial: Bool
    let model: String?
    let reasoningEffort: String?
    let lastActivityAt: TimeInterval?
    func isCurrent(at date: Date) -> Bool { (periodStart..<periodEnd).contains(date.timeIntervalSince1970) }
    var peakHour: UsageHour? { hours.filter { $0.tokens > 0 }.max { $0.tokens < $1.tokens } }
    static func compact(_ count: Int64) -> String {
        if count >= 1_000_000_000 { return String(format: "%.1fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return String(count)
    }
}
struct SnapshotEnvelope: Codable, Equatable, Sendable {
    let snapshot: QuotaSnapshot
    let receivedAt: TimeInterval
}
struct Connection: Codable, Equatable, Sendable {
    let server: URL
    let token: String
    let deviceId: String
}
struct PairingRequest: Identifiable, Equatable {
    let server: URL
    let code: String
    var id: String { code }
    init(link: String) throws {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "vibewatch", components.host == "pair",
              let items = components.queryItems,
              items.filter({ $0.name == "server" }).count == 1,
              items.filter({ $0.name == "code" }).count == 1,
              let serverString = items.first(where: { $0.name == "server" })?.value,
              let server = URL(string: serverString), Self.validServer(server),
              let code = items.first(where: { $0.name == "code" })?.value,
              code.count == 64, code.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw ClientError.invalidPairing
        }
        self.server = server
        self.code = code
    }
    static func validServer(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return false }
        if url.scheme == "https" { return true }
        #if targetEnvironment(simulator)
        return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
        #else
        return false
        #endif
    }
}
enum ClientError: LocalizedError {
    case invalidPairing, unauthorized, noSnapshot, pairingExpired, invalidResponse, connectionChanged, storage, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidPairing: return "配对链接无效，请扫描 Mac 生成的二维码。"
        case .unauthorized: return "设备凭据已失效，请在 iPhone 重新配对。"
        case .noSnapshot: return "云端还没有额度，请先在 Mac 启动采集器。"
        case .pairingExpired: return "配对码已使用或过期，请在 Mac 重新生成。"
        case .invalidResponse: return "云端返回了无法识别的数据。"
        case .connectionChanged: return "连接配置已更新，请重试。"
        case .storage:
            #if os(watchOS)
            return "无法访问共享存储，请检查 App Group 和 Keychain 签名配置。"
            #else
            return "无法访问本机安全存储，请检查应用签名后重试。"
            #endif
        case .http(let status): return "服务暂时不可用（\(status)）。"
        }
    }
}
