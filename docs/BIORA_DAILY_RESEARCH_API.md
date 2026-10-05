# BioRA 实验室：每日研究摘要接口 v1

版本：客户端 0.14.0 / build 21，2026-10-02。这是**已实现的客户端契约**，不是已经部署的云服务。服务器、鉴权签发、论文检索／模型分析及每日发布任务需要服务端自行实现；本轮没有改动现有团队后端或发起真实云端请求。

This standalone repository documents the client contract only. It does not include or operate a research-digest server, paper retrieval, model analysis, or a daily publishing pipeline. The native BioRA app runs directly on macOS, not in Docker.

## 1. 功能和隐私边界

设置 →「实验室 · 每日研究摘要」→ 开启实验室功能 → 保存 HTTPS 根地址、频道、IANA 时区和可选 Bearer Token。侧栏出现「每日研究」。默认关闭；历史工作区缺少新字段时也是关闭状态。暖色纸感／macOS 原生主题、中英文界面均可使用。

客户端只发 GET，不上传本机实验、仪器、Protocol、对话、PDF、工作区路径、模型设置或模型 Key。请求中含日期、时区、语言、频道，及用户为该服务器配置的独立令牌；服务器正常能看到来源 IP 和请求时间。来源链接仅由用户点击后在浏览器打开，不自动下载 PDF 或执行摘要中的内容。

摘要独立存入 `Workspace.researchDigests`，不是本人的科学问题、实测实验、Protocol 或排程，不触发 Assistant 工具。使用现有「主线＋多级结论树」阅读、知识画布、节点详情与全屏。另有摘要／来源页、日期选择和离线缓存列表。Assistant 可通过现有 `navigation` 分支打开 `laboratory` 页面；未开启时仅引导设置，不静默开启云端。

## 2. 请求

设置中的 `baseURL` 是 HTTPS 根地址，可以带部署前缀，但不含用户／密码、query、fragment 或路径穿越。例如：

```text
baseURL = https://research.example.org/api
GET /api/v1/research/daily?date=2026-10-02&timezone=Asia%2FShanghai&language=en&feed=default
```

| 参数 | 定义 |
| --- | --- |
| `date` | 必填，真实日历日期 `YYYY-MM-DD`，按 `timezone` 定义当天，非 UTC 日期推断 |
| `timezone` | 必填，IANA 标识；默认 `Asia/Shanghai` |
| `language` | 必填，`zh-Hans` 或 `en`；等于 BioRA 当前界面／生成语言 |
| `feed` | 必填，1–100 个 ASCII 字符，仅字母、数字、`_-.`；默认 `default`；是研究订阅频道，不是客户端实验室数据库 ID |

请求头：

```http
Accept: application/json
Accept-Language: en
User-Agent: BioRA/0.14.0
Authorization: Bearer <server-access-token>
If-None-Match: "daily-default-20261002-en-r1"
```

`Authorization` 仅在用户配置令牌时发送；公开频道可省略。`If-None-Match` 仅在当前服务器／频道／时区／语言／日期有缓存和 ETag 时发送。请求没有 body。服务端应验证令牌的读权限和频道权限，建议最小权限 `research:read`；不要将模型 API Key 当成此令牌。

安全约束：只允许系统证书校验通过的 HTTPS；不放宽 TLS，不跟随任何 HTTP 重定向，避免令牌转发。填写最终地址；本地开发需可信证书的 HTTPS 或前置 TLS 代理，不接受裸 HTTP。不保存会话 Cookie，无系统 HTTP 持久缓存。令牌按工作区目录、服务器根地址、频道的 SHA-256 标识隔离，沿用登录钥匙串存储；更换服务器／频道不会复用旧令牌。令牌不进工作区 JSON 备份；新电脑需要重新配置。更改根地址尾部 `/` 也会形成不同身份，建议服务端提供一个固定规范地址。

## 3. 响应与状态码

| 状态 | 客户端处理 |
| --- | --- |
| `200` | `Content-Type: application/json`，UTF-8 完整对象，通过结构／领域校验后缓存 |
| `304` | 仅对条件请求有效，无 body；保留原图谱与本机节点 ID，更新检查时间 |
| `202` | 服务器正在生成；无图谱，默认稍后 15 分钟再尝试 |
| `204` / `404` | 当天没有发布／频道无内容；不清除已有缓存，默认 30 分钟后再尝试 |
| `401` | 令牌缺失／失效，提示更新；自动重试间隔 6 小时，手动可立即重试 |
| `403` | 无频道权限，提示检查权限；自动重试间隔 6 小时 |
| `429` | 限流，默认 1 小时后重试 |
| `3xx`（除 `304`） | 拒绝重定向，要求配置最终地址 |
| 其他／网络错误 | 保留缓存，提示失败，默认 30 分钟后重试 |

可返回 `Retry-After: 900` 指示 `202/204/404/429` 的重试间隔。客户端目前支持**秒数格式**，夹在 60–86400 秒；HTTP-date 格式按默认间隔处理。非成功响应 body 不展示、不开模型修复、不执行指令。

响应解压后的内容上限 **2,000,000 字节**；已知 Content-Length 超限先拒绝，未知长度按流式累计截断并取消请求。请求超时 30 秒，资源超时 60 秒。`ETag` 可省略；如提供，不超过 512 UTF-8 字节，不含 CR/LF。推荐强 ETag，覆盖同一完整响应。响应日期、时区、语言、频道必须精确对应请求，服务器不得偷偷回退英文／其他日期或频道。

## 4. 完整 JSON 契约

可直接运行的**虚构联调示例**：[`BIORA_DAILY_RESEARCH_EXAMPLE.json`](BIORA_DAILY_RESEARCH_EXAMPLE.json)。机器可读结构：[`BIORA_DAILY_RESEARCH_SCHEMA.json`](BIORA_DAILY_RESEARCH_SCHEMA.json)。示例不是实际论文，不可用作科学证据。不得返回 Markdown 代码围栏、字符串化 JSON、工具调用或任意额外字段。

| 顶层字段 | 类型与含义 |
| --- | --- |
| `schema_version` | 整数，固定 `1`；不兼容格式必须升级此值和客户端 |
| `id` | 同一频道／日期／时区／语言的稳定摘要 ID；1–100 个标识字符，格式同 feed；修订不换 ID |
| `date`, `timezone`, `language`, `feed` | 精确回显请求 |
| `revision` | 正整数，内容变化必须单调递增；同版本内容改变或版本倒退会被拒绝 |
| `title` | 1–300 字符，摘要标题 |
| `summary` | 不超过 10000 字符的简述；不是无出处的自由生成总结 |
| `published_at` | 带时区的 ISO-8601/RFC3339 时间，支持小数秒，例如 `2026-10-02T00:00:00Z` |
| `sources` | 1–50 个可追溯来源；各对象恰有 `id,title,url,page_count` |
| `citations` | 最多 1000 个引用；各对象恰有 `node_key,source_id,page` |
| `graph` | 以下七字段的主线图谱对象，不含 `analysis` 或本机 UUID |

来源：`id` 在 sources 内唯一；`title` 1–1000 字符；`url` 是可追溯文献的 HTTPS 链接，不含用户名／密码，最长 2048 字符；`page_count` 为原 PDF 总页数，1–500。`page` 是 1-based PDF 页码，不是期刊印刷页码。每个图谱论断和原子实验至少一个引用，允许跨文献多个引用；三元组不可重复。来源标题可保持原文语言。

`graph` 恰有：

| 字段 | 对象的精确字段；数组上限 |
| --- | --- |
| `title`, `detail` | 研究问题标题 ≤300 字符，说明 ≤20000 字符（客户端追加说明后的领域上限仍为20000） |
| `claims` | `key,kind,text,source_page`；≤60 |
| `atomic_experiments` | `key,title,method,status,observed_result,source_page`；≤100 |
| `evidence_links` | `atom_key,claim_key,kind,explanation,limitations`；≤300 |
| `claim_links` | `from_key,to_key,kind,explanation,limitations`；≤300 |
| `mainline` | `claim_key,question,motivation,origin,role`；≤60 |

节点 `key` 在 claims 和 atomic_experiments 的联合空间唯一，只能用 ASCII 字母、数字、`_-`，1–40 字符。连边使用这些 key，UUID 由客户端生成，不引用用户工作区的实验 ID。字段必须出现；`source_page` 可为 null（详见下文），其余图谱文本使用字符串，包括无法报告的信息用 `""`，不伪造数字。

枚举：

- `claims.kind`：`assertion / hypothesis / observation / conclusion`。
- `atomic_experiments.status`：`recorded / planned`。recorded 指文献报告的检验，不是用户的实测。
- 两种证据连边的 `kind`：`supports / contradicts`。
- `mainline.origin`：`reported / inferred`。inferred 是重建的研究承接，不冒充原文明示。
- `mainline.role`：`result / discussion`。

论文研究逻辑约束（JSON Schema 之外的客户端校验）：

1. 至少一个 result；主线节点均引用 conclusion；末尾恰好一个 Discussion 综合结论。主线数组仅是推进顺序，不隐式产生证明关系。
2. 原子实验 → 下层论断 → 任意必要层级 → 主线 result；原子实验不能直接接任何主线节点。每个 result 都必须具有自己的实验证据树，可共享证据、跨树支持／反驳。
3. claim_links 必须是有向无环图，无自环／重复有向节点对；所有论断经有向边可达主线，每个 recorded 实验经结论树可达 result，不能借 Discussion 绕路。
4. 每条连边 `explanation` 必须非空，具体解释该观察／下层结论为何支撑或挑战目标；`limitations` 写边界，不能用“有关联”代替推理。
5. recorded 实验必须有非空 method、observed_result、source_page，且页码匹配自身 citations 中至少一项。planned 的 observed_result 必须空，不能作为 evidence_links 起点。论断非空；任意节点的 source_page 非 null 时必须匹配自身 citations。reported 主线的对应论断必须有 source_page。
6. 未找到结果／图注／数据时不得补造。纯理论文章如果无法形成此实验论证契约，应不作为一个已发布的此类摘要，不伪装成 performed experiment。章节、材料、Protocol 操作也不是独立原子实验。
7. 所有新生成的 title、summary、graph 文字跟随请求语言；英文响应中的生成文字不得含中文。source 标题保持原文。切换语言请求独立内容，旧缓存不自动翻译。
8. Source URL／页码校验只能证明结构可追溯，不能证明科学结论真实、原文语义覆盖或论文未撤稿；服务端与用户仍须核对。

建议长度：claim.text ≤10000，atom.title ≤300、method ≤10000、observed_result ≤20000；边 explanation/limitations 各≤10000；mainline.question ≤3000、motivation ≤5000。客户端图谱领域校验继续执行这些上限和来源说明上限。

## 5. 每日发布与客户端同步

推荐服务端流程：检索授权来源 → 本机／云端 PDF 文字及图注读取 → 分类型精读 → 按研究问题整合主线 → 每个结果的多级结论／原子实验树 → 来源和推理逐项核对 → 结构及领域验证 → 生成完整 JSON 和 ETag → 事务发布。先存好不可分割的快照再回 200，不将半成品公开。不要为了层级深而堆同义结论；需要深层逻辑时区分比较、对照、局部解释和综合机制。

按 `(feed,date,timezone,language)` 唯一存储，`id` 稳定、revision 单调。中央调度器按各频道时区每天生成；客户端不负责抓文献或在本机调用模型。两个语言版本单独生成／审核，英文未就绪回202／404，不回中文并伪标en。条件GET正确匹配ETag时回304，内容变更则revision和ETag一起更新。

应用启动、回前台及活跃期间每分钟检查是否到请求时间；有当日成功缓存时6小时内跳过网络；午夜按配置时区获取新一天。选择历史日期后仅显示缓存，点「获取／刷新」才请求；「今天」恢复跟随当前日。手动刷新跳过自动等待，但同一工作区不允许并行摘要请求。后台／完全退出不驻留同步进程；离线跨天后，下次启动只补当前日，不自动补齐每个缺失日。

最多缓存30条、JSON编码总量不超过12MB（跨服务器、语言及频道共用），按最近下载保留，超限自动淘汰旧条目；个人实验与文献库不受影响。关闭实验室保留缓存，但隐藏页面并停止自动请求；正在返回的旧请求因配置／语言已变化不会提交。来源和科学解释仍是待人工核验的服务器数据。

## 6. 服务端联调与代码位置

先用示例提供固定响应。公开测试频道无需令牌；私有频道用服务器自有鉴权签发仅读令牌。推荐测试顺序：200＋ETag → 条件GET304 → revision2＋新ETag → 404 → 401/403 → 429＋Retry-After → 错日期／语言／版本／引用／环 → 超限响应。不存在客户端自动注册、登录刷新、推送、上传或服务端写回接口；需要这些功能时应单独版本化定义，不能复用下载契约偷加写操作。

```sh
curl -i --get 'https://research.example.org/api/v1/research/daily' \
  --data-urlencode 'date=2026-10-02' \
  --data-urlencode 'timezone=Asia/Shanghai' \
  --data-urlencode 'language=en' \
  --data-urlencode 'feed=default' \
  -H 'Accept: application/json'
```

示例域名没有本项目部署的服务，请替换实际地址；不要把私有令牌直接写在可分享的日志／命令示例里。

实现：`PersonalCore/ResearchDigest.swift`（契约、来源与图谱校验）、`PersonalMac/ResearchDigestClient.swift`（HTTPS GET／流式边界）、`ResearchDigestStore.swift`（隔离缓存、版本和重试）、`LaboratoryViews.swift`（设置与阅读界面）、`WorkspaceView.swift`（开关导航与活跃期同步）。新增测试 `ResearchDigestTests.swift` 使用 URLProtocol 模拟网络和项目目录内隔离 SQLite；不访问真实用户数据、令牌或中央服务器。
