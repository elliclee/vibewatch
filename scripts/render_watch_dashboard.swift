import AppKit
import SwiftUI

let now = ISO8601DateFormatter().date(from: "2026-09-21T10:25:00Z")!
func sampleUsage() -> LocalUsage {
    let start = now.timeIntervalSince1970 - 18 * 3600 - 25 * 60
    let weights: [Int64] = [0,0,0,0,0,0,1,2,1,3,6,10,14,20,17,12,8,5,1,0,0,0,0,0]
    let sum = weights.reduce(0,+)
    var hours = weights.enumerated().map { UsageHour(start: start + Double($0.offset)*3600, tokens: $0.element * 18_300_000 / sum) }
    let adjustment = 18_300_000 - hours.reduce(Int64(0)) { $0 + $1.tokens }
    hours[18] = UsageHour(start: hours[18].start, tokens: hours[18].tokens + adjustment)
    return LocalUsage(periodStart:start,periodEnd:start+86400,utcOffsetMinutes:480,inputTokens:8_400_000,cachedInputTokens:3_700_000,outputTokens:6_200_000,totalTokens:18_300_000,hours:hours,source:"local",partial:false,model:"gpt-example",reasoningEffort:"high",lastActivityAt:now.timeIntervalSince1970-120)
}
func sample(low: Bool = false) -> QuotaSnapshot {
    QuotaSnapshot(schemaVersion:1,collectedAt:now.timeIntervalSince1970-60,ordinaryUsageAllowed:nil,
        buckets:[QuotaBucket(limitId:"codex",limitName:"Codex",
            primary:QuotaWindow(usedPercent:low ? 93 : 8,windowDurationMins:300,resetsAt:now.timeIntervalSince1970+13320),
            secondary:QuotaWindow(usedPercent:low ? 82 : 32,windowDurationMins:10080,resetsAt:now.timeIntervalSince1970+172800))],usage:sampleUsage())
}
struct DashboardPreview: View {
    func panel<C: View>(_ title: String, page: Int, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack { Spacer();Text("18:25").font(.system(size:11,weight:.medium)) }
                content()
                Spacer(minLength:0)
                HStack(spacing: 4) { Circle().fill(page == 0 ? Color.white : .gray).frame(width:4,height:4);Circle().fill(page == 1 ? Color.white : .gray).frame(width:4,height:4) }
            }.padding(.horizontal,15).padding(.vertical,14).frame(width:218,height:328)
                .background(.black,in:RoundedRectangle(cornerRadius:36))
                .padding(7).background(Color(white:0.15),in:RoundedRectangle(cornerRadius:43))
            Text(title).font(.system(size:14,weight:.semibold))
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("VibeWatch · Watch 两页布局").font(.system(size:25,weight:.semibold))
            HStack(alignment:.top,spacing:24) {
                panel("额度 · 正常",page:0) { WatchDashboardQuota(snapshot:sample(),bucket:sample().buckets[0],date:now) }
                panel("额度 · 偏低",page:0) { WatchDashboardQuota(snapshot:sample(low:true),bucket:sample(low:true).buckets[0],date:now) }
                panel("用量 · 本机今日",page:1) { WatchUsageDashboard(usage:sampleUsage(),date:now,stale:false) }
            }
            Text("SwiftUI 源码预览 · 示例数据与设备外框 · 非 watchOS 实机截图；小屏可下滑查看更多")
                .font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(28).background(Color(white:0.045)).environment(\.colorScheme,.dark)
            .environment(\.locale,Locale(identifier:"zh_CN")).transaction { $0.disablesAnimations = true }
            .environment(\.timeZone,TimeZone(secondsFromGMT:28800)!)
    }
}
@main struct RenderDashboard {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: DashboardPreview());renderer.scale=2
        guard let image=renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let path=URL(fileURLWithPath:"artifacts/watch-preview/watch-dashboard.png")
        try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:path)
        print("Watch dashboard source preview generated (synthetic data).")
    }
}
