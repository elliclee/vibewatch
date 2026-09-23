# 使用自己的账号发布 TestFlight

普通开发安装按 [BUILDING.md](BUILDING.md) 操作，无需 App Store Connect API 密钥。本页面向需要自行分发的维护者；仓库不提供证书、描述文件或私人邀请。

## 前置条件

1. 在自己的 App Store Connect 创建 iOS App，主 Bundle ID 为 `<前缀>.phone`。
2. 在开发者门户注册三目标标识，将 Watch / Widgets 与共享 App Group 关联并保存。
3. 本机钥匙串有对应团队的有效 Apple Distribution 证书及私钥。
4. 安装 [asc CLI](https://github.com/rudrankriyam/App-Store-Connect-CLI)，按其说明配置自己的认证。

脚本通过环境变量配置，不内置个人账号：

```sh
export VIBEWATCH_TEAM_ID='你的10位TeamID'
export VIBEWATCH_BUNDLE_PREFIX='com.yourname.vibewatch'
export VIBEWATCH_APP_GROUP='group.com.yourname.vibewatch.shared'
export ASC_APP_ID='你在AppStoreConnect创建的App数字ID'
export ASC_KEY_ID='你的APIKeyID'
export ASC_ISSUER_ID='你的IssuerID'
export ASC_PRIVATE_KEY_PATH='/绝对路径/AuthKey_你的KeyID.p8'
```

使用自己保管的密钥文件，不复制到仓库。若 asc 已配置其他受支持的认证方式，可以沿用其认证；`scripts/asc.sh` 只是透传调用。

## 归档、验证、上传

先修改 `apple/project.yml` 的 CURRENT_PROJECT_VERSION，确保高于自己已上传的构建。脚本会生成默认三目标工程，并将团队、Bundle 前缀和共享组作为归档参数传入。

```sh
python3 scripts/prepare_testflight_signing.py
python3 scripts/build_testflight.py
```

第一条复用与本地私钥匹配的分发证书，选择或创建本项目描述文件，不撤销其他证书。第二条归档、导出并验证三个嵌套包的版本、签名、权限与隐私清单，默认不上传。

确认后显式上传：

```sh
python3 scripts/build_testflight.py --upload
# 或上传刚验证的现有 IPA：
bash scripts/asc.sh builds upload --app "$ASC_APP_ID" \
  --ipa artifacts/testflight/VibeWatch.ipa --wait
```

产物与日志都在忽略的 `artifacts/testflight/`。签名数据格式变化后需重新执行 prepare，不要沿用其他部署或旧格式的 signing.json。

## 分发内部测试

等待 Apple 处理为 VALID，在 App Store Connect → TestFlight 为内部组添加构建，填写“测试内容”并邀请账号内测试者。可参考 `docs/TESTFLIGHT-NOTES.zh-Hans.txt` 改写。

内部组不提供面向所有人的公开邀请链接。外部测试另有 Beta 审核流程；不要把 App Store 正式版的“添加以供审核”当作内部测试的必需步骤。

这套脚本当前不支持实验手机小组件目标。启用四目标前必须扩展描述文件和嵌套包校验，不应绕过共享权限检查。
