# IPA 与嵌套签名

推荐通过自己的 Xcode 或 TestFlight 安装。仅能在 iPhone 安装 IPA，不代表包内 Watch App 与表盘组件已正确签名。

无签名归档可用 `scripts/package_unsigned_ipa.py <archive> <output.ipa>` 打包供研究，但它不是可直接运行的分发包。工具验证三个嵌套包和平台，并生成 SHA-256 与结构清单；不会读取 Apple 凭据。

任何重新签名工具都必须保留：

- `Watch/VibeWatchWatch.app`；
- Watch 内 `PlugIns/VibeWatchWidgets.appex`；
- 一致的 Bundle ID、Watch companion 标识、版本和团队；
- Watch / Widget 被描述文件授权的 App Group 与共享 Keychain。

第三方工具可能移除嵌套 Watch 包或改写标识。如果 iPhone 能运行而 Watch 列表没有应用，先检查签名后的 IPA 结构，再检查描述文件。不要靠降低 Info.plist 最低版本来假装支持更旧系统；二进制的 SDK 和部署要求不会因此改变。

仓库不提供个人签名包或签名材料。
