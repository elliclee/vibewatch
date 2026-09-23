// Source-rendered layout check; sample data and illustrative widget containers.
import AppKit
import SwiftUI

let previewDate = Date(timeIntervalSince1970: 1790000000)
func sample(weeklyOnly: Bool = false, stale: Bool = false) -> QuotaSnapshot {
    QuotaSnapshot(schemaVersion: 1, collectedAt: previewDate.timeIntervalSince1970 - (stale ? 3600 : 120),
        ordinaryUsageAllowed: nil, buckets: [QuotaBucket(limitId: "codex", limitName: "Codex",
            primary: weeklyOnly ? nil : QuotaWindow(usedPercent: 28, windowDurationMins: 300, resetsAt: previewDate.timeIntervalSince1970 + 7200),
            secondary: QuotaWindow(usedPercent: 61, windowDurationMins: 10080, resetsAt: previewDate.timeIntervalSince1970 + 86400))])
}
struct WidgetPreview: View {
    let dark: Bool
    func tile(_ snapshot: QuotaSnapshot?, compact: Bool) -> some View {
        PhoneQuotaWidgetContent(snapshot: snapshot, bucket: snapshot?.buckets.first, date: previewDate,
            paired: snapshot != nil, unavailable: false, compact: compact)
            .padding(16).frame(width: compact ? 170 : 364, height: 170)
            .background(dark ? Color(white: 0.09) : .white, in: RoundedRectangle(cornerRadius: 24))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("VibeWatch · iPhone 小组件").font(.system(size: 24, weight: .semibold))
            HStack(spacing: 20) { tile(sample(), compact: true); tile(sample(), compact: false) }
            HStack(spacing: 20) { tile(nil, compact: true); tile(sample(weeklyOnly: true), compact: false) }
            HStack(spacing: 20) {
                tile(sample(stale: true), compact: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("锁屏 · 矩形 / 圆形").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 22) {
                        RectangularQuotaView(snapshot: sample(), bucket: sample().buckets[0], date: previewDate)
                            .frame(width: 170, height: 72)
                        CircularQuotaView(snapshot: sample(), bucket: sample().buckets[0], date: previewDate, paired: true)
                            .frame(width: 64, height: 64)
                    }
                }.padding(16).frame(width: 364, height: 170)
                    .background(dark ? Color(white: 0.09) : .white, in: RoundedRectangle(cornerRadius: 24))
            }
            Text("SwiftUI 源码布局预览 · 示例数据 · 非 iOS 实机截图").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).background(dark ? Color(white: 0.025) : Color(white: 0.93))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 28800)!)
    }
}
@main struct RenderPhoneWidgetPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "artifacts/phone-widget-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let renderer = ImageRenderer(content: WidgetPreview(dark: dark)); renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: directory.appendingPathComponent(dark ? "dark.png" : "light.png"))
        }
        print("Phone widget layout previews generated (synthetic data).")
    }
}
