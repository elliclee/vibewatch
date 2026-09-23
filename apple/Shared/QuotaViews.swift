import SwiftUI

struct WindowCard: View {
    let title: String
    let window: QuotaWindow?
    let collectedAt: TimeInterval
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(window?.durationLabel ?? title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("剩余").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(window?.remaining.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                if window?.remaining != nil { Text("%").font(.title3).foregroundStyle(.secondary) }
            }
            if let remaining = window?.remaining {
                ProgressView(value: remaining, total: 100).tint(remaining < 20 ? .orange : .mint)
            }
            if let window, window.awaitingReset(at: date, collectedAt: collectedAt) {
                Label("重置待更新", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.orange)
            } else if let reset = window?.resetsAt {
                VStack(alignment: .leading, spacing: 2) {
                    Text("重置时间").foregroundStyle(.secondary)
                    Text(Date(timeIntervalSince1970: reset), format: .dateTime.month().day().hour().minute())
                }.font(.caption)
            } else {
                Text(window == nil ? "暂无窗口数据" : "重置时间未知").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
struct SnapshotFooter: View {
    let envelope: SnapshotEnvelope
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(envelope.snapshot.status(at: date), systemImage: envelope.snapshot.isStale(at: date) ? "clock.badge.exclamationmark" : "clock")
                .foregroundStyle(envelope.snapshot.isStale(at: date) ? .orange : .secondary)
            HStack(spacing: 4) {
                Text("采集于")
                Text(envelope.snapshot.collectedDate, format: .dateTime.month().day().hour().minute())
            }
            Text("Mac 休眠后显示最后一次采集的数据。")
        }.font(.caption)
    }
}
