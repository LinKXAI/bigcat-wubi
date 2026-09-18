# rime-wubi 依赖策略

## 官方仓库内容

`rime/rime-wubi` 当前 `master` 顶层包含：

- `AUTHORS`；
- `LICENSE`；
- `README.md`；
- `wubi86.dict.yaml`；
- `wubi86.schema.yaml`；
- `wubi_pinyin.schema.yaml`；
- `wubi_trad.schema.yaml`。

仓库采用 LGPL-3.0。公开 Windows installer 从上游提交
`152a0d3f3efe40cae216d1e3b338242446848d07` 原样内置下列最小完整源码集，文件摘要
记录在 `dependencies/windows-installer-v2.lock.json`。

## 当前安装需要什么

`damao_wubi.schema.yaml` 只声明：

```yaml
translator:
  dictionary: wubi86
```

因此运行所需的上游源文件只有自包含的 `wubi86.dict.yaml`。其头部定义词典名
`wubi86`、列结构和编码规则，没有 `import_tables`。

上游 `wubi86.schema.yaml` 包含拼音反查，并声明 `pinyin_simp` 依赖；当前正式方案
没有 reverse lookup translator，所以不需要该 schema、`wubi_pinyin`、
`wubi_trad` 或 `pinyin-simp`。

安装器仍要求本地源目录同时包含 `wubi86.schema.yaml`、`README.md` 和 `LICENSE`，用来
识别完整官方源码包。真正复制到 Rime 用户目录的只有：

- `wubi86.dict.yaml`；
- `LICENSE.rime-wubi.txt`；
- `rime-wubi.source.json`（大猫输入法生成的来源记录）。

## 安装顺序

1. 如果用户传入 `-WubiSourcePath`，不访问网络，直接校验并安装该目录。
2. 如果词典已经存在，直接复用。
3. 使用 `-InstallWubiDependency` 时，先调用 Weasel 官方 Plum 配方 `wubi`。
4. Plum 没有产生词典时，通过 Git 克隆固定的官方 URL：
   `https://github.com/rime/rime-wubi.git`。
5. Git 回退会检查 checkout 的 `origin`，拒绝其他所有者或仓库。

安装器不会从搜索结果、镜像站、任意 Raw URL 或用户输入的网络 URL 下载词典。

正式 Windows 安装器及其“重新部署”快捷方式始终传入内置的 `-WubiSourcePath`，因此不会
进入上述 Plum 或 Git 回退分支。Plum/Git 逻辑仅用于用户显式请求的源码安装命令。

## 许可证处理

从本地目录或 Git 回退安装时，上游词典与 LGPL-3.0 许可证一起复制到 Rime 用户目录，
并记录官方仓库 URL、安装方式和可用的提交哈希。这是运行时依赖安装，不代表把
`rime-wubi` 重新许可为本仓库的 Apache-2.0。
