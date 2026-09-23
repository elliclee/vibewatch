# 实验：iPhone 小组件

源码包含桌面小号/中号、锁屏矩形/圆形组件，但默认工程和当前发布脚本不包含此目标。不要把“源码存在”理解为安装后即可添加。

`apple/project-phone-widgets.yml` 保留四目标草案，`apple/PhoneWidgets` 与 `Shared/PhoneWidgetViews.swift` 为实现。复用云端协议、Widget 时间线、缺失窗口和过期状态。

## 启用前需要完成

1. 为主 App `<前缀>.phone` 和新扩展 `<前缀>.phone.widgets` 关联同一个 App Group。
2. 更新四目标草案中的构建号、个人标识和团队，并验证 Info / entitlements。
3. 扩展签名脚本为四目标，要求手机两目标具备共享组权限。
4. 在真实升级路径验证私有 Keychain / 缓存迁移，确保断开后不恢复旧凭据。
5. 验证桌面、锁屏、点击跳转和后台刷新，再发布。

迁移实现先写入共享存储，成功后删除旧配置；已有共享配对不被旧配置覆盖。只有主 App 执行迁移，扩展不读取私人旧配置。

预览脚本 `scripts/render_phone_widget_preview.swift` 使用合成数据，输出忽略的 artifacts 目录。组件实机分发仍属于后续工作。
