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
    private var twoWindows: Bool { bucket?.primary != nil && bucket?.secondary != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(bucket?.name ?? "VibeWatch")
                    .font(.system(size: compact ? 14 : 15, weight: .bold))
                Spacer(minLength: 0)
                if !compact {
                    WidgetUsageSummary(usage: snapshot?.usage, date: date)
                }
            }.lineLimit(1).minimumScaleFactor(0.8)
            if let snapshot, let bucket, bucket.displayWindow != nil {
                if compact {
                    VStack(spacing: 4) {
                        if let primary = bucket.primary { smallRow(primary, snapshot: snapshot, secondary: false) }
                        if let secondary = bucket.secondary { smallRow(secondary, snapshot: snapshot, secondary: true) }
                    }.frame(maxHeight: .infinity, alignment: .center)
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        if let primary = bucket.primary { column(primary, snapshot: snapshot, secondary: false) }
                        if twoWindows { Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1) }
                        if let secondary = bucket.secondary { column(secondary, snapshot: snapshot, secondary: true) }
                    }.frame(maxHeight: .infinity, alignment: .center)
                }
                if compact { WidgetUsageSummary(usage: snapshot.usage, date: date) }
                HStack(spacing: 4) {
                    Circle().fill(warning(snapshot) ? Color.orange : Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                    Text(snapshot.isStale(at: date) ? "已过期" : unavailable ? "离线缓存" : snapshot.ordinaryUsageAllowed == false ? "额度不可用" : "采集于")
                    Text(snapshot.collectedDate, style: .time).monospacedDigit()
                    Spacer(minLength: 0)
                }.font(.system(size: 9)).foregroundStyle(warning(snapshot) ? .orange : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Spacer(minLength: 0)
                Image(systemName: paired ? "chart.bar.xaxis" : "link")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                Text(emptyMessage).font(.subheadline.weight(.semibold))
                Text(paired ? "轻点打开，刷新额度" : "轻点打开 VibeWatch 配对")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.accessibilityElement(children: .combine)
    }

    private var emptyMessage: String {
        if snapshot != nil { return "暂无窗口数据" }
        if unavailable { return "连接暂不可用" }
        return paired ? "等待首次采集" : "尚未配对"
    }
    private func warning(_ snapshot: QuotaSnapshot) -> Bool {
        snapshot.isStale(at: date) || unavailable || snapshot.ordinaryUsageAllowed == false
    }
    private func tint(_ window: QuotaWindow, _ snapshot: QuotaSnapshot, _ secondary: Bool) -> Color {
        guard !snapshot.isStale(at: date), let remaining = window.remaining else { return .secondary }
        if colorScheme == .light {
            if remaining < 10 { return Color(red: 0.77, green: 0.13, blue: 0.12) }
            if remaining < 20 { return Color(red: 0.65, green: 0.34, blue: 0.02) }
            return secondary ? Color(red: 0.1, green: 0.36, blue: 0.78) : Color(red: 0.1, green: 0.46, blue: 0.24)
        }
        if remaining < 10 { return .red }
        if remaining < 20 { return .orange }
        return secondary ? .blue : .green
    }
    private func smallRow(_ window: QuotaWindow, snapshot: QuotaSnapshot, secondary: Bool) -> some View {
        let color = tint(window, snapshot, secondary)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: QuotaAppearance.symbol(window)).foregroundStyle(color)
                Text(window.durationLabel)
                Spacer(minLength: 0)
                percentage(window, size: twoWindows ? 21 : 34, color: color)
            }.font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            SegmentedQuotaBar(remaining: window.remaining, tint: color, height: twoWindows ? 6 : 9)
            HStack(spacing: 3) {
                Text("重置")
                resetText(window, snapshot: snapshot)
            }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func percentage(_ window: QuotaWindow, size: CGFloat, color: Color) -> some View {
        Text(window.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
            .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
    }
    private func column(_ window: QuotaWindow, snapshot: QuotaSnapshot, secondary: Bool) -> some View {
        let color = tint(window, snapshot, secondary)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: QuotaAppearance.symbol(window)).foregroundStyle(color)
                Text(window.durationLabel)
                if (window.remaining ?? 100) < 20 {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(color)
                }
            }.font(.system(size: 10, weight: .semibold)).lineLimit(1)
            percentage(window, size: 32, color: color)
            SegmentedQuotaBar(remaining: window.remaining, tint: color, height: 8)
            HStack {
                Text("剩余")
                Spacer(minLength: 0)
                Text(window.remaining.map { String(format: "已用 %.0f%%", 100 - $0) } ?? "已用未知")
            }.font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                Text("重置").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                resetText(window, snapshot: snapshot).foregroundStyle(color)
            }.font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 7).padding(.vertical, 5)
                .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.18), lineWidth: 0.5))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func resetText(_ window: QuotaWindow, snapshot: QuotaSnapshot) -> some View {
        if window.awaitingReset(at: date, collectedAt: snapshot.collectedAt) {
            Text("待更新").foregroundStyle(.orange)
        } else if let time = window.resetsAt {
            if (window.windowDurationMins ?? 1440) < 1440 {
                // Absolute reset time remains truthful between system timeline refreshes.
                Text(Date(timeIntervalSince1970: time), format: .dateTime.hour().minute())
            } else {
                Text(Date(timeIntervalSince1970: time), format: .dateTime.month(.defaultDigits).day().hour().minute())
            }
        } else { Text("未知") }
    }
}
