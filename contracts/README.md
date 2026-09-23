# VibeWatch 数据协议 v1

所有时间均为 UTC Unix 秒整数；百分比是已用比例（0–100），显示剩余比例时计算 `100 - usedPercent`。样例见 `snapshot.example.json`；样例为虚构数据，不代表真实账号。

## 上传快照

`PUT /v1/snapshot`，`Authorization: Bearer <上传密钥>`，`Content-Type: application/json`。

| 字段 | 类型 | 语义 |
|---|---|---|
| schemaVersion | 1 | 只接受第一版协议 |
| collectedAt | integer | 这一次成功采集的时间，不能由缓存续期；最多允许比服务器时钟超前 60 秒 |
| ordinaryUsageAllowed | boolean / null | 后端是否允许使用普通额度；未知不能推断为允许 |
| usage | object / null / omitted | 可选本机当日用量，见下文；旧客户端忽略 |
| buckets | array | 1–32 个额度 bucket，limitId 不重复 |
| buckets[].limitId | string | 本机协议 map 的 key；非空，最长 128 字符 |
| buckets[].limitName | string / null | 显示名，最长 128 字符 |
| buckets[].primary / secondary | object / null | 两种窗口，不硬编码成 5 小时或 7 天 |
| 窗口.usedPercent | number / null | 0–100，缺失为未知 |
| 窗口.windowDurationMins | integer / null | 窗口分钟数，1–5256000 |
| 窗口.resetsAt | integer / null | 上游声明的重置时间；不是恢复额度的证据 |

可空字段在采集器输出中显式写为 `null`；服务器也接受省略。其余字段必须符合协议，顶层、bucket、窗口的未知字段会被拒绝，防止误传登录或会话内容。最大请求体 64 KiB。`limitId` 不等于账号 ID；本项目不上传账号标识、计划类型、credits、会话日志或认证原文。

服务器只保留最新一份快照。单条 D1 条件 upsert 以 `collectedAt` 比较：严格更新才写入；旧时间或同一时间不同内容返回 409。同一时间、相同规范化内容可幂等重试，`receivedAt` 不改变。首次接收成功返回 `{ "accepted": true, "receivedAt": 123 }`。心跳是重新采集后的新快照，不是对旧记录续时间。

## 可选本机用量 usage

仅上传本机 Codex 日志白名单计数汇总，不上传对话、日志原文、会话 ID 或文件路径。不是账号跨设备总用量或官方账单。`usage` 缺失表示未提供统计，不能当成 0；旧 v1 客户端忽略新增字段。

- `periodStart` / `periodEnd`：Mac 当地日期的 UTC 秒边界，支持 23–25 小时；`utcOffsetMinutes`：Mac UTC 偏移。
- `inputTokens`：排除缓存后的输入；`cachedInputTokens`：缓存输入；`outputTokens`：输出；`totalTokens`：三者之和。均为非负整数，避免缓存重复计入。
- `hours`：按小时有序的 `{start, tokens}`，覆盖完整统计日，未来小时为 0，小时总和等于 totalTokens。
- `source` 固定 `local`；`partial` 标记已发现的缺失或计数异常，不代表未标记时即可覆盖其他设备。
- `model` / `reasoningEffort`：最近有计数的本机会话标签，可空，限定安全字符及 80 字符；`lastActivityAt` 为当日最近计数时间，可空。不是所有 token 均由该模型产生的声明。

云端拒绝未知字段、分项不一致、越界时间及未来小时非零计数。完整校验见 `cloud/src/snapshot.ts`。

## 读取和配对

| 接口 | 权限 | 输入 / 返回 |
|---|---|---|
| GET /health | 无 | `{ "status": "ok" }`，只表示进程可响应 |
| POST /v1/pairings | 上传密钥 | `{ "name": "iPhone + Watch" }` → code、expiresAt、deviceId |
| POST /v1/pairings/redeem | 一次性 code | `{ "code": "…" }` → token、deviceId |
| GET /v1/snapshot | 只读 token | `{ "snapshot": {…}, "receivedAt": 123 }` |
| GET /v1/devices | 上传密钥 | devices，含 id、name、createdAt、pairedAt，不含凭据 |
| DELETE /v1/devices/:id | 上传密钥 | 撤销只读凭据及对应配对记录 |

配对码和只读 token 均为 32 字节安全随机值的 64 位十六进制编码。配对码有效 600 秒；数据库只存 SHA-256 哈希，单条条件 UPDATE 原子兑换，并发只有一个成功。已配对 token 有效至撤销，不授予上传或创建设备权限。第一版一对 iPhone / Watch 共用一个只读设备身份；撤销时两者同时失效。

二维码内容：`vibewatch://pair?server=<URL编码的HTTPS根地址>&code=<一次性码>`。不包含上传密钥或设备 token。App 兑换前显示服务器供核对。配对响应丢失时，为避免重复发放 token，应重新生成配对码；可从设备列表删除上次未使用的身份。

所有 API 响应禁止缓存。生产客户端只连接 HTTPS 根地址，不跟随 HTTP 重定向；仅 Mac 和 Apple 模拟器允许回环 HTTP 用于本地开发。

## 错误与显示规则

- 400：非法 JSON、配对码格式或快照字段；401：未认证或已撤销；404：没有快照或接口不存在；409：旧快照；410：配对码过期/已用；413：请求过大；415：不是 JSON；503：未设置足够长度的上传密钥。
- 采集时间超过 10 分钟显示过期，即使刚从云端读到同一记录也不能改成“最新”。
- 重置时间已经过去且没有更新采集时显示“重置待更新”，保留原始剩余值。
- 整个窗口缺失时不占显示位置；窗口存在但百分比缺失时显示 `—`。两个窗口均缺失时显示“暂无额度数据”，不能推断为无限额度、零或满额。圆形组件仅在主窗口整体缺失时选择同 bucket 的次窗口，并标明时长。所选 bucket 暂时消失时显示不可用，不能切换到另一个 bucket 冒充原额度。
