# 架构与数据边界

## 采集

Python 采集器通过 Codex app-server 的 JSON-RPC 读取 account/rateLimits/read，将多 bucket 额度归一化成协议 v1。缺失窗口保留为空；不根据套餐名称虚构限制。采集失败不更新心跳，旧快照不能伪装成新数据。

可选本机用量读取 sessions / archived_sessions 的 token_count 与 turn_context。只提取白名单计数和模型标签，以累计值差分、跨日基线和事件摘要去重；本地增量缓存不上传。统计定义详见 [用量说明](WATCH-DASHBOARD.md)。

## 云端

Workers 校验白名单、请求大小、时间范围、计数一致性和角色权限。D1 存储最新快照、设备记录与令牌哈希。collectedAt 决定更新顺序，同秒同内容可重试，旧快照或同秒冲突返回 409；receivedAt 不续期。

上传密钥只在 Mac 与 Worker。一次性配对码有效 600 秒，D1 原子兑换为只读设备令牌，防止并发重复使用。云端仅保存其 SHA-256 哈希，撤销后不能读取。

## Apple 客户端

iPhone 管理配对与显示偏好，通过 WatchConnectivity 发送只读配置。Watch 配置写入共享 Keychain，缓存存入 App Group；同手表上的 Widget 读取相同存储。App Group 不负责跨设备同步。

iPhone App 与手机小组件使用共享 Keychain 和 App Group 缓存。build 9 首次打开主 App 时迁移 build 8 及更早版本的私有配对与缓存，成功写入共享存储后才删除旧数据。只有主 App 执行迁移。

Watch 与 Widget 分别通过 HTTPS 获取快照。缓存以服务器和设备身份隔离，禁止旧快照覆盖新快照，切换连接后拒绝旧请求写入。

## 时间与状态

- 时间以 UTC Unix 秒交换；本机用量附带 Mac 当地日期边界和 UTC 偏移。
- 采集超过 600 秒标记过期，刚从网络读到旧数据也不改变新鲜度。
- 重置已过只提示待更新，不自动恢复额度。
- Widget 时间线预排过期与重置状态，网络更新由系统预算调度。

## 范围

单人、自部署、最新快照；不是多租户服务、账单系统或跨设备用量分析平台。API 细节见 [协议说明](../contracts/README.md)。
