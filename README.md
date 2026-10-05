# BioRA — Research Assistant

<p align="center">
  <img src="Resources/README/biora-hero.png" alt="BioRA research argument map: a central scientific question branching into connected evidence trees" width="100%">
</p>

<p align="center"><em>From scientific questions to experiments, evidence, and the next result.</em></p>

BioRA is a local-first, native macOS research workspace for life-science researchers. It is designed around the way research actually moves: ask a question, plan and run experiments, capture what each step took, read papers critically, and connect evidence to a clear research mainline.

BioRA is a personal research assistant—not a laboratory management system. It does not control instruments, validate scientific conclusions, or replace experimental and safety judgment.

[简体中文](#简体中文)

## What BioRA can do

### An assistant that works across the workspace

Describe what you want in natural language. BioRA first classifies the intent into a supported function, then follows the appropriate workflow and response structure. You do not have to choose “scheduling” or “Protocol” before you can talk to it.

- Ask research and workspace questions in a conversational flow.
- Draft and revise structured Protocols.
- Plan experiments and find a feasible schedule.
- Work with personal instruments, experiments, scientific questions, literature, and workspace navigation where the relevant workflow is available.
- Review proposed changes before they are saved to your workspace.

Configure multiple compatible model providers and models, then choose which model handles each task. API keys are kept in the macOS Keychain. You can switch the app language; assistant prompts and generated content follow the selected language. If you prefer using a model in your browser, selected workflows can provide a prompt for you to copy and paste the result back for review.

### Protocols that preserve experimental structure

Protocols keep their original procedural hierarchy:

```text
block → subblock → atomic step
```

Each Protocol brings together an experiment objective, a materials checklist, the nested procedure, principles, and precautions. Materials are not mistaken for actions. Protocols are versioned, and procedural steps can include durations and resource requirements.

After a run, record the sample count and actual duration of each step. Per-step timing history can inform future planning, with calibration settings to distinguish fixed batch work from sample-dependent work. Unknown times remain uncertain rather than being silently treated as reliable estimates.

### Scheduling that combines algorithms and model assistance

The assistant turns a request into structured scheduling inputs; a deterministic planner evaluates ordering and feasibility. Planning can account for step dependencies, estimated durations, instrument availability, and personal availability. Calibrated timing observations can improve estimates over repeated runs.

The schedule is a plan for the researcher. It is not a reservation made with an external instrument system, and it does not operate equipment.

### Scientific questions as a mainline with evidence trees

Build a legible argument rather than a pile of disconnected cards:

- Organize the mainline from the scientific question through primary results and the reasons to pursue the next result.
- Grow multi-level conclusion trees below each mainline result; atomic experiments support or challenge lower-level conclusions, not the mainline directly.
- Connect trees when evidence or conclusions are genuinely related.
- Keep planned experiments distinct from recorded observations, and capture how evidence supports or limits a conclusion.
- Explore the graph on a navigable canvas, including zoom, pan, focused/full-screen views, and node details.

BioRA helps organize an argument; it does not determine that an experiment proves a claim.

### Literature and paper analysis

- Import a PDF and extract text locally; use macOS Vision OCR when needed.
- Send selected extracted content to the model you configured to create a reviewable research graph.
- Inspect a paper's mainline, conclusions, evidence, citations, and limitations before adopting anything into your own research.
- Relate panels within a figure, and add or refine figure-panel logic by reviewing a generated proposal or pasting a result from your own model website.
- Keep imported analysis as a draft until you review it.

The local PDF reader does not mean that PDF content stays local after you send it to a model. Extracted text or selected context is sent to the model provider you choose; check that provider's retention and privacy terms.

### Themes, language, and optional research digest

- Switch between the available visual themes instead of being locked into a single system appearance.
- Choose Chinese or English; prompts and newly generated content use the selected language.
- Optionally enable the experimental “daily research digest” feature in settings and connect to a server you configure. It is off by default, and BioRA does not include a hosted digest service.

## Privacy and data

- The workspace database and PDF archive are stored as local files and are **not encrypted by BioRA**. Use FileVault and private backups if you need disk-at-rest protection.
- API keys are stored in the macOS Keychain, not in the workspace export.
- Model requests go directly to the endpoint you configure. Text you choose to include—such as extracted PDF passages—is sent to that provider.
- The optional research digest contacts only the HTTPS server you configure. Review [the API contract](docs/BIORA_DAILY_RESEARCH_API.md) before enabling it.
- BioRA has no built-in account sync or team collaboration service in this personal edition.

## Requirements

- macOS 14 or later
- Xcode with the Swift 6 toolchain
- No third-party Swift Package dependencies; the app uses Apple frameworks and system SQLite.

## Build and run from source

```sh
zsh scripts/test.sh
zsh scripts/build.sh
open build/BioRA.app --args \
  --data-dir "$HOME/Library/Application Support/BioRA"
```

The test and build scripts create their generated files under the ignored `build/` directory. For a distributable download, the app still needs an appropriately signed and notarized release build; the local build script uses ad-hoc signing.

## Documentation

- [Protocol structure and review](docs/PROTOCOL_DOCUMENT.md)
- [Experiment timing and calibration](docs/BIORA_EXPERIMENT_TIMING.md)
- [Scientific question and evidence graph](docs/PERSONAL_SCIENCE_GRAPH.md)
- [PDF reading and paper graph](docs/PERSONAL_PDF_GRAPH.md)
- [Optional daily research digest API](docs/BIORA_DAILY_RESEARCH_API.md)
- [Publishing checklist](PUBLISHING.md)

## Contributing

Bug reports and focused contributions are welcome. Please do not include private Protocols, experiment records, PDFs, model responses, credentials, or workspace databases in issues or pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License and release status

The project source in this repository is licensed under [Apache-2.0](LICENSE). The app icon and README hero artwork were created specifically for this BioRA repository copy; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Source availability does not imply that a signed, notarized macOS download is available.

---

## 简体中文

BioRA 是面向生命科学研究者的本地优先 macOS 原生研究工作区。它围绕真实研究流程设计：从科学问题出发，安排并执行实验，记录每个步骤的实际用时，阅读论文，再把证据组织成清晰的研究主线。

BioRA 是个人研究助手，不是实验室管理系统；它不会控制仪器、验证科学结论，也不能代替研究者对实验和安全的判断。

### 完整功能介绍

#### 能操作工作区功能的实验助手

直接用自然语言描述需求。助手先判断用户意图，再进入对应的专用流程；你不必先手动选“排程”或“Protocol”。

- 以对话方式询问研究和工作区信息。
- 创建、修改结构化 Protocol。
- 规划实验并寻找可行的排程。
- 在对应流程中管理个人仪器、实验、科学问题、文献和页面导航。
- 保存到工作区前审阅助手提出的更改。

可以配置多个兼容的模型服务和模型，并按任务选择模型。API Key 存储在 macOS 钥匙串中。切换界面语言后，助手提示词和生成内容也会使用所选语言。部分流程还支持复制提示词到浏览器中的模型网站，再粘贴结果回来审阅。

#### 保留层次结构的 Protocol

Protocol 保留原有操作层次：`block → subblock → atomic step`。每份 Protocol 包含实验目的、材料清单、分层步骤、实验原理和注意事项。材料不会被误当成操作步骤。Protocol 带有版本；具体步骤可以设置耗时和资源要求。

每次实验后可记录样品数量及每个步骤的实际用时。各步骤可积累耗时历史，并按设置区分批次固定工作与随样品数量变化的工作，为后续计划提供更贴近实际的估算。未知耗时会保留为不确定值。

#### 经典算法与模型协作的排程

助手将自然语言请求整理成结构化输入，确定性排程算法负责评估顺序和可行性。排程可综合步骤依赖、预计时长、仪器可用时间和个人可用时间，并利用逐渐积累的实际耗时记录优化估算。

排程是给研究者参考的计划，不会替你向外部仪器系统预约，也不会操作设备。

#### 以主线和证据树组织科学问题

把研究论证整理成清楚的逻辑，而不是互不相关的卡片：

- 从科学问题出发，串联主线结果，以及为什么需要继续研究下一个结果。
- 每个主线结果下可以生长多层结论树；原子实验应先支持或挑战下层结论，不能直接连到主线。
- 当不同树之间确有证据或结论关系时，可以建立跨树连接。
- 区分计划中的实验与已记录的观察，并记录证据如何支持结论及其局限。
- 在可平移、缩放的画布中浏览关系，并使用专注或全屏视图查看图谱。

BioRA 帮助整理论证，不会自行判定某个实验已经证明某项结论。

#### 文献阅读和论文分析

- 导入 PDF，在本机提取文字；必要时使用 macOS Vision OCR。
- 选择内容发送给你配置的模型，生成可审阅的研究图谱。
- 审阅论文主线、结论、证据、引用和局限，再决定是否纳入自己的研究。
- 梳理论文图中不同面板之间的逻辑；可审阅模型草稿，也可从自选模型网站粘贴结果补充。
- 论文分析先作为草稿，确认后再保存。

本地 PDF 阅读不代表 PDF 内容在模型分析时仍留在本机。你选取发送的提取文字或上下文会传给所选模型服务，请先检查服务商的数据留存和隐私条款。

#### 主题、语言和可选研究摘要

- 可切换不同界面主题，不会被锁定在单一系统外观。
- 可选择中文或英文；提示词及新生成内容跟随所选语言。
- 可在设置中选择开启实验性的“每日研究摘要”，并连接自己配置的服务器。该功能默认关闭，本项目不提供托管摘要服务器。

### 隐私和数据

- 工作区数据库和 PDF 归档以本机文件保存，**BioRA 不会加密这些文件**。如需磁盘静态加密，请使用 FileVault，并妥善保管备份。
- API Key 存于 macOS 钥匙串，不包含在工作区导出中。
- 模型请求直接发往你配置的服务；选择附加的 PDF 提取文字等内容也会发送给该服务。
- 可选研究摘要只连接你配置的 HTTPS 服务器。启用前请阅读[接口文档](docs/BIORA_DAILY_RESEARCH_API.md)。
- 此个人版不包含内置账户同步或团队协作服务。

### 运行要求和构建

需要 macOS 14 或更新版本，以及带 Swift 6 工具链的 Xcode。项目没有第三方 Swift Package 依赖；SQLite 和系统框架来自 macOS。

```sh
zsh scripts/test.sh
zsh scripts/build.sh
open build/BioRA.app --args \
  --data-dir "$HOME/Library/Application Support/BioRA"
```

测试和构建生成物位于被 Git 忽略的 `build/` 目录。正式分发的 macOS 下载包仍需正确签名和公证；本地构建脚本使用临时签名。

### 许可证和发布状态

本仓库项目源码采用 [Apache-2.0](LICENSE)。App 图标和 README 主题图均为本 BioRA 仓库专门生成，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。开源源码不代表已经提供签名、公证的 macOS 下载包。
