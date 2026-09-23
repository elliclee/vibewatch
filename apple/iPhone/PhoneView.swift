import SwiftUI

struct PhoneView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingScanner = false
    @State private var scannedLink: String?
    @State private var link = ""
    @State private var pendingPairing: PairingRequest?
    @State private var showingDisconnect = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let envelope = model.envelope {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(alignment: .leading, spacing: 20) {
                                SnapshotFooter(envelope: envelope, date: context.date)
                                PhoneDashboard(snapshot: envelope.snapshot, date: context.date)
                            }
                        }
                    } else if model.connection != nil {
                        ContentUnavailableView("等待首次采集", systemImage: "chart.bar.xaxis", description: Text("在 Mac 启动采集器，然后刷新此页面。"))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "applewatch").font(.system(size: 52)).foregroundStyle(.mint)
                            Text("抬腕，看看还剩多少。").font(.largeTitle.bold())
                            Text("将 Mac 上的 Codex 额度同步到 iPhone 与 Apple Watch。")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 16)
                    }
                    if let message = model.message {
                        Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                    }
                    if model.connection == nil {
                        VStack(alignment: .leading, spacing: 14) {
                            Button { showingScanner = true } label: {
                                Label("扫描配对二维码", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                            TextField("或粘贴 Mac 生成的配对链接", text: $link, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            Button("使用配对链接") { prepare(link) }.disabled(link.isEmpty || model.isRefreshing)
                        }
                    } else if model.connection != nil {
                        DisclosureGroup("手表与小组件设置") {
                            VStack(alignment: .leading, spacing: 16) {
                                if let envelope = model.envelope {
                                    Picker("额度类型", selection: Binding(get: { model.preferredBucket }, set: { model.selectBucket($0) })) {
                                        Text("自动选择 Codex").tag("")
                                        ForEach(envelope.snapshot.buckets) { Text($0.name).tag($0.limitId) }
                                        if !model.preferredBucket.isEmpty && !envelope.snapshot.buckets.contains(where: { $0.limitId == model.preferredBucket }) {
                                            Text("所选额度暂不可用").tag(model.preferredBucket)
                                        }
                                    }.pickerStyle(.menu)
                                    Text("表盘与小组件按实际额度窗口显示，圆形组件会标注窗口时长。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                                Label(model.watchStatus, systemImage: "applewatch")
                                Button("再次同步手表配置") { model.synchronizeWatch() }
                                    .buttonStyle(.bordered).controlSize(.regular)
                                Text(model.connection?.server.host ?? "").font(.caption).foregroundStyle(.secondary)
                                Button("断开此设备", role: .destructive) { showingDisconnect = true }
                                    .frame(minHeight: 44)
                            }.font(.subheadline).padding(.top, 16)
                        }.font(.headline).dashboardPanel()
                    }
                }.padding(20)
            }
            .navigationTitle("VibeWatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.connection != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await model.refresh() } } label: {
                            if model.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                        }.disabled(model.isRefreshing).accessibilityLabel("刷新额度")
                    }
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showingScanner, onDismiss: {
                if let scannedLink { prepare(scannedLink); self.scannedLink = nil }
            }) {
                NavigationStack {
                    QRScanner { value in scannedLink = value; showingScanner = false }
                        .navigationTitle("扫描配对码")
                        .toolbar { Button("取消") { showingScanner = false } }
                }
            }
            .sheet(item: $pendingPairing) { pairing in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("连接到你的云端").font(.title.bold())
                        Text(pairing.server.absoluteString).font(.body.monospaced()).textSelection(.enabled)
                        Text("确认此地址与你在 Mac 配置的服务器一致。配对后，iPhone 会将只读配置同步给 Apple Watch。")
                            .foregroundStyle(.secondary)
                        Button("确认配对") {
                            pendingPairing = nil
                            link = ""
                            Task { await model.pair(pairing) }
                        }.buttonStyle(.borderedProminent).disabled(model.isRefreshing)
                        Spacer()
                    }.padding(24)
                    .toolbar { Button("取消") { pendingPairing = nil } }
                }.presentationDetents([.medium, .large])
            }
            .confirmationDialog("断开 iPhone 和手表？", isPresented: $showingDisconnect) {
                Button("断开连接", role: .destructive) { model.disconnect() }
            } message: {
                Text("将清除本机配置并通知手表。要让离线设备的凭据立即失效，请在 Mac 撤销对应设备。")
            }
            .onOpenURL { url in
                if url.host == "quota" { Task { await model.refresh() } }
                else { prepare(url.absoluteString) }
            }
        }.tint(.mint)
    }
    private func prepare(_ value: String) {
        do { pendingPairing = try PairingRequest(link: value) }
        catch { model.message = error.localizedDescription }
    }
}
