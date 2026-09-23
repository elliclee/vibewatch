# Watch 两页布局与用量统计

## 已实现

横向分页：额度页包含分段进度、剩余大数字、已用比例、重置卡片、最近本机会话模型/推理强度与采集时间；用量页包含当日总 token、按 Mac 当地时间的小时柱状图，以及非缓存输入、输出、缓存拆分。剩余低于 20% 橙色，低于 10% 红色；低额度数字轻微呼吸，减少动态效果及低亮度状态停用动画。小屏可上下滚动。

只展示接口实际返回的窗口，缺失 5 小时窗口时不占位；未知比例显示 —，重置经过仍等待真实更新，过期快照保留提示。没有用量记录时显示暂无统计，跨日旧记录标记上次用量。

## 采集与隐私

私有配置 `~/Library/Application Support/VibeWatch/config.json` 增加 `includeLocalUsage: true` 后，在原额度采集上附加汇总；默认不启用。修改配置后可重新运行 `python3 agent/install_launchd.py` 加载，保持文件权限 600，不打印配置。

从 `CODEX_HOME`（默认 `~/.codex`）的 sessions / archived_sessions 读取 token_count 与 turn_context 所需字段，只上传计数和安全模型标签。增量缓存 usage-state.json 存在私有配置旁。累计计数差分、重复事件去重与跨日基线避免重复计算；异常/缺失基线标记部分记录。缓存输入已从输入拆出，三栏可直接相加。

统计仅覆盖这台 Mac 可读取的本地会话，不能代表账号所有设备或官方计费；最近模型是上下文信息，不是对整个用量的模型归属判定。Mac 休眠后不继续采集。云端可选字段兼容现有 build 6。

## 验证与发布

额度和用量自动测试、默认三目标编译及真实汇总上传/鉴权读取已验证；详见 [验证范围](VALIDATION.md)。当前验证环境未安装 watchOS 模拟器运行时，源码预览使用示例数据和示意外框，不能替代实机验证。

预览生成：在仓库根目录执行：

```sh
swiftc -parse-as-library apple/Shared/Models.swift apple/Shared/WatchQuotaViews.swift apple/Shared/WatchDashboardViews.swift scripts/render_watch_dashboard.swift -o /tmp/vibewatch-render-dashboard
/tmp/vibewatch-render-dashboard
```

输出 `artifacts/watch-preview/watch-dashboard.png`。

默认三目标工程包含两页界面，手机小组件属于后续独立工作。构建见 BUILDING.md，统计接口见 contracts/README.md。
