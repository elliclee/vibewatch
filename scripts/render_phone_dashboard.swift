// Source-rendered layout check; sample data and illustrative widget containers.
import AppKit
import SwiftUI

let previewDate = Date(timeIntervalSince1970: 1790000000)
func sample(weeklyOnly: Bool = false, stale: Bool = false, low: Bool = false) -> QuotaSnapshot {
    var snapshot = QuotaSnapshot(schemaVersion: 1, collectedAt: previewDate.timeIntervalSince1970 - (stale ? 3600 : 120),
        ordinaryUsageAllowed: nil, buckets: [QuotaBucket(limitId: "codex", limitName: "Codex",
            primary: weeklyOnly ? nil : QuotaWindow(usedPercent: low ? 93 : 8, windowDurationMins: 300, resetsAt: previewDate.timeIntervalSince1970 + 7200),
            secondary: QuotaWindow(usedPercent: low ? 82 : 32, windowDurationMins: 10080, resetsAt: previewDate.timeIntervalSince1970 + 86400))])
    let start = previewDate.timeIntervalSince1970 - 22 * 3600
    snapshot.usage = LocalUsage(periodStart: start, periodEnd: start + 86400, utcOffsetMinutes: 480,
        inputTokens: 8_400_000, cachedInputTokens: 3_700_000, outputTokens: 6_200_000, totalTokens: 18_300_000,
        hours: (0..<24).map { UsageHour(start: start + Double($0) * 3600, tokens: Int64([0,0,0,0,0,0,0,0,200000,400000,600000,800000,1200000,2400000,4000000,3000000,2000000,1500000,1000000,600000,400000,200000,0,0][$0])) }, source: "local", partial: low, model: "gpt-5.5", reasoningEffort: "xhigh", lastActivityAt: nil)
    return snapshot
}

struct DashboardPreview: View {
    let snapshot: QuotaSnapshot
    let dark: Bool
    let width: CGFloat
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("VibeWatch").font(.headline)
                Spacer()
                Image(systemName: "arrow.clockwise").foregroundStyle(.mint)
            }
            PhoneDashboard(snapshot: snapshot, date: previewDate)
            HStack {
                Text("手表与小组件设置").font(.headline)
                Spacer()
                Image(systemName: "chevron.down").foregroundStyle(.mint)
            }.dashboardPanel()
            Text("SwiftUI 源码预览 · 示例数据 · 非实机截图").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).frame(width: width)
            .background(dark ? Color.black : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 28800)!)
    }
}
@main struct RenderPhoneDashboard {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "artifacts/phone-dashboard-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let missing = QuotaSnapshot(schemaVersion: 1, collectedAt: previewDate.timeIntervalSince1970, ordinaryUsageAllowed: nil, buckets: [QuotaBucket(limitId: "codex", limitName: "Codex", primary: nil, secondary: nil)])
        for (name, snapshot, dark, width) in [
            ("dark", sample(), true, CGFloat(393)),
            ("light", sample(), false, CGFloat(393)),
            ("weekly", sample(weeklyOnly: true), true, CGFloat(393)),
            ("low", sample(low: true), true, CGFloat(320)),
            ("stale", sample(stale: true), true, CGFloat(393)),
            ("missing", missing, false, CGFloat(320))
        ] {
            let renderer = ImageRenderer(content: DashboardPreview(snapshot: snapshot, dark: dark, width: width)); renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        print("Phone dashboard previews generated (synthetic data).")
    }
}
