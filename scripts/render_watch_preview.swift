// Compile with Shared/Models.swift and Shared/WatchQuotaViews.swift on macOS.
// Renders production view components inside illustrative device/clock containers.
import AppKit
import SwiftUI

let previewDate = Date(timeIntervalSince1970: 1789783800)
func fixture(primary: Double = 28, secondary: Double = 61, stale: Bool = false, unknown: Bool = false, weeklyOnly: Bool = false) -> QuotaSnapshot {
    QuotaSnapshot(schemaVersion: 1, collectedAt: previewDate.timeIntervalSince1970 - (stale ? 4200 : 120), ordinaryUsageAllowed: nil,
        buckets: [QuotaBucket(limitId: "codex", limitName: "Codex",
            primary: unknown || weeklyOnly ? nil : QuotaWindow(usedPercent: primary, windowDurationMins: 300, resetsAt: previewDate.timeIntervalSince1970 + 7200),
            secondary: unknown ? nil : QuotaWindow(usedPercent: secondary, windowDurationMins: 10080, resetsAt: previewDate.timeIntervalSince1970 + 172800))])
}
struct WatchFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(width: 198, height: 242).background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 37))
            .padding(8).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 45))
            .overlay(RoundedRectangle(cornerRadius: 45).stroke(Color(white: 0.28), lineWidth: 1))
            .overlay(alignment: .trailing) { RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.3)).frame(width: 5, height: 25).offset(x: 5, y: -34) }
            .scaleEffect(1.35).frame(width: 295, height: 360)
    }
}
struct AppScreen: View {
    let snapshot: QuotaSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Text("10:10")
            }.font(.system(size: 11, weight: .medium))
            WatchQuotaOverview(snapshot: snapshot, bucket: snapshot.buckets[0], date: previewDate)
            Spacer(minLength: 0)
        }.padding(.horizontal, 14).padding(.top, 17).padding(.bottom, 10)
    }
}
struct FaceScreen: View {
    let circular: Bool
    var snapshot = fixture()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("周六 19").font(.system(size: 12, weight: .medium)).foregroundStyle(.mint)
            Text("10:10").font(.system(size: 50, weight: .medium, design: .rounded)).monospacedDigit()
            if circular {
                HStack {
                    Spacer()
                    CircularQuotaView(snapshot: snapshot, bucket: snapshot.buckets[0], date: previewDate, paired: true)
                        .frame(width: 64, height: 64)
                    Spacer()
                }
                Text("Codex · \(snapshot.buckets[0].displayWindow?.durationLabel ?? "额度")").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                RectangularQuotaView(snapshot: snapshot, bucket: snapshot.buckets[0], date: previewDate)
                    .padding(9).background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(.horizontal, 15).padding(.vertical, 18)
    }
}
struct PreviewSheet: View {
    let complications: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("VibeWatch").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(complications ? "表盘组件" : "Watch 额度总览").font(.system(size: 17)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 18) {
                if complications {
                    panel("矩形 · 双窗口", "保留系统时间，同时查看两个额度窗口") { FaceScreen(circular: false) }
                    panel("圆形 · 主窗口", "一个大数字，抬腕即可查看剩余比例") { FaceScreen(circular: true) }
                } else {
                    panel("正常额度", "双窗口、重置时间和新鲜度在一屏内") { AppScreen(snapshot: fixture()) }
                    panel("额度偏低", "颜色和警示符号共同提示") { AppScreen(snapshot: fixture(primary: 93, secondary: 82)) }
                    panel("缓存已过期", "保留历史数值，明确标记采集时间") { AppScreen(snapshot: fixture(stale: true)) }
                }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("现有 SwiftUI 展示组件渲染 · 虚构数据 · 非 watchOS 截图\(complications ? " · 系统表盘容器为示意" : "")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: complications ? 678 : 996)
            .background(Color(red: 0.055, green: 0.064, blue: 0.077))
            .environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 8 * 3600)!).tint(.mint)
    }
    func panel<C: View>(_ title: String, _ caption: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 8) {
            WatchFrame { content() }
            Text(title).font(.system(size: 16, weight: .medium))
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(width: 300)
    }
}
struct SingleWindowSheet: View {
    private let snapshot = fixture(weeklyOnly: true)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VibeWatch · 仅有 7 天窗口").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("按接口实际返回的窗口显示，不保留空的 5 小时栏位。").font(.system(size: 15)).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                panel("Watch 总览") { AppScreen(snapshot: snapshot) }
                panel("矩形组件") { FaceScreen(circular: false, snapshot: snapshot) }
                panel("圆形组件 · 明确标注 7 天") { FaceScreen(circular: true, snapshot: snapshot) }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("现有 SwiftUI 展示组件渲染 · 虚构数据 · 非 watchOS 截图 · 系统表盘容器为示意")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 996).background(Color(red: 0.055, green: 0.064, blue: 0.077))
            .environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 8 * 3600)!).tint(.mint)
    }
    func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 8) {
            WatchFrame { content() }
            Text(title).font(.system(size: 16, weight: .medium))
        }.frame(width: 300)
    }
}
@main struct RenderWatchPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "artifacts/watch-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, complications) in [("watch-overview.png", false), ("watch-complications.png", true)] {
            let renderer = ImageRenderer(content: PreviewSheet(complications: complications))
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
        }
        let single = ImageRenderer(content: SingleWindowSheet())
        single.scale = 2
        if let image = single.cgImage {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("watch-weekly-only.png"))
        }
        let titleFree = ImageRenderer(content:
            VStack(alignment: .leading, spacing: 14) {
                Text("Watch · 去掉顶部品牌标题后").font(.system(size: 23, weight: .semibold))
                HStack(spacing: 24) {
                    VStack {
                        WatchFrame { AppScreen(snapshot: fixture()) }
                        Text("双额度窗口").font(.subheadline)
                    }
                    VStack {
                        WatchFrame { AppScreen(snapshot: fixture(weeklyOnly: true)) }
                        Text("仅有 7 天窗口").font(.subheadline)
                    }
                }
                Text("build 6 展示组件 · 示例数据 · 布局预览，非 watchOS 实机截图")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(28)
                .background(Color(red: 0.055, green: 0.064, blue: 0.077))
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.timeZone, TimeZone(secondsFromGMT: 8 * 3600)!).tint(.mint))
        titleFree.scale = 2
        if let image = titleFree.cgImage {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: directory.appendingPathComponent("watch-build-6-no-title.png"))
        }
        // Inspect the unknown-value state separately without a fabricated zero progress ring.
        let unknown = ImageRenderer(content: AppScreen(snapshot: fixture(unknown: true)).frame(width: 198, height: 242).background(.black).environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "zh_CN")))
        unknown.scale = 2
        if let image = unknown.cgImage {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("watch-unknown.png"))
        }
        print("Watch source previews generated (synthetic data).")
    }
}
