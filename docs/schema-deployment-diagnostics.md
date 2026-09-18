# Weasel schema 部署二分诊断

这组诊断只用于定位正式 Alpha schema 中导致 Weasel 0.17.4 部署卡住的配置。
它不会修改仓库中的 `schemas/damao_wubi.schema.yaml`，不会修改 `default.custom.yaml`，
也不会更换词典。每个变体都固定使用：

```yaml
schema_id: damao_wubi
translator:
  dictionary: wubi86
```

诊断脚本会先备份用户目录里当前的 `damao_wubi.schema.yaml`，再把所选变体复制为同名
schema，执行最长 120 秒的部署，并验证 `build/default.yaml`、编译 schema 和诊断版本号。

## 每次测试

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File ./scripts/Test-DaMaoSchemaVariant.ps1 `
  -Variant 00-minimal
```

每次只替换 `-Variant` 的值。成功时返回 `Result = success`；卡住时返回
`DM-DEPLOY-TIMEOUT` 和最新 Rime 日志位置。无需手工编辑 YAML。

诊断开始前若已经存在 `WeaselDeployer.exe`，脚本会返回 `DM-DEPLOY-BUSY`，不会覆盖
schema，也不会启动第二个 deployer。超时后会终止本次启动的 deployer 进程树、确认其
退出，再恢复测试前的用户 schema。

## 当前严格控制测试

目前只运行 `00-minimal`。它与此前实机成功的 Minimal schema 内容一致，不包含诊断元数据
或其他设置。记录 success 或 timeout 后暂停，不继续推断 speller 项。

## 后续测试顺序（暂停）

1. 运行 `01-speller`：Minimal 基线只增加完整 speller。
2. 如果成功，运行 `02-group2-all`：再增加 switches、recognizer/matcher 和 uniquifier。
3. 如果成功，运行 `03-group3-all`：再增加用户词典和 translator 选项。

在第一个失败组停止主线测试，按下面的分支缩小范围。

### 01-speller 失败

先运行 `01b-delimiter-length`：

- 成功：与 `01-speller` 的唯一增量是 `auto_select: true`；
- 超时：再运行 `01a-code-length`。若它成功，触发范围缩小到 delimiter；若仍超时，
  触发范围缩小到 `max_code_length`。

已确认 `01a-code-length` 超时后，不再继续 `01b`。下一项运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File ./scripts/Test-DaMaoSchemaVariant.ps1 `
  -Variant 01c-four-code-pattern
```

`01c-four-code-pattern` 完全不包含 `max_code_length`，只加入 `auto_select: true` 和
`auto_select_pattern: "^[a-z]{4}$"`。librime 1.13.1 使用整串正则匹配，但该判断位于
唯一候选自动选择路径中；因此实机应分别记录部署结果、1～3 码行为、四码唯一候选行为，
以及四码重码行为。该变体没有配置 `auto_select_unique_candidate`。

### 02-group2-all 失败

按顺序运行：

- `02a-recognizer`：recognizer processor、matcher segmentor、recognizer preset；
- `02b-switches`：只增加 switches；
- `02c-uniquifier`：只增加 uniquifier。

单个变体失败即可锁定对应组件组；如果三个单独变体都成功而 `02-group2-all` 失败，
说明触发条件是这些组件的组合。

### 03-group3-all 失败

运行：

- `03a-user-dictionary`：只增加 `user_dict: damao_wubi` 和 `enable_user_dict: true`；
- `03b-translator-options`：不启用用户词典，只增加 encoder/history/completion 选项。

若只有一个失败，触发范围就是该组；若两个单独成功而完整第三组失败，则说明是两组设置
组合时触发。

## 回报内容

每个变体只需记录“success”或“DM-DEPLOY-TIMEOUT”，例如：

```text
01-speller: success
02-group2-all: DM-DEPLOY-TIMEOUT
02a-recognizer: success
02b-switches: success
02c-uniquifier: DM-DEPLOY-TIMEOUT
```

保留错误中给出的最新日志路径。诊断期间不要恢复正式 schema，直到第一个失败组及其分支
测试完成。
