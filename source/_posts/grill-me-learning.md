---
title: "Grill-Me：让 AI Agent 学会先'拷问'再动手"
date: 2026-08-11
tags: [AI, Agent, 编程, 学习]
description: "Grill-me 是一个正在崛起的 AI Agent 技能范式——在执行任何任务前，Agent 先对用户进行苏格拉底式拷问，逼清意图再动手。本文深入剖析它的机制、生态和真实价值。"
---

# Grill-Me：让 AI Agent 学会先"拷问"再动手

---

## 一、一个让人血压升高的 AI 对话

你可能经历过这样的场景：

> **你**："帮我把这个函数的性能优化一下。"
> **AI**：*[花了 30 秒生成了一段代码，改了你根本不想改的部分，用了你根本不想要的库]*

或者更糟的：

> **你**："重构一下这个模块。"
> **AI**：*[删掉了你花了三周写的业务逻辑，替换成了"更优雅"的三行代码，编译都过不了]*

这个问题的根源是什么？不是 AI 不够聪明，而是 **AI 太急于执行**。

大语言模型有一个根深蒂固的行为模式：收到指令 → 立即行动。它被训练成"有用"，而"有用"的最短路径就是赶紧给你输出点什么。但人类的需求从来不是写清楚的一行命令——它是模糊的、有上下文的、甚至自相矛盾的。

2026 年夏天，GitHub 上出现了一个有意思的标签—— **`grill-me`**。它代表了一种截然不同的 AI Agent 行为范式：**在动手之前，先像面试官一样把用户拷问一遍。**

---

## 二、Grill-Me 到底是什么

### 2.1 定义

"Grill" 在英文里有"烤"的意思，但在美式口语中更常见的用法是 "grill someone"——**盘问、拷问**。这个词最早在社交媒体上被 AI 学习爱好者用来形容一种学习法：让 AI 不停地追问你，逼你暴露知识盲区（比如"让 ChatGPT 用最难的问题 grill 我"）。

到了 2026 年，这个概念被反转了——**不是让 AI grill 你，而是让 AI grill 你自己给它的任务**。

具体来说，一个 "grill-me" 模式的 Agent 会在收到任何实现请求后，启动这样的流程：

1. **先读代码库**（只读，不改动）
2. **逐条追问用户**——每个问题一次，等用户回答
3. **追问完毕后再写规划文档**（PLAN_v1.md）
4. **规划经受审核或反驳**（Reviewer/Criticizer 轮次）
5. **最后才执行**——而且执行前还要再确认一次

这听起来像过度设计，但它解决的是一个真实痛点：**AI Agent 的执行速度与人类意图的模糊度之间的巨大鸿沟**。

### 2.2 核心项目：Optim-Agent/optim-plans

当前最成熟的实现来自 [Optim-Agent/optim-plans](https://github.com/Optim-Agent/optim-plans)，一个 2026 年 8 月获得 484 stars 的开源项目。它的定位很精准：

> "Human-in-the-loop planning and refinement with a current-session execution handoff."

翻译成人话：**在实施前，用规划+审核+确认的闭环把模糊需求变成可执行的蓝图，然后把蓝图交回当前会话去执行。**

它不是一个新的 AI 框架，而是一组 **Agent 技能（Skills）**——可以被 Claude Code、OpenAI Codex 等 AI 编程助手加载的提示词包。截至 0.3.0 版本，它提供了五个技能：

| 技能 | 适用场景 | 追问数量 | 核心差异 |
|------|----------|----------|----------|
| `create-a-small-plan` | 小范围改动，影响有限 | 1-3 个 | 一次审核轮次，轻量 |
| `create-a-plan` | 中等复杂度，有风险 | 5-10 个 | 可研究外部资料，最多 5 轮审核 |
| `create-a-big-plan` | 高风险/开放式 | ≥10 个（无上限） | 审核直到收敛，无轮次限制 |
| `diagnose-before-plan` | Bug/故障/事故 | 先看证据再问 | 先出 RCA 报告，再决定是否规划 |
| `reference-before-plan` | 需要参考外部项目/论文 | ≥10 个 | 必须下载 ≥3 个可信参考后再规划 |

这个分级本身就很有意思——它承认了一个事实：**不是所有任务都需要被"拷问"十轮**。修一个 typo 不值得问十个问题，但重构整个鉴权模块，不问清楚就动刀就是灾难。

---

## 三、为什么"先拷问"能起作用

### 3.1 人类需求的"冰山模型"

当你对 AI 说"优化这个函数"时，你脑子里其实有这些东西：

```
可见的部分（你说出来的）：
┌─────────────────┐
│ "优化性能"       │  ← 这只是一个锚点
└─────────────────┘
            ↓
不可见的部分（你没说但决定了正确方案）：
┌─────────────────────────────────────┐
│ • 是延迟优化还是吞吐量优化？         │
│ • 能不能接受引入新依赖？             │
│ • 有兼容性要求吗？（旧版 API 调用方） │
│ • 测试覆盖率够不够支撑重构？         │
│ • 性能瓶颈真的在这里吗？             │
│ • 团队对复杂度的容忍度是多少？       │
└─────────────────────────────────────┘
```

传统的 AI 对话中，这些隐形需求要么靠猜，要么根本没人问。Grill-me 做的就是把冰山下的东西一条条挖出来。

### 3.2 "一次只问一个问题"的设计哲学

Grill-me 最反直觉的设计决策是：**每次只问一个问题**。

大多数人的直觉是：把问题一次问完效率更高。但 Grill-me 的设计者显然深思熟虑过：

- **认知负荷**：人类面对 10 个同时出现的问题会疲劳、会敷衍地回答"都行""你定"。一次一个，每个问题都能得到认真思考。
- **决策树展开**：第一个问题的答案决定了第二个问题问什么。如果同时问"要不要引入 Redis？"和"要不要加缓存层？"——这两个问题本身就是耦合的，必须先确定前者才能问后者。
- **用户控制权**：每次只面对一个决策，用户始终感觉自己在掌控方向，而不是被 AI 用 10 个问题轰炸到崩溃。

### 3.3 Auto-complete 的边界

Grill-me 允许用户回答 "Auto-complete"（自动补全），但这条退路被严格限制了：

> "Auto-complete may choose planning and refinement recommendations, but **never** native execution, destructive cleanup, install waivers, deployment, merge, push, or credential use."

翻译：AI 可以帮你选"用什么方案"，但永远不能替你决定"执行/部署/推送/用你的密钥"。这是一个非常聪明的人性化设计——**把选择权分级，低风险的决定可以自动化，高风险的决定必须人类拍板。**

---

## 四、工作流程深度拆解

让我们用 `create-a-plan`（中等复杂度场景）来完整走一遍：

### 阶段 0：只读侦察

```
Agent 行动：
┌──────────────────────────────────────┐
│ 1. git clone / 读取目标仓库           │
│ 2. 分析目录结构、依赖、测试覆盖       │
│ 3. 理解代码风格和架构模式             │
│ 4. 不写任何东西，只积累上下文          │
└──────────────────────────────────────┘
```

这一步很关键。很多 AI Agent 跳过这步，直接根据用户的一句话就开始写代码——结果写出来的东西跟仓库里的风格格格不入。Grill-me 强制先"读房子再装修"。

### 阶段 1：逐条拷问

```
Q1: [Agent] 你希望这次优化聚焦在哪个方面？
    [选项] A) 响应延迟  B) 内存占用  C) 代码可维护性  D) Other
    [你] A
    ↓
Q2: [Agent] 根据代码分析，延迟瓶颈主要在数据库查询。
    你希望：
    [选项] A) 加查询缓存  B) 优化 SQL 本身  C) 引入连接池  D) Other
    [你] B
    ↓
Q3: [Agent] 优化 SQL 可能影响现有调用方。需要保持向后兼容吗？
    [选项] A) 必须完全兼容  B) 可以接受 minor breaking changes  C) Other
    [你] A
    ...
```

每个问题都遵循一个固定格式：
1. **推荐选项排第一**——Agent 不是瞎猜，它基于代码分析给出建议
2. **"Other" 排在倒数第二**——总留一扇门给你表达"以上都不是"
3. **"Auto-complete" 排在最后**——你想交给我也行，但这是最后的退路

### 阶段 2：范围锁定

所有问题问完后，在写规划前，有一个**强制的最终确认**：

> "现在来确认最终范围：
> 1. **No more requirements** — 范围已定，开始写 PLAN_v1.md
> 2. **Add more requirements** — 我还有约束要加
> 3. Other
> 4. Auto-complete"

这是整个流程的"刹车机制"。它防止了 Agent 在问完 10 个问题后自作主张写规划——用户还有最后一次机会说"等等，你理解偏了"。

### 阶段 3：规划文档

`PLAN_v1.md` 的格式非常严谨，包含：

- **Goals** — 目标（稳定 ID）
- **Non-goals** — 非目标（明确什么不做）
- **Requirements** — 需求
- **Constraints** — 约束
- **Implementation items** — 实施项
- **Acceptance criteria** — 验收标准
- **Verification** — 验证方法
- **Risks** — 风险
- **Repo evidence** — 代码库证据
- **External evidence** — 外部证据
- **Decisions** — 决策记录
- **Verifier Checklist** — 每个验收标准的可验证条件

注意 `Non-goals` 这个字段——它逼着 Agent 和用户**明确什么不做**。这比明确做什么更重要，因为"不做"的边界定义了方案的克制程度。

### 阶段 4：审核/反驳

规划写完后，进入 refinement（精炼）阶段，两种模式：

| 模式 | 角色 | 工作方式 |
|------|------|----------|
| **Reviewer** | 友善的审校者 | 检查正确性、遗漏、风险、测试覆盖 |
| **Criticizer** | 对抗性质疑者 | 攻击隐藏假设、边缘情况、逻辑漏洞 |

每一轮最多暴露 5 条高优先级发现。`create-a-plan` 最多 5 轮，`create-a-big-plan` 直到收敛为止。

### 阶段 5：执行交接

最后一步，Agent 问一个不带 Auto-complete 选项的问题：

> "现在执行这个规划吗？
> 1. Execute this plan now with normal Prime Agent tools
> 2. Stop after planning
> 3. Other"

注意这里没有 Auto-complete——**执行这个动作永远不能自动完成**。这是整个流程中最硬的边界。

---

## 五、生态：Grill-Me 正在扩散

Grill-me 不是一个孤岛项目。在 GitHub 上搜索 `grill-me` topic，有 12 个公开仓库使用这个标签。除了 Optim-Agent，还有几个值得注意的：

### 5.1 Hongdosan-spec-driven-orchestra

这个项目把 Grill-me 作为 **Spec-Driven Development（SDD）五音阶** 的一部分：

```
SDD 五音阶：
┌──────────────────────────────────┐
│ Karpathy 4 Principles            │  ← 来自 Andrej Karpathy
│ Grill-me                         │  ← 拷问澄清
│ Verification Design              │  ← 先设计验证
│ Handoff                          │  ← 交接规范
│ Harness                          │  ← 测试夹具
└──────────────────────────────────┘
```

这里 Grill-me 被定位为一个"技能"，和其他方法论并列。有趣的是，它被放在了 Karpathy 四原则之后、验证设计之前——**先想清楚再验证**。

### 5.2 Crimx/skills 的 "whats-missing"

[crimx/skills](https://github.com/crimx/skills) 是一个个人 Agent 技能集合，其中有一个叫 `whats-missing` 的技能，描述是：

> "Pressure-test an idea before implementation. Acts like a senior collaborator: it inspects the available context, exposes weak assumptions, focuses discussion on decisions that can materially change the outcome, and pushes back on risky or needlessly complicated directions."

这跟 Grill-me 的精神高度一致，但表达更温和——"资深同事" 而不是 "面试官"。它强调的关键词是 **"pushes back"**（主动反对）——这恰好是大多数 AI Agent 最不擅长的事。

### 5.3 为什么这么多人在做类似的事？

因为这是一个**结构性缺口**。当前的 AI Agent 生态有一个共同的缺陷：

| 传统 Agent 行为 | Grill-me 行为 |
|----------------|---------------|
| 收到指令 → 立即执行 | 收到指令 → 先拷问 |
| 假设用户知道自己在说什么 | 假设用户的需求有隐含层 |
| 以输出速度为荣 | 以澄清质量为荣 |
| 犯错后修补 | 犯错前预防 |

这不是技术能力问题——GPT-4/Claude 完全有能力问对问题。这是**行为设计**问题：Agent 的默认模式是"执行者"而不是"顾问"。

---

## 六、Grill-Me 的局限性：它不是银弹

写博客不吹捧，我得说说它不灵的地方。

### 6.1 过度拷问是反模式

不是每个任务都需要被"grill"。以下场景用 Grill-me 就是折磨：

- **简单 CRUD 操作**："加个用户注册接口"——问了 5 个问题，用户已经跑了
- **紧急 Hotfix**："生产环境挂了，快修"——这时候问"你的回滚策略是什么"就是在耍人
- **探索性实验**："帮我试一下这个 API 能不能用"——用户就是想快速试，不想做规划

Grill-me 的 0.3.0 版本意识到了这个问题，所以 `create-a-small-plan` 只需要 1-3 个问题。但更根本的解决方案是：**不是所有任务都应该进入 Grill-me 流程**。Agent 需要有能力判断"这个任务值得拷问吗？"

### 6.2 用户会疲劳

即使一次只问一个问题，问 10 个也很累。我估计大多数人在问到第 4-5 个问题时就会开始敷衍地选 "Auto-complete"。这等于把决策权让渡给了 AI——那为什么不直接让 AI 自己拍板呢？

这个矛盾目前还没有完美的解决方案。一个可能的方向是：**默认 Auto-complete，但把 Auto-complete 的选择透明化**——"我帮你选了 A，因为……如果你不同意请说"。

### 6.3 工具链成熟度

Optim-plans 还很年轻（484 stars，首次公开发布 3 周前）。它依赖 `.git/optim-plans/` 目录存储状态，依赖 `optim_plans.py` 脚本控制流程——这些都在早期阶段。而且它目前主要针对 Claude Code 和 Codex，其他 Agent 框架（Cursor、Copilot、通义灵码）的兼容程度未知。

### 6.4 中文用户的体验鸿沟

当前 Grill-me 生态完全是英文的。但中文开发者的需求模式跟英文开发者有本质不同：

- 中文开发者更倾向于"你说一个大概，AI 你补全细节"
- 中文语境下 "Other" 选项的使用率可能更低（更倾向模糊回答）
- 中国的代码审查文化强调"多看少说"，跟 Grill-me 的"多问多说"有张力

这不是说 Grill-me 不适用于中文环境，而是说**它需要本地化**——不仅仅是翻译，而是行为模式的调适。

---

## 七、我的思考：红海还是蓝海？

### 7.1 从 Agent 设计角度看

Grill-me 解决的是 AI Agent 领域最核心的矛盾之一：**能力 vs. 意图对齐**。

当前的 AI Agent 都在卷"能做多复杂的事"——自动写代码、自动部署、自动修 Bug。但真正卡脖子的不是能力，而是**对齐**：AI 做的东西跟用户想要的不一样。

Grill-me 把这个问题从"执行阶段"前移到了"规划阶段"。这是一种**错误预防**而不是**错误修复**的思路——在软件工程里，这被称为"左移"（Shift Left）。

### 7.2 从个人学习者角度看

作为个人开发者，Grill-me 给我的启发不是"我要装一个插件"，而是：**我可以用 Grill-me 的思维模式来提升我自己写代码前的思考质量**。

每次接到一个模糊需求时，试着问自己：

> "如果我是 Grill-me Agent，我会先问用户什么问题？"

这个自问自答的过程，本身就是最好的需求澄清训练。

### 7.3 值得关注的方向

基于目前的生态，我认为以下几个方向值得持续跟踪：

1. **Grill-me 的"克制版本"**——能否训练 Agent 自己判断"这个任务需要几个问题"，而不是固定套模板
2. **跨语言适配**——中文/日文等语境下的拷问模式会是什么样
3. **与企业开发流程的融合**——Grill-me 的 PLAN_v1.md 格式能否成为 Code Review 的输入
4. **与 Test-Driven Development 的结合**——"先拷问 → 再写测试 → 再实现"的三段式流程

---

## 八、实操建议：如果你想试

如果你也想在开发工作流中引入 Grill-me 的思路，不必等框架成熟。以下是几个渐进式方案：

### 方案 A：手动 Grill（零成本）

下次你用 AI 编程助手时，在它动手前，先主动问：

> "在开始之前，基于你的代码分析，你对我这个需求有什么疑问吗？请一次问一个。"

就这么一句话，AI 就会切换到"拷问模式"。

### 方案 B：安装 Optim-Plans

如果你是 Claude Code 或 Codex 用户：

```bash
# 添加到 Claude Code 技能路径
mkdir -p ~/.claude/skills
git clone https://github.com/Optim-Agent/optim-plans.git
cd optim-plans
cp -r skills ~/.claude/skills/
```

然后在需要时显式调用 `create-a-plan` 等技能。

### 方案 C：自建 Prompt

把 Grill-me 的核心流程写成你自己的系统提示词：

```
在执行任何任务前，按以下流程：
1. 先只读分析代码库
2. 逐条追问用户（一次一个问题）
3. 追问结束后写规划文档
4. 规划经审核后确认执行
5. 执行前最终确认
```

---

## 九、总结

Grill-me 不是一个工具，而是一种**态度**：在 AI Agent 的能力爆炸式增长的今天，最稀缺的不是执行速度，而是**理解意图的耐心**。

它提醒我们：一个真正靠谱的编程助手，不应该是那个最快写出代码的，而应该是那个最懂得**在写代码之前先问对问题**的。

> "The best code is the code you didn't have to write because you asked the right question first."

---

*参考链接：*
- [Optim-Agent/optim-plans](https://github.com/Optim-Agent/optim-plans) — 当前最成熟的 Grill-me 实现，484 stars
- [GitHub: grill-me topic](https://github.com/topics/grill-me) — 12 个使用 grill-me 标签的公开仓库
- [crimx/skills](https://github.com/crimx/skills) — 包含 whats-missing 等类 Grill-me 技能的个人集合
- [Hongdosan spec-driven-orchestra](https://github.com/hongdosan/hongdosan-spec-driven-orchestra) — 将 Grill-me 纳入 SDD 五音阶框架