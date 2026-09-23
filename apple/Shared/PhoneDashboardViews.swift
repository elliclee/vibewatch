import SwiftUI

/// Phone-sized presentation of the same quota and local usage shown on Watch.
struct PhoneDashboard: View {
    let snapshot: QuotaSnapshot
    let date: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(snapshot.buckets) { bucket in
                VStack(alignment: .leading, spacing: 20) {
                    Text(bucket.name).font(.title2.bold())
                    if let window = bucket.primary { quota(window, secondary: false) }
                    if let window = bucket.secondary { quota(window, secondary: true) }
                    if bucket.displayWindow == nil {
                        Text("暂无额度数据").foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { resets(bucket) }
                        VStack(spacing: 12) { resets(bucket) }
                    }
                }.dashboardPanel()
            }
            usagePanel
        }
    }

    private func color(_ window: QuotaWindow, secondary: Bool) -> Color {
        guard !snapshot.isStale(at: date), let value = window.remaining else { return .secondary }
        if value < 10 { return .red }
        if value < 20 { return scheme == .dark ? .orange : Color(red: 0.65, green: 0.34, blue: 0.02) }
        if secondary { return .blue }
        return scheme == .dark ? .green : Color(red: 0.1, green: 0.46, blue: 0.24)
    }

    private func quota(_ window: QuotaWindow, secondary: Bool) -> some View {
        let tint = color(window, secondary: secondary)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(window.durationLabel, systemImage: QuotaAppearance.symbol(window))
                    .font(.headline)
                if let remaining = window.remaining, remaining < 20 {
                    Image(systemName: "exclamationmark.triangle").font(.caption)
                        .accessibilityLabel("额度偏低")
                }
                Spacer(minLength: 8)
                Text(window.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(tint)
            SegmentedQuotaBar(remaining: window.remaining, tint: tint, height: 14)
            HStack {
                Text("剩余")
                Spacer()
                Text(window.remaining.map { String(format: "已用 %.0f%%", 100 - $0) } ?? "已用未知")
            }.font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    @ViewBuilder private func resets(_ bucket: QuotaBucket) -> some View {
        if let window = bucket.primary { reset(window, secondary: false) }
        if let window = bucket.secondary { reset(window, secondary: true) }
    }

    private func reset(_ window: QuotaWindow, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("重置 · " + window.durationLabel).font(.caption).foregroundStyle(.secondary)
            Group {
                if window.awaitingReset(at: date, collectedAt: snapshot.collectedAt) {
                    Text("待更新").foregroundStyle(.orange)
                } else if let reset = window.resetsAt {
                    Text(Date(timeIntervalSince1970: reset), format: .dateTime.month(.defaultDigits).day().hour().minute())
                        .foregroundStyle(color(window, secondary: secondary))
                } else { Text("未知").foregroundStyle(.secondary) }
            }.font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.25)))
    }

    private var usagePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(snapshot.usage?.isCurrent(at: date) == false ? "上次用量" : "今日用量").font(.headline)
                Spacer()
                Text("本机统计").font(.caption).foregroundStyle(.secondary)
            }
            if let usage = snapshot.usage {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalUsage.compact(usage.totalTokens))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                        .accessibilityLabel("\(usage.totalTokens) tokens")
                    Text("tokens").font(.subheadline).foregroundStyle(.secondary)
                }
                if !usage.hours.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("小时分布 · Mac 当地时间").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(usage.hours, id: \.start) { hour in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(snapshot.isStale(at: date) ? Color.gray : Color.green.opacity(hour.start == usage.peakHour?.start ? 1 : 0.5))
                                    .frame(height: hour.tokens == 0 ? 2 : max(4, 80 * Double(hour.tokens) / Double(max(1, usage.peakHour?.tokens ?? 0))))
                                    .accessibilityLabel("\(hourLabel(hour.start, usage: usage))，\(hour.tokens) tokens")
                            }
                        }.frame(height: 80, alignment: .bottom)
                        HStack {
                            Text("0h")
                            Spacer()
                            if let peak = usage.peakHour { Text("峰值 " + hourLabel(peak.start, usage: usage)) }
                            Spacer()
                            Text("24h")
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { breakdown(usage) }
                    VStack(alignment: .leading, spacing: 12) { breakdown(usage) }
                }
                Divider()
                if let model = usage.model {
                    Text(model + (usage.reasoningEffort.map { " · " + $0 } ?? ""))
                        .font(.subheadline.monospaced().weight(.semibold))
                    Text("最近本机会话").font(.caption).foregroundStyle(.secondary)
                }
                Text(usage.partial ? "部分记录 · 仅本机可读取会话 · 输入不含缓存" : "仅本机会话 · 输入不含缓存")
                    .font(.caption).foregroundStyle(.secondary)
                if snapshot.isStale(at: date) {
                    Label("用量数据已过期", systemImage: "clock.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("暂无用量统计").font(.subheadline)
                Text("需要 Mac 采集器提供本地 token 记录，额度百分比无法换算成 token。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.dashboardPanel()
    }

    @ViewBuilder private func breakdown(_ usage: LocalUsage) -> some View {
        detail("输入", count: usage.inputTokens, tint: scheme == .dark ? .green : Color(red: 0.1, green: 0.46, blue: 0.24))
        detail("输出", count: usage.outputTokens, tint: .blue)
        detail("缓存", count: usage.cachedInputTokens, tint: .purple)
    }
    private func detail(_ label: String, count: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(LocalUsage.compact(count)).font(.system(.headline, design: .monospaced)).foregroundStyle(tint)
                .fixedSize(horizontal: true, vertical: false)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label)，\(count) tokens")
    }
    private func hourLabel(_ time: TimeInterval, usage: LocalUsage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: usage.utcOffsetMinutes * 60) ?? .gmt
        return String(format: "%02d:00", calendar.component(.hour, from: Date(timeIntervalSince1970: time)))
    }
}

extension View {
    func dashboardPanel() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
    }
}
