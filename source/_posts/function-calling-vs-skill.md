---
title: Function Calling 和 Skill 是什么关系
date: 2026-10-23 15:00:00
type: tech
permalink: /2026/10/23/function-calling-vs-skill/
tags:
  - Function-Calling
  - Skill
  - Agent
  - Tool-Use
description: Function Calling 是 LLM 原生调工具的协议（模型层），Skill 是开发者封装的任务方法论（应用层）。一个是"手"，一个是"剧本"，是封装与被封装的关系。
---

## 先说结论

很多人把 Function Calling 和 Skill 当成同一种东西，其实不是。**它们在不同层。**

一句话：

- **Function Calling 是"手"** —— LLM 调工具的原生协议，模型层
- **Skill 是"剧本"** —— 开发者封装的任务方法论，应用层

Function Calling 决定"用什么工具"，Skill 决定"做什么事、按什么顺序、注意什么"。两者是**封装与被封装**的关系：Skill 靠 Function Calling 去调用具体的工具，但 Skill 本身不是 Function Calling。

上一篇 [Skill 系统](/2026/10/19/agent-skill-system/) 讲的是"剧本怎么写"。这篇讲"剧本里的动作，最终是怎么通过 Function Calling 真正落地的"。

## Function Calling 是什么

LLM 本身只会生成文本。Function Calling（也叫 tool use）是模型厂商在训练时加的一层能力：当模型判断"我需要做点什么"时，它不直接输出自然语言，而是输出一个**结构化的 JSON 调用**：

```json
{
  "type": "function",
  "function": {
    "name": "terminal",
    "arguments": "{\"command\": \"python extract.py --input-dir ...\"}"
  }
}
```

然后**运行时**（Hermes、LangChain、LangGraph 等）拦截这个 JSON，真正去执行 `terminal`，把执行结果喂回模型。模型观察结果，再决定下一步。

关键点：**Function Calling 是 LLM 的原生能力，是模型层的协议。** 你写提示词写不出它，它是在模型训练里"长"出来的。它定义了"工具长什么样"（JSON schema）和"模型怎么发起调用"。

## Skill 是什么

Skill 是**你写的"任务方法论"**。它是一份 Markdown 文件（SKILL.md），包含三样东西：

1. **触发条件**（frontmatter 里的 `description`）：什么时候该用这个 skill
2. **流程步骤**（正文）：先做 A、再做 B、注意 C
3. **可执行代码**（`scripts/`）：真正干活的脚本

注意：Skill **不是** Function Calling，它是**提示词 + 脚本包**。它直接注入 LLM 的上下文（作为一段被读到的文字），不经过 Function Calling 的 JSON 协议。

## 两者的关系（关键一张图）

以一个真实任务为例：我说"处理 Downloads 里的招聘 PDF，提取数据入库"。

```
┌─────────────────────────────────────────┐
│  用户："处理招聘 PDF 入库"               │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Agent（LLM）读到 Skill 的指令          │
│  （这段是提示词，注入上下文，           │
│    不经过 Function Calling）            │
└──────────────────┬──────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │  Function Calling     │
        │  模型输出 JSON：      │
        │  {name:"terminal",   │
        │   args:{command:...}} │
        └──────────┬───────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  运行时执行 terminal 工具               │
│  → python extract.py ...              │
│  → 返回 stdout                        │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  LLM 观察结果，可能再发一次调用        │
└─────────────────────────────────────────┘
```

**Skill 是"大脑里的剧本"，Function Calling 是"手伸出去按按钮"。**

这个例子里，我给自己写的一个 skill `recruitment-pdf-extract` 就有三份东西：

- `SKILL.md` 正文（"先建表、再逐个提取、按 phone 去重"）→ **提示词层**，注入 LLM
- `SKILL.md` 里的"用 `terminal` 跑 `scripts/extract.py`"这句 → 触发一次 **Function Calling**
- `scripts/extract.py` → **真正被 terminal 执行的代码**

三层各司其职，缺一层都不成立。

## 精确对应表

在 LangChain / LangGraph 生态里，这两个概念的分界更清晰：

| 概念 | LangChain 对应物 | Hermes 对应物 |
|---|---|---|
| **Tool**（原子能力） | `@tool` 装饰器 | `terminal`、`read_file`、`web_search` |
| **Function Calling** | 模型调用 tool 的机制（JSON schema） | LLM 输出 `terminal(command="...")` |
| **Skill**（方法论） | 无直接对应物，通常拆成 `prompt + tool + 流程` | SKILL.md（描述 + 步骤 + 脚本） |
| **Agent** | `StateGraph`，把 tools 编排成图 | 整个对话进程 |

LangChain 里没有一个叫 "skill" 的一等公民。所以很多团队自己用 `SKILL.md` 或 `AGENTS.md` 承载"方法论"这一层——这正是 Hermes 的做法。**Function Calling 是所有框架都有的底层协议；Skill 是应用层的选择。**

## 为什么容易混淆

因为 **Skill 的执行依赖 Function Calling，但 Skill 本身不是 Function Calling。**

拆开看一条 Skill 的正文：

```
## How to Run
用 terminal 工具跑 scripts/extract.py
```

- 这一句**告诉 LLM 要做什么**（提示词，直接进上下文，不走 JSON 协议）
- LLM 据此**发起一次 Function Calling**（输出 `{name:"terminal", ...}`）
- 运行时**执行 `terminal`**，跑 `scripts/extract.py`

所以可以这么总结：

> **Skill = 提示词（让 LLM 知道做什么）+ 工具调用（让 LLM 知道用哪只手）+ 脚本（让工具真正干活）**

Function Calling 只是 Skill 里"用哪只手"那一环。你写 SKILL.md 的 `scripts/extract.py`，这段代码是被 `terminal` 这个 function call 执行的；你写 SKILL.md 的正文（"先建表，再逐条入库，注意 phone 去重"），这段是提示词，直接注入 LLM 上下文，**不经过 Function Calling**。

## 一张总表把层次理清楚

| 维度 | Function Calling | Skill |
|---|---|---|
| 层级 | 模型层（LLM 原生能力） | 应用层（开发者封装） |
| 本质 | 模型输出结构化 JSON | 一份 Markdown 文件（提示词 + 脚本） |
| 谁定义 | LLM 厂商在模型里训练出来的 | 开发者写的提示词 + 脚本 |
| 决定什么 | 用什么工具 | 做什么事、按什么顺序、注意什么 |
| 是否进上下文 | 是（作为调用指令） | 是（作为被读到的剧本） |
| 类比 | 手 | 剧本 |
| 和 ReAct 的关系 | ReAct 循环里"Act"那一步 | ReAct 循环里"Reason 依据"的一部分 |

## 面试可以直接用的一句话

> "Function Calling 是 LLM 调工具的原生协议（JSON schema），是 agent 的**手**。Skill 是开发者封装的**任务方法论**（提示词 + 可执行脚本 + 流程约束），它通过 Function Calling 去调用具体的 tools。Skill 是应用层，Function Calling 是模型层，两者是**封装与被封装**的关系——Skill 里的脚本靠 Function Calling 落地，但 Skill 本身（那段提示词）不走 Function Calling 协议。"

再往外扩一层：Function Calling 解决"模型怎么伸手"，ReAct 解决"模型怎么思考—行动—观察循环"，Skill 解决"这类任务的标准打法"，DAG / LangGraph 解决"多个任务怎么按依赖编排"。从下往上是**模型协议 → 运行范式 → 方法论 → 编排**四层，Function Calling 是最底的那层地基。
