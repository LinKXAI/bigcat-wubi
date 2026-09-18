# UserDB Portability P1：只读检测与 Snapshot Parser

本实现受 [Public Baseline V1](userdb-portability-acceptance-baseline.md) 约束。
公开测试只校验当前仓库的 17 个固定文件，不依赖不可达的历史 Git 对象。

P1 只实现环境检测、librime 原生 `.userdb.txt` 严格只读解析、稳定状态/错误码和隔离测试。P1 不生成 snapshot，不打开 UserDB，不执行同步、备份、导出、恢复、合并、改名或迁移。

## 1. librime 1.13.1 依据

P1 parser contract 以 librime `1.13.1` tag 为唯一已验证格式版本，依据以下官方源码：

- [`user_db.cc`](https://github.com/rime/librime/blob/1.13.1/src/rime/dict/user_db.cc)：原生 snapshot 后缀、header 描述、entry key/value grammar、`c/d/t` 解析与 tombstone 行为。
- [`user_db.h`](https://github.com/rime/librime/blob/1.13.1/src/rime/dict/user_db.h)：`c`、`d`、`t` 的实际 C++ 类型与默认值。
- [`tsv.cc`](https://github.com/rime/librime/blob/1.13.1/src/rime/dict/tsv.cc)：metadata/comment/Tab/line 的实际读取方式。
- [`text_db.cc`](https://github.com/rime/librime/blob/1.13.1/src/rime/dict/text_db.cc)：snapshot metadata 与 records 的内存表示。
- [`user_dict_manager.cc`](https://github.com/rime/librime/blob/1.13.1/src/rime/lever/user_dict_manager.cc)：backup/sync snapshot、restore identity 与 legacy upgrade 流程。
- [`deployment_tasks.cc`](https://github.com/rime/librime/blob/1.13.1/src/rime/lever/deployment_tasks.cc)：`installation.yaml`、默认/显式 `sync_dir`、installation identity 与版本字段。

librime 的 `UserDictManager::Export` 使用另一套 `Rime user dictionary export`/TableDb 格式。P1 不把它、CSV 或自定义文本当作原生 UserDB snapshot。

官方底层 TSV reader 会对部分坏 metadata/entry 记录警告后继续，userdb entry parser 也会忽略第三列之后的列。该行为适合 librime 内部恢复兼容，但不适合作为后续 portability mutation 的安全输入边界。因此 P1 在保持数值类型、code 尾空格修复和未知 metadata 兼容的同时，对 canonical snapshot 结构实行 fail closed。P1 不声称这一严格层与底层 reader 的错误恢复策略相同。

## 2. Parser grammar

只接受文件名：

```text
<db_name>.userdb.txt
```

内容必须为有效 UTF-8。UTF-8 BOM 可有可无，结果语义一致；非法或截断字节序列返回 `SNAPSHOT_INVALID_UTF8`，严格 decoder 不允许用 U+FFFD 静默替换坏字节。字节 `EF BF BD` 编码的 literal U+FFFD 是合法 Unicode，必须正常解析。嵌入 NUL 失败。读取不依赖 Windows PowerShell 默认 ANSI 编码。

Header：

```text
# Rime user dictionary
#@/db_name<TAB><db_name>
#@/db_type<TAB>userdb
#@/rime_version<TAB><version>  # optional
#@/tick<TAB><uint64>           # optional
#@/user_id<TAB><identity>      # optional
```

- 必需：description、`/db_name`、`/db_type`。
- 可选：`/rime_version`、`/tick`、`/user_id`。librime 缺少 tick 时合并侧使用默认值，缺少 user identity 时报告 `unknown`；P1 不补写这些值。
- 未知 metadata：允许并只报告字段名，不输出值。
- 已知 metadata 重复：结构错误。
- 文件名必须与 header `db_name` 精确一致；header 是 authority，P1 不从文件名推断或修正身份。

每条 canonical record 必须恰有三个 Tab 分隔字段：

```text
<code><TAB><phrase><TAB>c=<int32> d=<finite-double> t=<uint64>
```

- code 和 phrase 均不可为空，不可含控制字符。P1 不对非空 code 自行增加首字符或字符集限制。
- librime 会为缺少尾随空格的 code 补一个空格；P1 使用相同规范化来构造 logical key。
- `c < 0` 是合法 tombstone，不按非法负值处理。
- `d` 必须有限且非负，并按 librime 1.13.1 的 `min(10000.0, d)` 规则规范化。
- `t` 必须在 uint64 范围内。
- 缺字段、多余列、非数值、NaN、Infinity、溢出和负 tick 均失败。
- 完整的最后一条 record 可以没有终止换行；结构不完整的未终止末条返回 `SNAPSHOT_TRUNCATED`。
- LF、CRLF 均接受；裸 CR 失败。
- snapshot 内重复的规范化 logical key 返回 `SNAPSHOT_DUPLICATE_KEY`、重复数量和首个冲突行号，不执行 merge。

## 3. 默认输出与隐私

`Read-DaMaoUserDbSnapshot` 默认只返回：

```text
Path ByteLength Sha256 Encoding DbName DbType RimeVersion Tick UserId
EntryCount TombstoneCount DuplicateKeyCount MinTick MaxTick
StructuralHealth ErrorCode ErrorLine UnknownHeaderFields
```

默认结果、status、错误和 JSON 均不包含 phrase、code 或坏行正文。内部测试只有显式使用 `-IncludeEntries` 才能访问 parsed entries。

## 4. Environment/status model

入口：

```powershell
scripts/Get-DaMaoUserDbStatus.ps1
scripts/Get-DaMaoUserDbStatus.ps1 -LogicalRole PureWubi
scripts/Get-DaMaoUserDbStatus.ps1 -RimeUserDir <isolated-path> -AsJson
```

P1 默认只处理 Public Baseline V1 中 `PureWubi` 的两个独立物理 identity：

```text
damao_wubi_alpha03
damao_wubi
```

`damao_wubi_pinyin` 报告为 `excluded_by_default`。未知 DB 可以报告，但始终返回 `USERDB_IDENTITY_UNCLASSIFIED`，不得自动归类 PureWubi。

每个已知 `db_name` 独立返回以下状态之一：

| State | 含义 |
| --- | --- |
| `Absent` | 没有 live、legacy 或合法 snapshot。 |
| `LiveDb` | `<db_name>.userdb/` 目录存在；可能同时有正常 sync snapshot。 |
| `LegacyDb` | 只有已知 legacy `<db_name>.userdb.kct` 表示。 |
| `SnapshotOnly` | 没有 live/legacy，且合法 snapshot 内容来源唯一。 |
| `Ambiguous` | live+legacy、身份冲突、坏 target snapshot，或 SnapshotOnly 有多个不同内容来源。 |

`LiveDb + 正常 sync snapshot` 是 librime 正常状态，不按 artifact 数量误判为 Ambiguous。两个 PureWubi DB 同时存在时仍返回两个独立记录，`AutomaticMerge=false`、`AutomaticRename=false`。

`LiveDb` 只表示目录存在和基础路径结构可识别：

```text
LiveDb existence != LevelDB health validation
```

P1 从不连接或打开 LevelDB。

同理：

```text
SnapshotOnly != restored UserDB
```

P1 不创建目标数据库，也不选择恢复来源。

## 5. Installation 与版本检测

P1 以严格 UTF-8 读取 `installation.yaml` 的顶层 scalar metadata，并区分：

- `SyncDirSource=Default`：`<RimeUserDir>/sync`。
- `SyncDirSource=Explicit`：配置中的绝对 `sync_dir`。

缺失/重复/非法 installation identity、非法或不可读 sync path 都只报告，不创建目录。相对 custom `sync_dir` 会因依赖进程当前目录而 fail closed 为 `SYNC_DIR_INVALID`。

版本状态：`Supported | UnknownVersion | Unsupported | NotDetected`。

- 已验证：Weasel `0.17.4`、librime `1.13.1`。
- 未知未来 librime 版本仍可做只读 status listing，但 `SnapshotFormatVerified=false`，并返回 `LIBRIME_VERSION_UNVERIFIED`。
- P1 的 `FutureMutationCapability` 恒为 `DisabledP1ReadOnly`。

installation identity、logical role、physical `db_name` 与 snapshot `/user_id` 是四个独立概念。snapshot 的 header user identity 不会成为当前机器 live DB identity。

## 6. 稳定错误码

```text
P1_BLOCKED_INPUT_CORE_DRIFT
RIME_USER_DIR_NOT_FOUND
INSTALLATION_YAML_NOT_FOUND
INSTALLATION_YAML_INVALID
INSTALLATION_ID_MISSING
INSTALLATION_ID_INVALID
SYNC_DIR_INVALID
SYNC_DIR_NOT_FOUND
SYNC_DIR_NOT_READABLE
LIBRIME_NOT_DETECTED
LIBRIME_VERSION_UNVERIFIED
WEASEL_NOT_DETECTED
SNAPSHOT_NOT_FOUND
SNAPSHOT_INVALID_UTF8
SNAPSHOT_HEADER_INVALID
SNAPSHOT_DB_TYPE_INVALID
SNAPSHOT_DB_NAME_INVALID
SNAPSHOT_FILENAME_DB_NAME_MISMATCH
SNAPSHOT_ENTRY_INVALID
SNAPSHOT_NUMERIC_FIELD_INVALID
SNAPSHOT_DUPLICATE_KEY
SNAPSHOT_TRUNCATED
USERDB_ARTIFACT_AMBIGUOUS
USERDB_IDENTITY_UNCLASSIFIED
```

自动判断只依赖 ErrorCode，不依赖自然语言 message。

## 7. P1 只读边界

P1 只枚举目录、读取普通文件、计算 SHA-256 和读取文件版本 metadata。隔离测试只在系统临时目录创建人工 fixture。

P1 不执行用户数据同步，不调用 librime mutation API，不备份/导出/恢复 UserDB，不打开、repair、compact 或 migrate LevelDB，不复制 `.userdb/`，不修改真实 Rime 用户目录或 `installation.yaml`，不创建真实目标 UserDB，不改 schema/Lua/learning runtime/Public Baseline V1，不做 merge、rename、automatic migration 或 installer 集成。

P2 的 targeted librime adapter、canonical snapshot generation 和 package v2 不属于本阶段。
