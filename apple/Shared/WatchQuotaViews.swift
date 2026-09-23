import SwiftUI

/// Watch and complication presentation, independent of networking and device chrome.
enum QuotaAppearance {
    static func color(_ remaining: Double?, secondary: Bool = false, stale: Bool = false) -> Color {
        guard !stale, let remaining else { return .secondary }
        if remaining < 10 { return .red }
        if remaining < 20 { return .orange }
        return secondary ? .blue : .green
    }
    static func symbol(_ window: QuotaWindow?) -> String {
        (window?.windowDurationMins ?? 0) >= 1440 ? "calendar" : "clock"
    }
}

struct QuotaBar: View {
    let remaining: Double?
    let tint: Color
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                if let remaining {
                    Capsule().fill(tint).frame(width: geometry.size.width * max(0, min(100, remaining)) / 100)
                }
            }
        }.frame(height: height).accessibilityHidden(true)
    }
}

struct QuotaResetLabel: View {
    let window: QuotaWindow?
    let collectedAt: TimeInterval
    let date: Date
    var compact = false
    var body: some View {
        Group {
            if let window, window.awaitingReset(at: date, collectedAt: collectedAt) {
                Text(compact ? "待更新" : "重置待更新").foregroundStyle(.orange)
            } else if let reset = window?.resetsAt {
                HStack(spacing: 3) {
                    if compact { Image(systemName: "arrow.clockwise") }
                    if Calendar.current.isDate(date, inSameDayAs: Date(timeIntervalSince1970: reset)) {
                        Text(Date(timeIntervalSince1970: reset), format: .dateTime.hour().minute())
                    } else if compact {
                        Text(Date(timeIntervalSince1970: reset), format: .dateTime.month(.defaultDigits).day())
                    } else {
                        Text(Date(timeIntervalSince1970: reset), format: .dateTime.month(.defaultDigits).day().hour().minute())
                    }
                    if !compact { Text("重置") }
                }
            } else { Text(compact ? "未知" : "重置时间未知") }
        }.lineLimit(1).minimumScaleFactor(0.8)
    }
}

struct WatchQuotaRow: View {
    let title: String
    let window: QuotaWindow?
    let snapshot: QuotaSnapshot
    let date: Date
    var secondary = false
    @ScaledMetric(relativeTo: .title2) private var numberSize = 25
    private var tint: Color {
        QuotaAppearance.color(window?.remaining, secondary: secondary, stale: snapshot.isStale(at: date))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: QuotaAppearance.symbol(window)).font(.caption).foregroundStyle(tint)
                Text(window?.durationLabel ?? title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 2)
                if let remaining = window?.remaining, remaining < 20 {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(tint)
                }
                Text(window?.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.75)
            }
            QuotaBar(remaining: window?.remaining, tint: tint)
            QuotaResetLabel(window: window, collectedAt: snapshot.collectedAt, date: date)
                .font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct WatchQuotaOverview: View {
    let snapshot: QuotaSnapshot
    let bucket: QuotaBucket
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(bucket.name).font(.headline).lineLimit(1)
                Spacer(minLength: 2)
                Text("剩余额度").font(.caption2).foregroundStyle(.secondary)
            }
            if let primary = bucket.primary {
                WatchQuotaRow(title: "主窗口", window: primary, snapshot: snapshot, date: date)
            }
            if let secondary = bucket.secondary {
                WatchQuotaRow(title: "次窗口", window: secondary, snapshot: snapshot, date: date, secondary: true)
            }
            if bucket.displayWindow == nil {
                Text("暂无额度数据").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: snapshot.isStale(at: date) ? "clock.badge.exclamationmark" : "clock")
                if snapshot.isStale(at: date) {
                    Text("缓存已过期")
                    Spacer(minLength: 0)
                } else if snapshot.ordinaryUsageAllowed == false {
                    Text("普通额度不可用")
                } else { Text("采集于") }
                if snapshot.ordinaryUsageAllowed != false || snapshot.isStale(at: date) {
                    Text(snapshot.collectedDate, style: .time).monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(snapshot.isStale(at: date) || snapshot.ordinaryUsageAllowed == false ? .orange : .secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

struct RectangularQuotaView: View {
    let snapshot: QuotaSnapshot
    let bucket: QuotaBucket
    let date: Date
    var unavailable = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(bucket.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("剩余").font(.system(size: 8))
                Spacer(minLength: 0)
                if snapshot.isStale(at: date) { Text("已过期").foregroundStyle(.orange) }
                else if unavailable { Text("缓存").foregroundStyle(.orange) }
                else if snapshot.ordinaryUsageAllowed == false { Text("不可用").foregroundStyle(.orange) }
                else { Image(systemName: "clock") }
                Text(snapshot.collectedDate, style: .time).monospacedDigit()
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            if let primary = bucket.primary { row(primary, title: "主", secondary: false) }
            if let secondary = bucket.secondary { row(secondary, title: "次", secondary: true) }
            if bucket.displayWindow == nil {
                Text("暂无额度数据").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func row(_ window: QuotaWindow?, title: String, secondary: Bool) -> some View {
        let tint = QuotaAppearance.color(window?.remaining, secondary: secondary, stale: snapshot.isStale(at: date))
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(window?.durationLabel ?? title).font(.system(size: 10)).lineLimit(1)
                Text(window?.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                Spacer(minLength: 0)
                QuotaResetLabel(window: window, collectedAt: snapshot.collectedAt, date: date, compact: true)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.minimumScaleFactor(0.8)
            SegmentedQuotaBar(remaining: window?.remaining, tint: tint, height: 3)
        }.accessibilityElement(children: .combine)
    }
}

struct CircularQuotaView: View {
    let snapshot: QuotaSnapshot?
    let bucket: QuotaBucket?
    let date: Date
    var unavailable = false
    var paired = false
    private var window: QuotaWindow? { bucket?.displayWindow }
    private var label: String {
        guard let snapshot else { return unavailable ? "离线" : paired ? "待采集" : "待配对" }
        if snapshot.isStale(at: date) { return "已过期" }
        if unavailable { return "缓存" }
        if snapshot.ordinaryUsageAllowed == false { return "不可用" }
        guard let window else { return "暂无数据" }
        guard window.remaining != nil else { return "未知" }
        if window.awaitingReset(at: date, collectedAt: snapshot.collectedAt) { return "待更新" }
        return "\(window.durationLabel) %"
    }
    var body: some View {
        Group {
            if let remaining = window?.remaining {
                Gauge(value: remaining, in: 0...100) {
                    Text(label).font(.system(size: 8, weight: .medium))
                } currentValueLabel: {
                    Text(String(format: "%.0f", remaining))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(QuotaAppearance.color(remaining, secondary: bucket?.primary == nil, stale: snapshot?.isStale(at: date) == true))
            } else {
                VStack(spacing: 0) {
                    Text("—").font(.title2)
                    Text(label).font(.system(size: 9))
                }
            }
        }.accessibilityLabel("\(bucket?.name ?? "额度")，\(window?.durationLabel ?? "窗口未知")剩余 \(window?.remaining.map { String(format: "%.0f%%", $0) } ?? "未知")，\(label)")
    }
}
