---
title: "DeepSeek Harness：把智能体框架做成插件化的 K8s"
date: 2026-08-20 14:00:00
tags:
  - AI
  - 智能体
  - 开源
  - 架构分析
  - DeepSeek
categories:
  - 创业思考
---

8 月 13 日，DeepSeek AI 开源了一个名为 DeepSeek Harness 的项目。7 天之后，GitHub 星数冲到了 16.7 万，fork 数 1.78 万。

这个数字放在今年 8 月的开源市场里，大概相当于什么水平？OpenAI 在 7 月发布 o3 时，相关的 demo 仓库也没能这么快冲到 16 万星。167 万星的 OpenAI-CLI 用了整整一个月。

但数字不是这篇文章的重点。重点是：**这个项目到底是个什么东西，它想解决什么问题，它的方法论是否成立。**

因为说实话，167 万星背后有一个非常不寻常的架构理念——"一切皆插件"（Everything is a Plugin）。这个理念如果成立，它可能是智能体开发领域最重要的一次范式转移。

---

## 一、这是什么：一个被低估的"基础设施"

先说结论。DeepSeek Harness（以下简称 dsh）不是一个具体的 AI 应用。它不是聊天机器人，不是代码助手，不是自动化工作流。

**它是一套用于构建 AI 智能体的基础设施框架。**

打个比方——你不能用 Kubernetes 去"跑一个网站"，Kubernetes 是让你构建和运行容器的平台。同样，你也不能用 dsh 去"问一个问题"，dsh 是让你构建和运行智能体的平台。

它的核心定位：

- 提供模型适配层、工具注册表、会话管理、沙箱隔离、UI 交互等全套基础设施
- 所有组件都是可替换的插件
- 开发者通过组合插件来构建自己的智能体产品

官方一句话："Everything is a Plugin."

目前处于开发者预览（Developer Preview）阶段，版本 0.1.0-rc.8，今日刚发。项目明确声明"未来会有破坏兼容性的变更"。

---

## 二、167 万星的背后：不只是品牌效应

167 万星 / 7 天这个速度，如果只看数字，大概率会觉得是 DeepSeek 品牌效应 + 自动加星的产物。但仔细看代码结构和文档质量，这个项目的水准确实配得上这个关注度——至少配得上"认真看一下"。

### 2.1 代码规模

用 pygount 风格的统计口径来看：

| 指标 | 数值 |
|------|------|
| 总文件数 | 9,060 |
| 包数（package.json） | 255 |
| 顶级包目录 | 50 |
| TypeScript 源码 | ~2,700 文件 |
| Markdown 文档 | ~2,469 文件 |
| Cordis YAML 配置 | ~1,297 文件 |
| 仓库大小 | ~118 MB |

50 个核心包，255 个 npm 包，9000 多个文件。这个体量在开源项目里不算小——相当于一个中等规模的企业级前端框架的体量。

### 2.2 文档质量（罕见）

这是让我最意外的部分。一个 7 天的项目，文档建设达到了这个程度：

- 架构总览文档（architecture.md）
- Cordis 框架入门教程（7 步完整教程）
- 40+ 个子系统逐一有独立文档
- 10+ 篇实战 Cookbook
- 能力缝设计文档
- 配置目录 / 工具目录 / 事件拓扑图
- 防御性编程模式
- **4 篇事故复盘（Postmortem）**
- 中英双语全套翻译，且有机器翻译配对校验系统

尤其是事故复盘这一块——一个项目才 7 天，就已经写了 4 篇 postmortem，说明团队内部确实在认真对待工程质量，而不是发个 README 就跑。

事故复盘的标题包括：
- ACP 默认导出丢失 inject 问题
- JS 表达式导致文件系统工具被禁用
- Web Agent GUI 反馈循环
- Landlock 部分通知误判子进程失败

这些不是 marketing 出来的内容，是一个工程团队在真实开发中踩过的坑。

---

## 三、核心架构：Cordis 与"一切皆插件"

现在进入本文最核心的部分。dsh 的架构理念是否成立，取决于 Cordis 这个框架是否足够强大和优雅。

### 3.1 Cordis：是什么

Cordis 是 dsh 底层自研的 TypeScript 插件框架，已经 vendor 进仓库。它有论文支撑——《A Programming Paradigm for Spatiotemporal Composability》。

核心概念只有四个：

| 概念 | 含义 |
|------|------|
| **Context** | 共享上下文，所有插件注册和发现服务的中心 |
| **Service** | 可注入的服务，有生命周期管理 |
| **Events** | 类型化事件，插件之间的通信机制 |
| **Effects** | 可逆的副作用，插件卸载时自动清理 |

Cordis 的设计哲学是"时空可组合性"——空间上，插件可以在不同的 scope 里隔离；时间上，插件注册的生命周期是精确可逆的。

### 3.2 "一切皆插件"到底意味着什么

这句话不是 marketing slogan，而是贯穿整个架构的设计决策。

在 dsh 里：
- **模型适配器是插件** — 换一个 LLM 后端，换一个插件
- **工具注册表是插件** — 增加一个新工具，写一个插件
- **会话日志是插件** — 想改成 SQLite 存储，换一个插件
- **Agent 循环本身是插件** — 整个推理引擎都可以替换
- **文件系统是插件** — 从本地到远程沙箱，统一接口
- **Shell 执行是插件** — Bash/PwSH 通过统一的 shell seam 接入
- **沙箱是插件** — Linux Landlock / Windows ACL 各自一个插件

这意味着：

> 没有"核心代码不能改"的问题。你可以替换任何一层。

### 3.3 能力缝（Capability Seam）

这是 Cordis 最精妙的设计。每个可替换能力有三角色：

```
Service Definition (接口定义)
        ↓
Service Provider (实现提供者)
        ↓
Consumer (消费者，通常是工具)
```

一个能力不是一个插件，而是三个角色的组合。添加一个新能力意味着设计所有三个角色。

这个设计的威力在于：**更换一个 Provider，整个消费链自动更新**。

举例：把文件系统 Provider 从"本地"换成"E2B 远程沙箱"——Bash、PTY、LSP 全部自动跟着迁移到远程环境，不需要对消费者做任何修改。

---

## 四、Agent 循环设计：Turn 与 Step 模型

dsh 的 Agent 循环设计有一个清晰的 Turn/Step 层次：

```
turn/start
  ↓ claim next-step input + one queued message
  ↓ assemble prompt sections + tool schemas
  ↓
  agent/pre-step  (可重写或拒绝消息)
  ↓
  step/start
  ↓
  append user/message → derive model history → LLM request → assistant/chunk*
  ↓
  tool/call* → tools/execute → tool/result*
  ↓
  step/end
  ↓
  如果有更多待处理 → 下一个 step
  ↓
turn/end
```

几个关键设计点：

**Step** = 一次模型请求 + 调用的工具。**Turn** = 零或多个 Step。一个 Turn 在它的第一条输入被消费之前保持"开放"状态，当没有更多待处理内容时关闭。

**agent/pre-step** 事件是关键拦截点——监听者可以重写传入的消息，或者直接拒绝。被拒绝的 turn 仍然会在日志中记录为"花费了 0 个 step 的 turn"。

**agent/turn-stopping** 是一个特殊事件，没有 next() 调用，是串行的——这意味着任何监听者都可以无条件终止一个 turn。

### "Model-visible means logged"

这是整个会话管理的核心不变量：**任何到达模型请求的内容都必须可以从日志中重建出来**。

这意味着：
- 分叉会话（fork）、恢复（resume）、转录（transcript）、遥测（telemetry）、持久化——全部从日志派生
- 新增一种模型可见的输入，需要扩展 SessionEventMap
- 运行时不变量（invariant）会强制校验

这比大多数 agent 框架要严格得多。很多框架的 agent 在运行时会有一些"隐式状态"——比如中间变量、缓存、临时计算——这些在 dsh 的设计里都是不允许的。

---

## 五、50 个核心包的功能全景

用一张图来理解整个仓库的结构：

```
deepseek-harness/
├── vendor/              # 自托管框架层（Cordis + 8 个工具库）
│   ├── cordis/          #   核心插件框架
│   ├── cosmokit/        #   配置工具
│   ├── schemastery/     #   Schema 验证
│   ├── hmr/             #   热模块替换
│   ├── loader/          #   插件加载器
│   ├── group/           #   分组工具
│   ├── include/         #   配置包含
│   ├── timer/           #   定时器
│   └── logger-console/  #   日志
│
├── packages/            # 50 个核心包
│   ├── 核心引擎
│   │   ├── core/        #   Agent 接口 / Session / System Prompt / Tools / Scope
│   │   ├── boot/        #   启动 / Profile 组合 / CLI
│   │   ├── bundle/      #   Web App / Headless / Base 分发
│   │   └── llm/         #   模型适配层（DeepSeek / PI-AI）/ Token 计量 / 重试
│   │
│   ├── 交互层
│   │   ├── acp/         #   AC Agent 协议
│   │   ├── subagent/    #   子代理（fork/spawn/in-process/ACP/Claude Code/Codex）
│   │   ├── workflow/    #   工作流引擎（Ralph 工具）
│   │   ├── plan/        #   计划模式
│   │   ├── goal/        #   目标管理
│   │   └── todo/        #   任务列表
│   │
│   ├── 能力层
│   │   ├── fs/          #   文件系统（搜索/编辑/沙箱/策略）
│   │   ├── shell/       #   Bash/PwSH + 沙箱
│   │   ├── terminal/    #   持久化终端（node-pty）
│   │   ├── code-runtime/#   代码执行（Python/Worker Thread）
│   │   ├── lsp/         #   LSP 语言服务
│   │   ├── web/         #   Web 抓取 + 搜索（DeepSeek/Exa/Perplexity）
│   │   ├── mcp/         #   MCP 客户端
│   │   ├── skill/       #   技能系统
│   │   ├── compaction/  #   上下文压缩
│   │   └── context/     #   上下文注入
│   │
│   ├── 基础设施层
│   │   ├── session/     #   会话持久化 / 标题生成 / 遥测
│   │   ├── session-query/#  会话 SQL 查询
│   │   ├── storage/     #   存储（SQLite/JSON）
│   │   ├── settings/    #   设置管理
│   │   ├── credentials/ #   凭据管理
│   │   ├── sandbox/     #   沙箱策略（Landlock/ACL）
│   │   ├── guard/       #   超时策略 / 重复提醒
│   │   └── hooks/       #   Claude Code / Codex 钩子
│   │
│   └── 集成层
│       ├── e2b/         #   E2B 云端沙箱
│       ├── sdk/         #   Python SDK
│       ├── examples/    #   可运行 demo
│       └── experimental/ #  实验性特性（Agent Teams）
│
├── apps/                # 产品组装层
│   ├── cli/             #   dsh CLI 入口
│   └── web/             #   Web UI
│
└── native/
    └── landlock-run/    # Linux Landlock 原生二进制
```

值得注意的几个包：

**subagent/** — 子代理系统有 6 种 Provider：
- subagent-fork-in-process（进程内 fork）
- subagent-spawn-in-process（进程内 spawn）
- subagent-in-process-driver（进程内驱动）
- subagent-acp（ACP 协议远程）
- subagent-claude-code（调用 Claude Code）
- subagent-codex（调用 OpenAI Codex）
- subagent-dsh-sdk（Python SDK 调用）

这意味着你可以把子代理任务分发给"另一个 dsh 实例"，或者"Claude Code"，或者"OpenAI Codex"，接口完全统一。

**experimental/agent-team/** — 实验性的 Agent Teams 特性，提供 durableroster（持久化花名册）、task board（任务板）、mailbox（邮箱），实现多 agent 协作。

**compaction/** — 上下文压缩，有专门的 compaction-tool-result-pruner（工具结果修剪器）和 command-compact（命令压缩）。这对长上下文场景很重要。

**session-query/** — 会话 SQL 查询引擎，支持用 SQL 查询历史会话内容。

---

## 六、安全与沙箱设计

安全是 agent 框架的命门。dsh 在这方面做得相当彻底。

### Linux Landlock

Landlock 是 Linux 内核 5.13 引入的无特权沙箱机制。dsh 有独立的 native 包（landlock-run）实现 Landlock 沙箱——一个编译好的原生二进制，用 eBPF 程序限制进程的文件系统访问范围。

这不同于传统的 seccomp 或 AppArmor——Landlock 允许**非 root 用户**创建沙箱策略，非常适合 agent 这种需要安全隔离但不想搞复杂权限管理的场景。

### Windows ACL

Windows 端使用 ACL（访问控制列表）沙箱，通过 sandbox-windows-acl 包实现。

### 权限预设

permission-presets 包提供了预定义的权限集合——开发者不需要从零开始设计权限策略，可以直接用"文件读写 + 网络但无 shell"之类的预设。

### 运行时不变量

runtime-diagnostics 包下的 invariants 系统会在运行时检查一系列不变条件——比如"模型可见的内容必须已记录到日志中"。这不是测试时的断言，是**运行时的 invariant**。

---

## 七、工程纪律：一个 7 天项目的成熟度

看完代码后，让我最意外的是这个项目的工程纪律。

**pnpm 配置**严格到令人发指：

```yaml
# 默认拒绝所有 install/build scripts
strictDepBuilds: true  # 未列出的脚本 = 安装错误

allowBuilds:
  esbuild: true      # 真正需要的
  lefthook: true     # git hooks
  node-pty: true     # PTY 跨平台
  koffi: true        # Windows 原子写入
  '@google/genai': false       # 不需要，明确拒绝
  protobufjs: false            # 不需要，明确拒绝
```

**15 个 CI 工作流**：

- ci.yml — 全量 CI
- e2e.yml + e2b-e2e.yml — 端到端测试（含云端沙箱）
- landlock-run.yml — Landlock 安全测试
- sandbox.yml — 沙箱安全测试
- python-release.yml — Python SDK 发布
- pi-ai-provider-e2e.yml — PI-AI 模型后端集成测试
- docs-pages.yml — 文档站部署
- expected-filenames.yml — **文件名规范检查**（这个太离谱了）

一个"文件名规范检查"的 CI 工作流——意味着仓库里所有文件的命名都要符合预设规则。

**测试体系**：

- vitest 主测试框架
- 覆盖率分区（coverage partitions）
- e2e 测试覆盖云端沙箱
- Web stress tests（独立配置）
- Web performance tests（独立配置）

**oxlint** — 用 Rust 写的 JS/TS lint 工具，比 ESLint 快 3-60 倍。dsh 用 oxlint 做 lint，有独立的 staged 配置文件。

---

## 八、Python SDK 与单文件部署

仓库包含一个完整的 Python SDK：

- `python/sdk/` — Python 包（pyproject.toml）
- `python/sdk-runtime/` — **单文件 exe 部署运行时**

单文件 exe 部署是什么意思？就是把整个 Node.js runtime + dsh 核心 + 插件打包成一个单独的可执行文件。Python SDK 调用这个 exe，通过 JSON-RPC 协议通信。

这个设计很聪明：Python 开发者可以用 Python 写 agent 逻辑，但实际执行引擎是高性能的 TypeScript 实现。

---

## 九、我的评估：优势和风险

### 优势

**1. 架构理念真正落地**

"一切皆插件"不是喊口号——50 个包，每个都是独立可替换的单元。模型适配器、文件系统、Shell、沙箱、子代理、UI——全部可插拔。这种设计在开源 agent 框架中是罕见的。

对比：
- LangChain：插件化更多是"可组合"而不是"可替换"
- CrewAI：主要是多 agent 编排，不是基础设施层
- AutoGen：微软出品，但架构是"agent 对话"而不是"插件缝"
- dsh：真正的能力缝设计，Provider 替换影响整个消费链

**2. 文档质量罕见**

40+ 子系统文档、7 步 Cordis 教程、4 篇事故复盘、完整中英双语——一个 7 天的项目做到这个程度，说明团队投入是认真的。

**3. 安全考虑周全**

Landlock + ACL 双平台沙箱、权限预设、运行时不变量、strictDepBuilds——安全不是事后补的，是架构设计的一部分。

**4. 子代理系统统一**

能 fork 进程内、spawn 进程内、用 ACP 远程、调 Claude Code、调 Codex——一个接口覆盖所有场景。

### 风险与不确定性

**1. 品牌效应 ≠ 社区活力**

167 万星 / 7 天，大概率有 DeepSeek 品牌预热的成分。0 open issues 说明要么项目完美，要么社区还没真正用起来。真实价值要等 rc 稳定后看社区 PR 和讨论质量。

**2. 开发者预览 = 不承诺兼容性**

明确写了"THERE WILL BE COMPATIBILITY-BREAKING CHANGES"。这意味着现在写的插件，rc.9 可能就挂了。生产环境不要碰。

**3. 学习曲线陡峭**

50 个包、4 个概念（Context/Service/Events/Effects）、能力缝的三角色设计——这不是一个"npx 就跑"的玩具项目。要真正用好它，需要理解 Cordis 的时空可组合性理念。

**4. 模型后端有限**

目前只有 DeepSeek 和 PI-AI 两个后端。OpenAI、Anthropic、Google 需要自己写适配器。虽然适配器是插件化的——理论上不难写——但目前生态不成熟。

**5. 中文社区的独特性**

README 里有企微群和微信公众号的二维码，说明 DeepSeek 在构建一个以中文开发者为主的社区生态。这对中国开发者是优势，对国际社区可能是壁垒。

---

## 十、定位判断：这可能是 Agent 基础设施的"Kubernetes 时刻"

回到最初的问题——dsh 到底是什么？

我认为它的野心是成为 **agent 开发的基础设施层**，类似于：

- Kubernetes 之于容器编排
- Spring Boot 之于 Java 企业开发
- pnpm workspace 之于 Node.js monorepo

如果这个定位成立，dsh 的成功不取决于它自己的功能有多好，而取决于：
1. 插件生态是否繁荣
2. 开发者是否愿意围绕它构建产品
3. "能力缝"这个设计理念是否被社区接受

目前 167 万星只是一个开始。真正的考验在 rc 稳定后——社区会写出多少高质量的插件？会不会有人基于 dsh 构建出有影响力的 agent 产品？

---

## 十一、给开发者的建议

**如果你在考虑学习或尝试 dsh：**

- 先读 Cordis primer（`docs/cordis-primer.md`）——30 分钟入门
- 然后读 7 步 Cordis 教程（`docs/cordis-tutorial/`）——2 小时
- 用 `npx @deepseek-ai/dsh web` 跑起来试试——5 分钟
- 不要急着写插件，先理解"能力缝"的三角色设计

**如果你在评估 dsh 作为技术选型：**

- 目前是 Developer Preview，不要用于生产
- 核心架构理念有说服力，但需要等 rc 稳定观察生态
- 对比 LangChain / CrewAI / AutoGen 时，关注"可替换性"而非"功能列表"
- 关注社区插件增长速度和 PR 质量，这比 star 数更有意义

---

## 最后

6 天 167 万星，这个数字本身已经说明问题了。DeepSeek 不仅仅是在做模型，它在构建整个 agent 生态的基础设施。

从 DeepSeek-V3 的开源，到 R1 的推理开源，再到现在的 Harness——DeepSeek 的战略路径很清晰：**先用模型建立影响力，再用工具链构建生态，最终成为 agent 时代的基础设施提供者。**

这个项目值不值得关注？值得。
这个项目现在能不能用？不能。
这个项目 6 个月后是什么样子？这取决于社区。

> "最好的开源项目不是 star 最多的，而是 6 个月后还在被认真维护、还在被社区使用的。"

---

*参考链接：*
- [deepseek-ai/deepseek-harness (GitHub)](https://github.com/deepseek-ai/deepseek-harness)
- [Cordis 论文: A Programming Paradigm for Spatiotemporal Composability](https://github.com/cordiverse/paper)
- [Cordis 框架 (GitHub)](https://github.com/cordiverse/cordis)
- [DeepSeek Harness 官网](https://deepseek.com/harness)