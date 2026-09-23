import SwiftUI
import WidgetKit

struct PhoneQuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry
    private var snapshot: QuotaSnapshot? { entry.envelope?.snapshot }
    private var bucket: QuotaBucket? { snapshot?.bucket(preferred: entry.preferredBucket) }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                CircularQuotaView(snapshot: snapshot, bucket: bucket, date: entry.date,
                                  unavailable: entry.unavailable, paired: entry.paired)
            } else if family == .accessoryRectangular {
                if let snapshot, let bucket {
                    RectangularQuotaView(snapshot: snapshot, bucket: bucket, date: entry.date, unavailable: entry.unavailable)
                } else {
                    VStack(alignment: .leading) {
                        Text("VibeWatch").font(.headline)
                        Text(entry.unavailable ? "连接暂不可用" : entry.paired ? "等待首次采集" : "打开 App 配对")
                            .font(.caption)
                    }
                }
            } else {
                PhoneQuotaWidgetContent(snapshot: snapshot, bucket: bucket, date: entry.date,
                    paired: entry.paired, unavailable: entry.unavailable, compact: family == .systemSmall)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "vibewatch://quota"))
        .privacySensitive()
    }
}

@main
struct VibeWatchPhoneWidgets: Widget {
    let kind = "VibeWatchPhoneQuota"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { PhoneQuotaWidgetView(entry: $0) }
            .configurationDisplayName("Codex 额度")
            .description("在桌面或锁屏查看剩余额度；跟随 App 中选择的额度类型。")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
