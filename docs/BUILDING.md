# Apple 客户端构建

本文针对默认三目标工程：iPhone、Watch、Watch Widgets。推荐先完成 [云端部署](SETUP.md)，也可先构建并检查未配对界面。

## 工具链

安装完整 Xcode，打开一次以完成组件安装，在 Settings → Components 中安装需要的 iOS / watchOS 平台支持。命令行确认：

```sh
xcodebuild -version
xcrun --sdk watchos --show-sdk-version
brew install xcodegen
```

当前验证使用 Xcode 27；部署目标为 iOS 17 / watchOS 10。不承诺旧版 Xcode 能直接构建。真机需要 Xcode 能支持其系统版本。

## 标识与工程

使用自己的开发者团队与唯一 Bundle 前缀。以下 `com.example.vibewatch` / `ABCDE12345` 都是示例，必须替换：

```sh
python3 scripts/configure_apple.py --prefix com.example.vibewatch --team ABCDE12345
xcodegen generate --spec apple/project.local.yml
open apple/VibeWatch.xcodeproj
```

脚本生成忽略提交的 `apple/project.local.yml`，保留默认 `project.yml`。Xcode 工程、Info.plist 与 entitlements 由 XcodeGen 生成；后续再次生成时仍使用这个本机 spec。上游工程配置更新后重新运行配置脚本。

| Target | Bundle ID | App Group |
| --- | --- | --- |
| VibeWatch | `<前缀>.phone` | 不需要，使用私有存储 |
| VibeWatchWatch | `<前缀>.phone.watch` | `group.<前缀>.shared` |
| VibeWatchWidgets | `<前缀>.phone.watch.widgets` | 与 Watch 相同 |

Watch 与 Widgets 的共享 Keychain 组为 `$(AppIdentifierPrefix)<前缀>.shared`。AppIdentifierPrefix 由签名工具链展开，通常与 Team ID 相同；不要手写一个不属于自己团队的前缀。

## 开发者门户与签名

1. 打开 Apple Developer → Certificates, Identifiers & Profiles → Identifiers，创建上表三个明确的 App IDs。
2. 在 Identifiers 类型中切换到 App Groups，创建 `group.<前缀>.shared`。
3. 分别打开 Watch 和 Widgets 的 App ID，启用 App Groups，Edit 中勾选该组，Continue 后还需点击页面 Save。
4. 在 Xcode 为三个 target 选择同一团队，使用 Automatically manage signing。确认 Watch / Widgets 的 App Groups 与 Keychain Sharing 配置正确。
5. 将 iPhone 连接到 Mac，确认信任关系，启用设备所要求的开发者模式。Apple Watch 需与该 iPhone 配对。

需要能够配置 App Groups 的开发者账号。不要直接沿用仓库示例标识注册设备，也不要通过移除共享权限规避签名失败；Watch 与表盘组件实际需要共享存储。

## 安装与配对

1. 选择 `VibeWatch` scheme 和真实 iPhone，Build & Run。
2. 在 iPhone 的 Watch App 中安装 VibeWatch；也可在 Xcode 选择 `VibeWatchWatch` scheme 与配对手表运行。
3. 在 Mac 生成配对二维码，iPhone 扫码后确认自己的服务地址。
4. 打开 Watch App 接收配置。如尚未接收，在 iPhone 点击再次同步手表配置。
5. 长按系统表盘 → 编辑 → 复杂功能，在支持矩形或圆形组件的位置选择 VibeWatch。

WatchConnectivity 的“已交给系统”不等于已经送达。配置接收后，手表通过自己的网络读取服务，不要求手机 App 常驻。

## 只验证编译

无需分发证书即可检查真机 SDK 编译，但产物不能直接安装：

```sh
xcodegen generate --spec apple/project.yml
xcodebuild -project apple/VibeWatch.xcodeproj -scheme VibeWatch \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

使用自己的 Team 时，改用 `project.local.yml` 生成工程。默认工程不包含 iPhone 小组件。

正式 TestFlight 分发见 [TESTFLIGHT.md](TESTFLIGHT.md)；重新签名 IPA 的限制见 [IPA-TESTING.md](IPA-TESTING.md)。
