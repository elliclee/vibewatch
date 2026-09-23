import SwiftUI
import WidgetKit

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry
    private var snapshot: QuotaSnapshot? { entry.envelope?.snapshot }
    private var bucket: QuotaBucket? { snapshot?.bucket(preferred: entry.preferredBucket) }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                CircularQuotaView(snapshot: snapshot, bucket: bucket, date: entry.date,
                                  unavailable: entry.unavailable, paired: entry.paired)
            } else if let snapshot, let bucket {
                RectangularQuotaView(snapshot: snapshot, bucket: bucket, date: entry.date, unavailable: entry.unavailable)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VibeWatch").font(.headline)
                    Text(emptyMessage).font(.caption)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "vibewatch://quota"))
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
    private var emptyMessage: String {
        if snapshot != nil { return "所选额度暂无数据" }
        if entry.unavailable { return "连接不可用" }
        return entry.paired ? "等待首次采集" : "请先在 iPhone 配对"
    }
}
@main
struct VibeWatchWidgets: Widget {
    let kind = "VibeWatchQuota"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("Codex 额度")
            .description("显示剩余额度和数据状态；在 iPhone 选择额度类型。")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}
