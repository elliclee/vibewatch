# 部署与首次配对

每位使用者部署自己的 Worker / D1，并配置自己的上传密钥。请先克隆仓库，以下路径均相对于仓库根目录。

## 1. Cloudflare Workers 与 D1

```sh
cd cloud
npm ci
cp wrangler.jsonc wrangler.local.jsonc
npx wrangler login
npx wrangler d1 create vibewatch --config wrangler.local.jsonc
```

把创建结果的数据库 ID 填入 `wrangler.local.jsonc` 的 `d1_databases[0].database_id`，替换全零占位符。多账号时在本机配置增加自己的 `account_id`。`wrangler.local.jsonc` 不提交；不要覆盖成别人的线上数据库。

```sh
npx wrangler d1 migrations apply vibewatch --remote --config wrangler.local.jsonc
npx wrangler secret put UPLOAD_TOKEN --config wrangler.local.jsonc
npx wrangler deploy --config wrangler.local.jsonc
cd ..
```

上传密钥建议由密码管理器生成 64 位随机十六进制字符，在 secret put 的隐藏输入中粘贴。第一次设置 secret 可能要求先创建 Worker。保留同一密钥，稍后输入 Mac 配置；不要放入命令行参数或提交到 Git。

记录部署输出的 HTTPS 根地址，例如 `https://vibewatch.<你的子域>.workers.dev`，不要加 `/v1`。`/health` 可公开访问，额度接口必须鉴权。当前数据库仅保存最新快照，不是历史分析数据库。

`npm run deploy` 使用默认模板；生产部署务必显式使用自己的 `--config wrangler.local.jsonc`。仓库的 `cloud/public` 仅包含静态响应头配置，不附带 IPA 或个人数据。

## 2. Mac 采集

确认 Codex CLI 已通过正常流程登录，并能在终端运行。无需向 VibeWatch 提供 Codex 登录凭据。

```sh
python3 agent/vibewatch.py init
python3 agent/vibewatch.py probe
python3 agent/vibewatch.py once
```

`init` 交互询问自己的 HTTPS 根地址和相同上传密钥，写入：

```text
~/Library/Application Support/VibeWatch/config.json
```

文件权限为 600，配置不进入仓库。`probe` 验证真实接口，只输出 bucket 数和缺失窗口数。`once` 成功采集后上传一次。

| 配置 | 默认值 | 含义 |
| --- | --- | --- |
| server | init 输入 | HTTPS 根地址 |
| uploadToken | init 隐藏输入 | 仅 Mac 持有的上传密钥 |
| codex | 安装时的 CLI 路径 | CLI 移动或升级路径后需同步更新 |
| intervalSeconds | 120 | 采样间隔，允许 60–300 秒 |
| heartbeatSeconds | 300 | 达到该间隔后的下一次成功采样上传，实际可稍长 |
| includeLocalUsage | false | 可选本机当日 token 汇总 |

手表今日用量页需要在私有配置增加 `"includeLocalUsage": true`。只上传计数汇总和安全模型标签，不上传对话、会话 ID 或路径。配置修改后重启后台任务。统计定义见 [WATCH-DASHBOARD.md](WATCH-DASHBOARD.md)。

## 3. 配对

先按 [Apple 构建指南](BUILDING.md) 安装自己的 App，再执行：

```sh
python3 agent/vibewatch.py pair
open "$HOME/Library/Application Support/VibeWatch/pairing.html"
```

在 iPhone 扫描二维码或粘贴页面中的链接，核对服务器并确认。一次性码有效 10 分钟，使用后或过期后需重新生成。二维码由本机生成，不发送到第三方服务；配对完成后可以删除本地页面。

首次打开 Watch 接收配置。手表已配对但没有数据时，确认 Mac 首次上传成功，并在 iPhone 再次同步手表配置。

## 4. 后台运行

首次上传成功后按需安装：

```sh
python3 agent/install_launchd.py
```

`dev.vibewatch.collector` 随当前用户登录运行。Mac 休眠或关机不能继续采样。日志位于私有配置旁的 `logs/`，不记录真实令牌或原始 RPC。采集程序使用文件锁，后台运行时不要同时执行 `once` 或第二个 `run`。

停止并移除登录任务：

```sh
python3 agent/install_launchd.py --uninstall
```

配置保留。重新安装即可恢复；移动仓库目录后需重新安装以更新脚本路径。

## 5. 撤销和排障

```sh
python3 agent/vibewatch.py devices
python3 agent/vibewatch.py revoke <设备UUID>
```

iPhone 与 Watch 共用一个只读设备身份。撤销同时阻止它们和表盘组件后续读取；离线缓存仍可能显示旧数据。iPhone 的本地断开不同于云端撤销。

轮换上传密钥时，先用相同 Worker 配置执行 secret put，再更新 Mac 私有配置并重启采集。已有只读身份不会因上传密钥轮换自动失效。

| 现象 | 检查方向 |
| --- | --- |
| probe 失败 | Codex 已登录、CLI 路径可用、当前账号支持额度查询 |
| 上传 401 | Worker 与 Mac 上传密钥一致 |
| 上传 409 | Mac 时钟正常、没有另一台采集器竞争写入 |
| 配对 410 | 重新生成一次性码 |
| 无快照 404 | 完成首次采集上传 |
| Watch 未配对 | 两端均打开一次，在 iPhone 再次同步配置 |
| 共享存储错误 | Watch / Widgets 的团队、App Group、Keychain 及描述文件一致 |
| 组件更新慢 | 打开 Watch 主动刷新；后台刷新由系统调度 |
| 数据过期 | 唤醒 Mac，检查采集任务和网络 |

切换 Codex 账号后，下次采集会读取当前账号；本机当日会话计数可能包含之前账号的记录。当前版本不提供多账号隔离统计。
