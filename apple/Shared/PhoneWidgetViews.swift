import SwiftUI

/// Shared with the source preview renderer; no sample quota is included in the app.
struct PhoneQuotaWidgetContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: QuotaSnapshot?
    let bucket: QuotaBucket?
    let date: Date
    let paired: Bool
    let unavailable: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.mint)
                Text(bucket?.name ?? "VibeWatch").fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !compact { Text("剩余额度").foregroundStyle(.secondary) }
            }.font(.caption)
            if let snapshot, let bucket, bucket.displayWindow != nil {
                if compact {
                    VStack(spacing: 9) {
                        if let primary = bucket.primary { smallRow(primary, snapshot: snapshot, secondary: false) }
                        if let secondary = bucket.secondary { smallRow(secondary, snapshot: snapshot, secondary: true) }
                    }.frame(maxHeight: .infinity, alignment: .center)
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        if let primary = bucket.primary { column(primary, snapshot: snapshot, secondary: false) }
                        if let secondary = bucket.secondary { column(secondary, snapshot: snapshot, secondary: true) }
                    }.frame(maxHeight: .infinity, alignment: .center)
                }
                HStack(spacing: 3) {
                    Image(systemName: snapshot.isStale(at: date) || unavailable ? "clock.badge.exclamationmark" : "clock")
                    Text(snapshot.isStale(at: date) ? "已过期" : unavailable ? "离线缓存" : snapshot.ordinaryUsageAllowed == false ? "额度不可用" : "采集于")
                    Text(snapshot.collectedDate, style: .time).monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(snapshot.isStale(at: date) || unavailable || snapshot.ordinaryUsageAllowed == false ? .orange : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Spacer(minLength: 0)
                Text(emptyMessage).font(.subheadline.weight(.medium))
                Text(paired ? "轻点打开，刷新额度" : "轻点打开 VibeWatch 配对")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyMessage: String {
        if snapshot != nil { return "暂无窗口数据" }
        if unavailable { return "连接暂不可用" }
        return paired ? "等待首次采集" : "尚未配对"
    }
    private func tint(_ window: QuotaWindow, _ snapshot: QuotaSnapshot, _ secondary: Bool) -> Color {
        if colorScheme == .light, !snapshot.isStale(at: date), let remaining = window.remaining, remaining >= 20 {
            return secondary ? Color(red: 0, green: 0.43, blue: 0.57) : Color(red: 0, green: 0.45, blue: 0.39)
        }
        return QuotaAppearance.color(window.remaining, secondary: secondary, stale: snapshot.isStale(at: date))
    }
    private func smallRow(_ window: QuotaWindow, snapshot: QuotaSnapshot, secondary: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.durationLabel).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(window.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: bucket?.secondary != nil && bucket?.primary != nil ? 23 : 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(window, snapshot, secondary)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            QuotaBar(remaining: window.remaining, tint: tint(window, snapshot, secondary), height: 4)
            if window.awaitingReset(at: date, collectedAt: snapshot.collectedAt) {
                Text("重置待更新").font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
    }
    private func column(_ window: QuotaWindow, snapshot: QuotaSnapshot, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(window.durationLabel).font(.caption2).foregroundStyle(.secondary)
            Text(window.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(size: 33, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint(window, snapshot, secondary)).lineLimit(1).minimumScaleFactor(0.7)
            QuotaBar(remaining: window.remaining, tint: tint(window, snapshot, secondary), height: 4)
            QuotaResetLabel(window: window, collectedAt: snapshot.collectedAt, date: date)
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
