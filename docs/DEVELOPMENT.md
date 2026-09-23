# 开发指南

## 测试

Python 只使用标准库；Cloudflare 开发依赖由 package-lock.json 锁定。

```sh
python3 -m unittest discover -s agent/tests
python3 -m unittest discover -s scripts/tests
npm --prefix cloud ci
npm --prefix cloud run typecheck
npm --prefix cloud test
swift test --package-path apple
```

CI 执行上述不依赖生产凭据的测试。云端测试通过 Miniflare 使用独立数据库和虚构数据，不访问已部署服务。

## 本地 Worker

```sh
python3 scripts/setup_local.py
cd cloud
npm ci
npm run db:local
npm run dev
```

另开终端，在仓库根目录执行：

```sh
python3 scripts/smoke_local.py
```

默认用虚构数据验证上传、配对、读取和撤销；显式 `--real` 才读取本机 Codex 额度，仍只发送到回环服务。私有本地配置保存在 `artifacts/local/config.json`，不与生产配置共用。测试结束用 Ctrl-C 停止 Worker。

## Apple 客户端测试

使用未配对生产账号的模拟器。先列出可用设备，替换下面示例名称：

```sh
xcrun simctl list devices available
xcodegen generate --spec apple/project.yml
xcodebuild -project apple/VibeWatch.xcodeproj -scheme VibeWatchTests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

默认四目标工程测试共享缓存隔离、旧私有配对迁移、断开后不恢复旧配对与 API 行为。历史私有存储版本专用测试按配置跳过。普通 scheme 不运行独立 HTTP 集成测试。

要运行 HTTP 测试，先启动合成数据服务：

```sh
cd cloud
npm run build
npm run test:server
```

另开终端运行 `VibeWatchHTTPTests` scheme，目标为同一模拟器。服务固定监听回环 8791 端口，不使用生产凭据。

## SwiftUI 预览图

无需第三方素材，直接复用展示源码和虚构数据：

```sh
swiftc -parse-as-library apple/Shared/Models.swift apple/Shared/WatchQuotaViews.swift \
  apple/Shared/WatchDashboardViews.swift scripts/render_watch_dashboard.swift \
  -o /tmp/vibewatch-render-dashboard
/tmp/vibewatch-render-dashboard
```

输出 `artifacts/watch-preview/watch-dashboard.png`。这些图片是源码渲染预览，不能当作 watchOS 运行截图或实机验证。

## 工程与生成文件

- `apple/project.yml` 是默认工程源；修改它后重新运行 XcodeGen。
- `apple/project.local.yml` 是个人标识配置，不提交。修改 Xcode UI 中的设置可能被再次生成覆盖。
- `apple/*.xcodeproj`、`artifacts/`、`.wrangler/`、签名材料和 `.env` 均忽略。
- 修改云端绑定后可在 cloud 目录运行 `npm run types`；生成结果不能依赖私有 `.dev.vars`。
- 发布脚本默认只支持四目标正式构建，详见 [TESTFLIGHT.md](TESTFLIGHT.md)。
