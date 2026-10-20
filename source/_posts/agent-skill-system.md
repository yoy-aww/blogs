---
title: Skill 系统：把方法沉淀成 Agent 能加载的文件
date: 2026-10-19 16:00:00
type: tech
permalink: /2026/10/19/agent-skill-system/
tags:
  - Skill
  - Agent
  - 知识管理
  - Prompt-工程
description: Skill 是把"怎么做某类任务"的流程沉淀成可加载的文件单元——和工具/MCP 互补。讲清楚 Skill 的结构、加载机制、和程序性记忆的关系，以及和 MCP 的边界。
---

## 先说结论

Skill（技能）是把"怎么做某类任务"的**方法**沉淀成文件单元，让 Agent 按需加载。

和工具不一样：工具是"能力"（能搜索、能查数据库），Skill 是"方法"（做代码审查时，先跑 lint，再看 diff，再查安全模式）。一个 Agent 拿到 MCP 工具后还是不知道"这类任务的标准流程"，Skill 就是来回答这个问题的。

Skill 系统的核心是三个东西：

1. **文件结构**：每个 Skill 是一个目录，包含 SKILL.md（带 frontmatter 的元数据 + 正文）和可选的 references / templates / scripts
2. **加载机制**：Agent 启动时只加载所有 Skill 的元数据（description），触发条件匹配时再加载完整内容
3. **触发协议**：description 写得像路由条件，Agent 看到匹配就加载

这篇文章讲清楚 Skill 的结构、加载机制、和 MCP 的边界、和程序性记忆的关系。

## 为什么需要 Skill

LLM 有三个限制，Skill 是其中两个的直接对策：

### 限制 1：不知道团队的内部流程

LLM 训练数据里没有"我们团队代码审查的标准流程"。每次让它审代码，它给出一个"通用"的审查意见——可能是对的，但不一定是你们团队想要的。

**Skill 的解法**：把团队流程写成一个 Skill 文件，Agent 加载后再审，就知道该看哪些维度。

### 限制 2：上下文窗口有限，不能塞所有知识

如果把"代码审查流程"、"测试用例编写规范"、"部署 SOP"、"故障排查手册"……全塞进系统 Prompt，100K 上下文也撑不住。

**Skill 的解法**：Agent 启动时只加载所有 Skill 的元数据（描述行），几十 KB 搞定。真要做代码审查时，再加载代码审查 Skill 的完整内容——其他 Skill 不占上下文。

### 限制 3：知识更新成本高

LLM 的知识被冻结在训练截止日期。团队的流程变了、工具换了、API 升级了，LLM 都不知道。

**Skill 的解法**：Skill 是 Markdown 文件，人和 Agent 都能改。改了立刻生效，不用重训模型。

## Skill 的标准结构

一个 Skill 是一个目录：

```
skills/
└── code-review/
    ├── SKILL.md              # 主文件：元数据 + 步骤
    ├── references/
    │   └── security-checks.md  # 参考资料：安全检查清单
    ├── templates/
    │   └── review-comment.md   # 模板：审查评论模板
    └── scripts/
        └── lint.sh             # 脚本：一键 lint
```

### SKILL.md 的结构

```markdown
---
name: code-review
description: "代码审查的标准流程：先看 diff，再跑安全扫描，按维度给具体建议。"
version: 1.0.0
---

# 代码审查

## 触发条件
当用户要求 review PR、审代码、检查安全漏洞时使用。

## 步骤
1. 用 git diff 拿到改动
2. 用 grep 检查敏感信息（密钥、密码）
3. 用静态分析工具跑一遍
4. 按"安全 → 性能 → 风格"顺序检查
5. 给出具体文件位置和建议

## 参考资料
- 安全检查清单见 `references/security-checks.md`

## 模板
- 审查评论模板见 `templates/review-comment.md`
```

### frontmatter 的关键字段

| 字段 | 用途 | 示例 |
|---|---|---|
| `name` | Skill 的唯一标识 | `code-review` |
| `description` | **触发条件 + 一句话说明**，Agent 看这个决定要不要加载 | "代码审查的标准流程……" |
| `version` | 版本号，方便追踪变更 | `1.0.0` |

**description 是 Skill 的灵魂**：Agent 启动时只看到所有 Skill 的 description（一行一个），匹配上才加载完整内容。写得好 = Agent 选对 Skill，写得差 = Skill 白做。

## 加载机制：两阶段

### 阶段一：启动时加载元数据

Agent 启动时扫描所有 Skill 目录，读取每个 SKILL.md 的 frontmatter，组装成"可用技能列表"放进系统 Prompt：

```python
import yaml
from pathlib import Path

def load_skills_metadata(skills_dir):
    skills = []
    for skill_md in Path(skills_dir).glob("*/SKILL.md"):
        content = skill_md.read_text()
        # 解析 YAML frontmatter
        meta = yaml.safe_load(content.split("---")[1])
        skills.append({
            "name": meta["name"],
            "description": meta["description"],
            "path": skill_md.parent,
        })
    return skills

def build_system_prompt(skills):
    skill_lines = "\n".join([
        f"- {s['name']}: {s['description']}" for s in skills
    ])
    return f"""
你是一个 Agent。可用的技能：
{skill_lines}

当用户的问题匹配某个技能的触发条件时，调用 read_skill(name="<skill_name>") 加载完整内容。
"""
```

**这一步非常便宜**：几十到几百个 Skill 的元数据加起来也就几 KB，几乎不占上下文。

### 阶段二：触发时加载完整内容

Agent 看到用户问题匹配某个 Skill 的 description，调用 `read_skill` 工具加载完整 SKILL.md：

```python
def read_skill(name):
    skill_path = SKILLS_DIR / name / "SKILL.md"
    if not skill_path.exists():
        return f"Skill '{name}' 不存在"
    return skill_path.read_text()

# 这个工具暴露给 LLM 调用
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "read_skill",
            "description": "加载指定名称的 Skill 完整内容。当用户问题匹配某个 Skill 的触发条件时调用。",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Skill 名称"}
                },
                "required": ["name"]
            }
        }
    }
]
```

**完整加载的内容**：SKILL.md 正文 + 引用的 references / templates / scripts。Agent 拿到后按里面的步骤执行。

### 为什么分两阶段

不分阶段会怎样？把所有 Skill 内容塞进系统 Prompt：

- **上下文爆炸**：100 个 Skill，每个 5KB，就是 500KB——上下文撑不住
- **注意力稀释**：模型对 100 个 Skill 的注意力都分散了，反而答不准
- **更新困难**：每次改一个 Skill 都要重新生成 Prompt，影响所有请求

分阶段后：

- **启动便宜**：只加载元数据，几 KB 搞定
- **触发精准**：按需加载完整内容，只装真正相关的 Skill
- **更新灵活**：Skill 改了立刻生效，不用重启

## Skill 的描述怎么写

description 是 Agent 路由的依据。写好的 description 有几个特征：

### 1. 动词开头，说明做什么

```
✅ "代码审查的标准流程：先看 diff，再跑安全扫描……"
❌ "代码审查相关"
```

### 2. 包含触发关键词

```
✅ "当用户要求 review PR、审代码、检查安全漏洞时使用"
❌ "用于代码相关工作"
```

Agent 匹配 description 靠关键词。"review PR"、"审代码"、"安全漏洞"是用户可能说的词，写进去匹配率才高。

### 3. 一句话能说完

```
✅ "构建 BPMN 工作流项目：bpmn-js + Node + Flowable 的完整脚手架。"
❌ "这个 Skill 是用来帮你搭建 BPMN 项目的。BPMN 是……（300 字介绍）"
```

description 出现在系统 Prompt 里，每个 Skill 一行。冗长的 description 浪费上下文。

### 4. 区分场景

```
✅ "Use when ComposeView crashes in a Service-hosted overlay."（具体场景）
❌ "Android 布局相关"（太宽泛）
```

description 越具体，Agent 越容易匹配正确。一个 Skill 服务多个不相关场景是设计问题。

## 工程实践：一个完整的 Skill 示例

```
skills/
└── rag-evaluation/
    ├── SKILL.md
    ├── references/
    │   └── ragas-metrics.md
    └── scripts/
        └── run_eval.py
```

**SKILL.md**：

```markdown
---
name: rag-evaluation
description: "评估 RAG 系统质量：跑 faithfulness、answer relevance、context recall 三大指标，定位瓶颈环节。"
version: 1.0.0
---

# RAG 系统质量评估

## 触发条件
当用户问"RAG 效果怎么评估"、"检索质量怎么测"、"答案质量怎么打分"时使用。

## 步骤

1. **采样线上请求**：从生产 trace 里抽 100 条真实 query
2. **收集参考答案**：人工标注或拿历史好评回答作 ground truth
3. **跑三大指标**：
   - Faithfulness：回答是否忠于参考资料
   - Answer Relevance：回答是否针对问题
   - Context Recall：检索覆盖率
4. **定位瓶颈**：哪个指标低就看哪个环节
5. **生成报告**：模板见 `references/ragas-metrics.md`

## 工具
- 评估脚本：`scripts/run_eval.py`
- 指标定义：见 `references/ragas-metrics.md`

## 注意
- 采样量至少 100 条，少于此数字统计意义不大
- Faithfulness 用 LLM-as-judge 时，judge 模型要比被测模型强
```

**Agent 加载后的执行流**：

```
用户："我想知道 RAG 效果怎么测"
        ↓
Agent 看到 description 匹配 "怎么评估"
        ↓
Agent 调用 read_skill("rag-evaluation")
        ↓
完整 SKILL.md 加载到上下文
        ↓
Agent 按"步骤"逐条执行：
  1. 跑采样脚本（scripts/run_eval.py）
  2. 跑三个指标
  3. 用 references/ragas-metrics.md 里的定义解读结果
  4. 出报告
```

## Skill 和 MCP 的边界

这两个概念经常被搞混，因为它们都是"扩展 Agent 能力"。但层次完全不同：

| 维度 | MCP | Skill |
|---|---|---|
| 本质 | 协议（工具怎么暴露） | 知识单元（方法怎么沉淀） |
| 单位 | Server（进程） | 文件（Markdown 目录） |
| 提供什么 | **能力**：能调用某个函数/资源 | **方法**：知道某类任务怎么做 |
| 加载时机 | Agent 启动时连接 | 触发条件匹配时加载 |
| 谁维护 | 工具作者 | 团队/Agent 自己 |
| 类比 | USB-C 接口 | 操作手册 |

### 一个组合场景

你有一个代码审查 Agent：

- **MCP Server**：提供 `get_diff`、`run_lint`、`run_security_scan` 三个工具——Agent 有"能跑这些工具"的能力
- **Skill**：`code-review` Skill——告诉 Agent"做代码审查时，先 get_diff，再 run_lint，再 run_security_scan，按这个顺序看"

没有 MCP，Agent 没法调工具；没有 Skill，Agent 不知道该怎么组合调工具。两者缺一不可。

### 一个常见混淆

"我要不要在 Skill 里写工具的 JSON Schema？"——**不要**。Skill 是知识（怎么做），工具的 Schema 是工具接口（怎么用），应该放在 MCP Server 里。Skill 里只说"调 X 工具"，不重复定义 X 工具的接口。

## Skill 和程序性记忆的关系

回到记忆分层的视角：Skill 就是**程序性记忆**的工程实现。

记忆五层（工作 / 短期 / 长期 / 情景 / 程序性）中，程序性记忆装的是"怎么做某类任务的稳定流程"。Skill 把它文件化、可加载、可版本管理。

| 维度 | 程序性记忆（概念） | Skill（实现） |
|---|---|---|
| 生命周期 | 永久 | 永久 |
| 存储 | 文件 | 文件（Markdown 目录） |
| 召回 | 触发时加载 | 触发时加载 |
| 维护 | 人或 Agent | 人或 Agent |

也就是说，"程序性记忆"是一个抽象概念，"Skill"是它最常见的工程形态。其他形态还有：

- **Cursor Rules**：基于 `.cursorrules` 文件，更轻量
- **Claude Projects Knowledge**：项目级知识文件
- **Prompt Templates**：纯 Prompt 模板，没有触发机制

Skill 的优势是**结构清晰、可组合、可版本管理**——一个目录里既有元数据，又有正文，又能引用参考资料和脚本，是一个完整的"知识包"。

## Skill 系统的实际案例

### Hermes Agent

Hermes Agent 内置 Skill 系统，所有 Skill 在 `~/AppData/Local/hermes/skills/` 下：

```
skills/
├── hermes-agent/              # 配置 Hermes 本身
├── hermes-desktop-plugins/    # 写桌面插件
├── llm-finetuning/            # 微调 LLM
├── mlops/                     # MLOps 工具
│   ├── huggingface-hub/
│   └── inference/
├── creative/                  # 创意工具
│   ├── comfyui/
│   └── ascii-art/
└── ...（数十个 Skill，分类组织）
```

每个 Skill 都是 `name/SKILL.md` 的标准结构，按需加载。

### Claude Code

Claude Code 支持"项目级 Skill"，在 `.claude/skills/` 下放项目特定的 SKILL.md，Agent 启动时自动扫描。

### Cursor Rules

Cursor 用 `.cursorrules` 文件做轻量版 Skill——没有 frontmatter，整个文件就是 Prompt 的一部分，所有请求都注入。适合项目级、单一规则的场景。

## 工程实践要点

### 1. Skill 粒度要适中

一个 Skill 服务一个"任务类型"。不要一个 Skill 装所有事（变成大杂烩），也不要一个动作拆成多个 Skill（管理成本爆炸）。常见粒度：10-50 个 Skill 覆盖一个团队的常见任务。

### 2. Skill 不要互相依赖

一个 Skill 应该能独立工作。如果做代码审查必须先加载"Python 风格指南"，把后者直接写成前者的一部分，或合并成一个 Skill。Skill 间的依赖会让触发逻辑变复杂。

### 3. 大文件分出去

SKILL.md 不要超过 5-10KB。参考资料放 `references/`，模板放 `templates/`，脚本放 `scripts/`。SKILL.md 只装"步骤主线"和"引用"。

### 4. description 用关键词路由

Agent 匹配靠关键词。description 里要包含用户可能说的话——动词、名词、场景描述。

```
✅ "Use when <触发场景>. <一句说明>"
```

### 5. 版本管理

SKILL.md 的 frontmatter 加 `version` 字段，方便追踪变更。Skill 改了之后在 commit message 里标版本号。

### 6. 测试触发

写完 Skill 要测试触发——让 Agent 用几个相关 query 试试，看它能不能正确加载对应 Skill。description 写得太抽象 = 不触发，太具体 = 漏触发。

## 常见坑

**坑 1：把所有知识塞进系统 Prompt**

不分层 = 上下文爆炸 + 注意力稀释。能用 Skill 的别硬塞。

**坑 2：description 写得像广告**

"我们的 Code Review 神器，全面覆盖代码质量、安全、性能……"——Agent 看完不知道什么时候该用。description 是触发条件，不是营销文案。

**坑 3：Skill 内容太长不引用**

SKILL.md 写 50KB，全塞进上下文。大文件分出去到 `references/`，SKILL.md 只装主线。

**坑 4：忽略 Skill 的测试**

写完一个 Skill 就直接上线，没有验证过 Agent 能不能正确触发。description 写得太抽象 = 永不触发，写得太窄 = 漏触发。每次改 Skill 都跑几个 query 验证一下。

**坑 5：Skill 和工具混为一谈**

在 SKILL.md 里写工具的 JSON Schema——这是工具接口，应该放在 MCP Server 里。Skill 只说"调 X 工具"，不重复定义接口。

**坑 6：没有版本管理**

Skill 改了没记录，出问题不知道是哪个版本引入的。frontmatter 加 version 字段，commit 里标版本号。

## 一句话总结

Skill 是 Agent 的"程序性记忆"——把"怎么做某类任务"沉淀成可加载的 Markdown 文件。两阶段加载（启动时只读元数据，触发时加载完整内容）解决了"上下文有限 vs 知识无限"的根本矛盾。它和 MCP 互补：MCP 给 Agent "能调工具"的能力，Skill 告诉 Agent "怎么组合调工具"。一个是 USB-C 接口，一个是操作手册——两者一起才组成现代 Agent 的"能力 + 方法"双栈。把团队的隐性流程写成 Skill 文件，是新团队最容易落地的 Agent 工程实践。
