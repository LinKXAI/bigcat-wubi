# 大猫五笔 / Big Cat Wubi

大猫五笔是基于 Rime/Weasel 的 Windows 五笔 86 输入法安装包。项目坚持本地优先、
隐私优先，并以开源方式提供配置、安装脚本、用户词典迁移工具和可复现的 Windows
构建流程。

## Features

- Windows 上的五笔 86 输入、候选选择与本地用户词典学习；
- 内置并校验 Weasel 0.17.4 与固定版本的 `rime-wubi` 源文件；
- 安装包可离线完成安装和重新部署；
- 用户词典备份、严格校验、恢复前预检与安全备份；
- 不提供遥测、云候选、账号、广告或后台剪贴板监听；
- GitHub-hosted Windows CI 验证和无签名安装包构建。

## Windows installation

从 [Releases](https://github.com/LinKXAI/bigcat-wubi/releases) 下载最新 Windows 安装包，
运行 `BigCatWubi-Setup.exe`，然后按安装向导完成部署。安装包可在无网络环境下使用。

当前发行候选版尚未签名，Windows SmartScreen 可能显示未知发布者提示。请核对发布页
提供的 SHA-256，再决定是否运行。详细行为和卸载边界见
[Windows installer](docs/windows-installer.md)。

## Download / Releases

计划中的公开仓库地址是 <https://github.com/LinKXAI/bigcat-wubi>。正式公开发布后，
安装包、校验和与构建元数据将只通过该仓库的 Releases 页面提供。项目不会自动发布
GitHub Release。

首个公开版本的发布标识为 `v0.9.0-rc1`，产品显示版本为 `0.9.0 RC1`，Windows 数字
文件/产品版本为 `0.9.0.0`。三者由 [installer/windows/VERSION](installer/windows/VERSION)
统一定义，安装包和构建元数据从该文件读取；安装包文件名保持 `BigCatWubi-Setup.exe`。

## User dictionary backup and restore

用户词典保存在本机 Rime 用户目录中。备份与恢复入口如下：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Backup-DaMaoUserDictionary.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Restore-DaMaoUserDictionary.ps1 -Archive <backup.zip>
```

Package V2 工具使用严格 snapshot 解析、身份授权、恢复预检，并在修改已有目标前创建
安全备份。`damao_wubi_alpha03` 与 `damao_wubi` 保持为两个独立物理数据库；工具不会
自动合并、改名或迁移。详见 [User data and backup](docs/user-data.md)。

## Privacy

正常输入、用户词典、备份和恢复均在本机进行。捆绑安装包不需要联网。只有用户在
源码安装场景显式使用 `-InstallWubiDependency` 时，脚本才可能通过 Plum 或 Git 获取
官方上游依赖。完整边界见 [Privacy architecture](docs/privacy-architecture.md)。

## Build from source

在 Windows 上安装 Inno Setup 7.1.0，并运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/Run-DaMaoTests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/Build-WindowsInstaller.ps1
```

构建只使用当前公开仓库 checkout、仓库内固定的上游输入和显式指定的 Inno Setup。
GitHub Actions 的手动构建工作流会固定校验 Inno Setup 7.1.0 下载，并上传名称为
`bigcat-wubi-windows-unsigned` 的无签名产物。

## Code signing policy

当前发布产物未签名；SignPath Foundation 尚未接受本项目，项目没有签名凭据，也没有
提交过签名请求。未来政策、可信构建和人工批准边界见
[Code signing policy](CODE_SIGNING.md) 与 [SignPath readiness](docs/signpath-readiness.md)。

## Licenses

大猫五笔原创内容采用 [Apache License 2.0](LICENSE)。安装包还聚合或引用采用各自
许可证的上游组件：Weasel 0.17.4（GPL-3.0）、`rime-wubi` 固定源码
（LGPL-3.0）以及 Weasel 使用的 librime（BSD 3-Clause）。整个安装包不能被描述为
仅采用 Apache-2.0。详见 [Licensing](docs/licensing.md)。

## Known issues

- ASCII/English mode works, but the schema icon may remain the Big Cat icon instead of
  changing to the intended “A” icon. This is cosmetic and does not affect direct English input.

## Contributing / Security

提交补丁前请阅读 [Contributing](CONTRIBUTING.md)，并运行仓库验证与相关 portability
测试。安全问题请遵循 [Security policy](SECURITY.md)；不要在公开 Issue 中粘贴真实
用户词典、按键历史、私人配置或个人数据。

当前公开发布说明见 [CHANGELOG.md](CHANGELOG.md)。
