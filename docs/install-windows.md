# Windows 11 安装与部署

## 前置条件

- Windows 11；
- 官方小狼毫（Weasel）；
- PowerShell 5.1 或更高版本；
- 首次安装上游五笔词典时允许访问 GitHub。

小狼毫支持 Windows 11，默认把程序安装在 `Program Files`，把用户文件放在
`%APPDATA%\Rime`。如果安装选项指定了其他用户目录，大猫输入法会读取
`HKCU\Software\Rime\Weasel\RimeUserDir`。

## 1. 安装小狼毫

从 [Weasel 官方发布页](https://github.com/rime/weasel/releases/latest) 安装。安装结束后，
确认 Windows 输入法列表里能选择“小狼毫”。

本仓库不重新分发或修改 Weasel。

## 2. 安装 大猫输入法

在仓库根目录打开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Install-DaMao.ps1 -InstallWubiDependency
```

脚本会：

1. 定位 Weasel 和 Rime 用户目录；
2. 检查程序目录与用户目录没有混在一起；
3. 通过 Weasel 自带的 `rime-install.bat` 安装官方 `wubi` 配方；
4. 如果 Plum 失败，使用 Git 克隆官方 `rime/rime-wubi`；
5. 校验仓库来源并只安装 `wubi86.dict.yaml` 与上游许可证；
6. 复制 `damao_wubi.schema.yaml`；
7. 在 `default.custom.yaml` 中追加方案，不替换现有方案列表；
8. 运行 `WeaselDeployer.exe /deploy`。

如果已经安装了官方 `rime-wubi`，可省略 `-InstallWubiDependency`。

### 完全离线安装

在一台可以访问普通 GitHub 的电脑上下载官方
[rime/rime-wubi](https://github.com/rime/rime-wubi) 仓库 ZIP，解压后复制到目标电脑，
然后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Install-DaMao.ps1 `
  -WubiSourcePath "D:\OfflinePackages\rime-wubi-master"
```

本地目录必须包含官方仓库的 `wubi86.dict.yaml`、`wubi86.schema.yaml`、`README.md`
和 `LICENSE`。如果目录是 Git checkout，安装器还会检查 `origin` 是否为
`rime/rime-wubi`。本地 ZIP 没有 Git 元数据，因此其来源由提供该路径的用户负责。

### 错误类型

| 错误码 | 含义 | 处理 |
|---|---|---|
| `DM-WEASEL-NOT-FOUND` | 未找到 Weasel 或 deployer | 安装 Weasel，或传入 `-WeaselRoot` |
| `DM-NETWORK-UNAVAILABLE` | Plum 与官方 GitHub 都无法连接 | 使用 `-WubiSourcePath` |
| `DM-PLUM-FAILED` | Plum 未能安装 `wubi` | 查看后续 Git 回退结果 |
| `DM-WUBI-INSTALL-FAILED` | Git、文件复制或来源验证失败 | 检查 Git 和本地源目录 |
| `DM-WUBI-SOURCE-INVALID` | 本地目录缺文件或来源异常 | 重新下载官方仓库 |
| `DM-DEPLOY-FAILED` | Rime 文件已安装，但重新部署失败 | 从开始菜单手工重新部署并查看 Weasel 日志 |
| `DM-DEPLOY-TIMEOUT` | Weasel 部署在限定时间内没有结束 | 查看错误中给出的最新 Rime 日志位置，再手工重新部署 |

脚本修改已有配置前，会把原文件保存到 Rime 用户目录下的
`backup/damao-ime-config-<时间>`。

自动安装器会在运行 Weasel 之前检查 `%APPDATA%\Rime`。只有该目录不存在或目录内
完全没有任何条目时，才记录为全新 Rime 状态。Weasel 随后即使创建了空的
`default.custom.yaml`、`user.yaml` 等初始化文件，这次安装仍可用已记录的全新状态，
通过 `"schema_list/@before 0"` 把大猫五笔放到共享默认方案列表之前。这样不会删除
Weasel 的其他方案，也不会写入 `user.yaml`。

只要检查时已有一个文件或子目录，就按现有用户处理。安装器保留已有内容和顺序，
只通过 `"schema_list/+"` 或安全的现有列表合并追加一次 `damao_wubi`。重新安装、修复和
“大猫五笔 - 重新部署”都不携带全新状态标记，因此不会再次把大猫五笔移到首位。
旧版安装器生成的 `schema_list/@next` 大猫输入法条目会在备份后自动迁移为兼容列表结构。
只有 YAML 明显损坏或现有结构无法安全合并时，安装器才会以
`DM-CONFIG-MERGE-UNSAFE` 停止，并保留原文件。

部署最长等待 120 秒。安装器不仅检查 `WeaselDeployer.exe` 的退出码，还会确认
`build/default.yaml` 已注册 `damao_wubi` 且 `build/damao_wubi.schema.yaml` 已生成。

## 3. 选择输入方案

在任意普通文本编辑器中切换到小狼毫，然后按 `Ctrl+反引号` 或 `F4`，选择
`大猫输入法`。

如果菜单中没有该方案，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Test-DaMaoEnvironment.ps1
```

检查失败时，先从开始菜单执行“小狼毫重新部署”，再运行一次环境检查。

## 4. 开始使用

当前正式方案只保留标准五笔输入、候选和本地用户词典。它不会启用拼音混输、自动造词、
云候选或额外界面。

安装后按 [Manual Windows testing](manual-testing.md) 完成首次验收。

## 自定义路径

脚本都接受显式路径，便于便携安装或测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Install-DaMao.ps1 `
  -WeaselRoot "D:\Apps\Rime\weasel-x.y.z" `
  -RimeUserDir "D:\IME\RimeUser"
```

`RimeUserDir` 不得位于 Weasel 程序目录中。
