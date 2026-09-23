import SwiftUI

struct SegmentedQuotaBar: View {
    let remaining: Double?
    let tint: Color
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(0..<14, id: \.self) { index in
                    let fraction = min(1, max(0, (remaining ?? 0) / 100 * 14 - Double(index)))
                    Rectangle().fill(tint.opacity(0.16))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(tint).frame(width: max(0, (proxy.size.width - 26) / 14) * fraction)
                        }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 2))
        }.frame(height: height).accessibilityHidden(true)
    }
}

struct WatchDashboardQuota: View {
    let snapshot: QuotaSnapshot
    let bucket: QuotaBucket
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    private func tint(_ window: QuotaWindow, secondary: Bool) -> Color {
        guard !snapshot.isStale(at: date), let remaining = window.remaining else { return .secondary }
        if remaining < 10 { return .red }
        if remaining < 20 { return .orange }
        return secondary ? .blue : .green
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(bucket.name).font(.headline).lineLimit(1)
            if let primary = bucket.primary { row(primary, secondary: false) }
            if let secondary = bucket.secondary { row(secondary, secondary: true) }
            if bucket.displayWindow == nil { Text("暂无额度数据").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 6) {
                if let primary = bucket.primary { reset(primary, secondary: false) }
                if let secondary = bucket.secondary { reset(secondary, secondary: true) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let usage = snapshot.usage, let model = usage.model {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(snapshot.isStale(at: date) ? Color.gray : .green).frame(width: 5, height: 5)
                        Text(model).fontWeight(.semibold)
                        if let effort = usage.reasoningEffort { Text("· " + effort).foregroundStyle(.secondary) }
                    }.font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("最近本机会话").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Text(snapshot.isStale(at: date) ? "已过期" : snapshot.ordinaryUsageAllowed == false ? "普通额度不可用" : "采集于")
                    Text(snapshot.collectedDate, style: .time).monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(snapshot.isStale(at: date) || snapshot.ordinaryUsageAllowed == false ? .orange : .secondary)
            }
        }
    }
    private func row(_ window: QuotaWindow, secondary: Bool) -> some View {
        let color = tint(window, secondary: secondary)
        let low = (window.remaining ?? 100) < 10 && !snapshot.isStale(at: date)
        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: QuotaAppearance.symbol(window)).foregroundStyle(color)
                Text(window.durationLabel).font(.system(size: 13, weight: .semibold))
                if (window.remaining ?? 100) < 20 { Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(color) }
                Spacer(minLength: 0)
                Text(window.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                    .modifier(QuotaPulse(enabled: low && !reduceMotion && !dimmed))
            }.lineLimit(1).minimumScaleFactor(0.8)
            SegmentedQuotaBar(remaining: window.remaining, tint: color)
            HStack {
                Text("剩余")
                Spacer()
                Text(window.remaining.map { String(format: "已用 %.0f%%", 100 - $0) } ?? "已用未知")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func reset(_ window: QuotaWindow, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("重置 · " + window.durationLabel).font(.system(size: 9)).foregroundStyle(.secondary)
            if window.awaitingReset(at: date, collectedAt: snapshot.collectedAt) {
                Text("待更新").foregroundStyle(.orange)
            } else if let time = window.resetsAt {
                if (window.windowDurationMins ?? 1440) < 1440 {
                    let minutes = max(0, Int64(ceil((time - date.timeIntervalSince1970) / 60)))
                    Text(String(format: "%02lld:%02lld", minutes / 60, minutes % 60)).monospacedDigit().foregroundStyle(tint(window, secondary: secondary))
                        .accessibilityLabel("距重置 \(minutes / 60) 小时 \(minutes % 60) 分钟")
                } else {
                    Text(Date(timeIntervalSince1970: time), format: .dateTime.month(.defaultDigits).day().hour().minute())
                        .foregroundStyle(tint(window, secondary: secondary))
                }
            } else { Text("未知").foregroundStyle(.secondary) }
        }.font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading).padding(7)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.3)))
    }
}

private struct QuotaPulse: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.phaseAnimator(enabled ? [false, true] : [false]) { view, phase in
            view.opacity(phase ? 0.6 : 1)
        } animation: { _ in .easeInOut(duration: 1.2) }
    }
}

struct WatchUsageDashboard: View {
    let usage: LocalUsage?
    let date: Date
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(usage?.isCurrent(at: date) == false ? "上次用量" : "今日用量").font(.headline)
            if let usage {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalUsage.compact(usage.totalTokens)).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
                    Text("tokens · 本机统计").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("小时分布 · Mac 当地时间").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(usage.hours, id: \.start) { hour in
                            let maximum = max(1, usage.peakHour?.tokens ?? 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(hour.start == usage.peakHour?.start ? Color.green : Color.green.opacity(0.5))
                                .frame(height: hour.tokens == 0 ? 1 : max(3, 65 * Double(hour.tokens) / Double(maximum)))
                                .accessibilityLabel("\(hourLabel(hour.start, usage: usage))，\(hour.tokens) tokens")
                        }
                    }.frame(height: 65, alignment: .bottom)
                    HStack {
                        Text("0h")
                        Spacer()
                        if let peak = usage.peakHour { Text("峰值 " + hourLabel(peak.start, usage: usage)) }
                        Spacer()
                        Text("24h")
                    }.font(.system(size: 8)).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    detail("输入", usage.inputTokens, .green)
                    detail("输出", usage.outputTokens, .blue)
                    detail("缓存", usage.cachedInputTokens, .purple)
                }
                Text(usage.partial ? "部分记录 · 仅本机可读取会话" : "仅本机会话 · 输入不含缓存")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if stale { Text("数据已过期，请刷新").font(.caption2).foregroundStyle(.orange) }
            } else {
                Text("暂无用量统计").font(.headline)
                Text("需要 Mac 采集器提供本地 token 记录，额度百分比无法换算成 token。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func detail(_ title: String, _ count: Int64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(LocalUsage.compact(count)).foregroundStyle(color).fontWeight(.semibold)
        }.font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func hourLabel(_ time: TimeInterval, usage: LocalUsage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: usage.utcOffsetMinutes * 60) ?? .gmt
        return String(format: "%02d:00", calendar.component(.hour, from: Date(timeIntervalSince1970: time)))
    }
}
