import SwiftUI

@main
struct VibeWatchWatchApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchView().environmentObject(model) }
                .task { await model.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
                .onOpenURL { _ in Task { await model.refresh() } }
        }
    }
}
struct WatchView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if let envelope = model.envelope {
                TabView {
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(alignment: .leading, spacing: 12) {
                                if let bucket = envelope.snapshot.bucket(preferred: model.preferredBucket) {
                                    WatchDashboardQuota(snapshot: envelope.snapshot, bucket: bucket, date: context.date)
                                } else { Text("所选额度暂不可用，请在 iPhone 更换。") }
                                refreshControls
                            }.padding(.bottom, 18)
                        }
                    }.tag(0)
                    ScrollView {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(alignment: .leading, spacing: 12) {
                                WatchUsageDashboard(usage: envelope.snapshot.usage, date: context.date,
                                                    stale: envelope.snapshot.isStale(at: context.date))
                                refreshControls
                            }.padding(.bottom, 18)
                        }
                    }.tag(1)
                }.tabViewStyle(.page(indexDisplayMode: .always))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.mint)
                        Text(model.connection == nil ? "请先在 iPhone 配对" : "等待 Mac 首次采集").font(.headline)
                        Text("打开 iPhone 上的 VibeWatch，配置会自动同步到手表。")
                            .font(.caption).foregroundStyle(.secondary)
                        refreshControls
                    }
                }
            }
        }.tint(.mint)
    }
    private var refreshControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.message { Text(message).font(.caption2).foregroundStyle(.orange) }
            Button { Task { await model.refresh() } } label: {
                if model.isRefreshing { ProgressView() } else { Label("刷新", systemImage: "arrow.clockwise") }
            }.disabled(model.isRefreshing || model.connection == nil)
        }
    }
}
