---
title: Agent 记忆分层：为什么不能把所有事塞进上下文窗口
date: 2026-10-19 13:00:00
type: tech
permalink: /2026/10/19/agent-memory-layers/
tags:
  - Agent
  - 记忆
  - 长上下文
  - 向量检索
categories:
  - 技术思考
description: 把 Agent 的记忆按生命周期分成五层——工作、短期、长期、情景、程序性——每一层都有独立的生命周期、存储介质和召回机制。"长期记忆 + RAG"本质就是同一个系统。
---

## 先说结论

Agent 的记忆不能一股脑塞进上下文窗口。原因很朴素：

1. **贵**。上下文里每多一个 token 都是钱
2. **慢**。Prefill 阶段是 O(n²) 的注意力计算
3. **稀释注意力**。塞太多，模型注意力被分散，反而答不准
4. **会过期**。把一年前和今天的内容一起塞，时间维度上毫无意义

工程上的正解是**记忆分层**：按生命周期和用途把记忆拆成几层，每层用不同的存储、不同的召回策略。这一篇把这五层拆开讲，并解释一个反直觉的事实——"长期记忆"和"RAG"在工程上是同一回事。

## Agent 的五个记忆层

```
┌────────────────────────────────────────────────────────────┐
│ 工作记忆 (Working Memory)          单次请求生命周期        │
│   ↓ 当前对话历史、当前任务状态、中间推理                   │
├────────────────────────────────────────────────────────────┤
│ 短期记忆 (Short-term Memory)       会话生命周期            │
│   ↓ 本次会话的偏好、中间结论、临时任务                      │
├────────────────────────────────────────────────────────────┤
│ 长期记忆 (Long-term Memory)         跨会话，永久           │
│   ↓ 用户画像、稳定偏好、知识库                              │
├────────────────────────────────────────────────────────────┤
│ 情景记忆 (Episodic Memory)          按事件存储             │
│   ↓ 过去某个任务的完整轨迹、对话片段                        │
├────────────────────────────────────────────────────────────┤
│ 程序性记忆 (Procedural Memory)      长期沉淀的流程         │
│   ↓ 怎么做某类任务的步骤、技能、模板                        │
└────────────────────────────────────────────────────────────┘
```

这五层不是理论分类学，每一层都有明确的工程实现。

## 工作记忆：上下文窗口

工作记忆就是 LLM 的上下文窗口，生命周期 = 单次请求。

**内容**：

- 系统 Prompt
- 当前对话历史（最近 N 轮）
- 工具调用记录和结果
- 中间推理过程

**特点**：

- 容量有限（即便 1M token 的模型，实际有效窗口也小得多）
- 直接决定这次回答的质量
- 用完即弃（除非显式保存到短期/长期记忆）

**工程上的关键决策**：怎么决定"哪些历史要保留"。

```python
def get_messages(history, max_tokens=8000):
    # 简单策略：保留最近 N 轮
    if count_tokens(history) <= max_tokens:
        return history
    
    # 进阶策略 1：按 token 截断
    msgs = []
    for msg in reversed(history):
        if count_tokens(msgs + [msg]) > max_tokens:
            break
        msgs.append(msg)
    return list(reversed(msgs))
    
    # 进阶策略 2：摘要压缩
    # 用便宜的小模型把老对话摘要成一段，保留关键信息
    
    # 进阶策略 3：基于重要性打分
    # 让另一个 LLM 给每条消息打"重要性分"，保留高分的
```

**工作记忆的关键问题是"遗忘"**：上下文满了怎么办？硬截断会丢关键信息，全保留又撑爆窗口。常见方案是"近期原样 + 远期摘要"——最近的对话保留原文，更早的对话用 LLM 摘要成一段塞回。

## 短期记忆：会话级缓存

短期记忆的生命周期 = 一次会话（几分钟到几小时）。

**存储**：Redis、内存字典、Session 对象。

**内容**：

- 用户本次会话的偏好（"我刚才说想看 TypeScript 的写法"）
- 中间任务的当前状态（"刚才在修第 3 个 bug"）
- 本次会话的临时变量

```python
from redis import Redis
import json

redis = Redis()

def get_session_memory(session_id):
    raw = redis.get(f"session:{session_id}")
    return json.loads(raw) if raw else {}

def save_session_memory(session_id, memory):
    redis.setex(f"session:{session_id}", 3600, json.dumps(memory))  # 1 小时过期

# 用法
def agent_step(session_id, user_input):
    memory = get_session_memory(session_id)
    # 把短期记忆注入 Prompt
    prompt = f"会话上下文：{json.dumps(memory)}\n\n用户：{user_input}"
    response = llm(prompt)
    
    # 更新短期记忆
    memory["last_query"] = user_input
    memory["last_response"] = response
    save_session_memory(session_id, memory)
    return response
```

**短期记忆和工作记忆的区别**：工作记忆在上下文窗口里，LLM 每轮都能看到；短期记忆在 Redis 里，需要主动查询并注入 Prompt。短期记忆比工作记忆更便宜（Redis 比上下文便宜几个数量级），但要主动召回。

**短期记忆的典型用途**：

- 多轮对话中保持任务连贯
- 记住用户中途表达的偏好（"我比较喜欢用 Tailwind"）
- 暂存中间状态（比如正在进行的购物流程）

## 长期记忆：跨会话的用户画像

长期记忆的生命周期 = 跨会话，永久。

**存储**：向量库（pgvector、Milvus、Chroma）+ 元数据 DB。

**内容**：

- 用户画像（职业、兴趣、偏好）
- 历史决策记录
- 知识库（公司文档、产品手册）
- 与用户相关的任何"长期有效"的事实

```python
# 长期记忆通常就是一个 RAG 系统
from openai import OpenAI
import pgvector  # 假设用 pgvector

llm = OpenAI()

def save_long_term_memory(user_id, content, embedding):
    # 存到向量库
    db.execute(
        "INSERT INTO memories (user_id, content, embedding) VALUES (?, ?, ?)",
        (user_id, content, embedding)
    )

def retrieve_long_term_memory(user_id, query, k=5):
    q_embedding = llm.embeddings.create(model="text-embedding-3-small", input=query).data[0].embedding
    rows = db.execute(
        "SELECT content, embedding <=> ? AS dist FROM memories "
        "WHERE user_id = ? ORDER BY dist LIMIT ?",
        (q_embedding, user_id, k)
    ).fetchall()
    return [r["content"] for r in rows]

# Agent 每次开始新会话前，召回相关的长期记忆
def new_session(user_id, first_message):
    relevant_memories = retrieve_long_term_memory(user_id, first_message, k=5)
    memory_context = "\n".join(relevant_memories)
    return [
        {"role": "system", "content": f"关于用户的已知信息：\n{memory_context}"},
        {"role": "user", "content": first_message}
    ]
```

**关键洞察**：长期记忆 = 向量检索 = RAG。把"长期记忆"想成"以用户为中心的 RAG 系统"，工程上完全用 RAG 那套工具实现。

**长期记忆的写入策略**：

```python
# 什么内容值得写入长期记忆？
def should_save_to_long_term(content):
    # 1. 用户明确表达的偏好
    if "我比较喜欢" in content or "我习惯" in content:
        return True
    # 2. 涉及具体事实（名字、地点、公司）
    if has_entities(content):
        return True
    # 3. 用户的纠正（"不对，应该是 X"）
    if "不对" in content or "应该是" in content:
        return True
    return False
```

不是所有对话都值得进长期记忆。过滤不好，长期记忆会变成一个无意义的杂烩，召回时全是噪声。

**长期记忆的删除**：用户应该能删自己的记忆。GDPR 等合规要求也强制这一点。设计时要考虑"删除/导出"能力。

## 情景记忆：按事件存储的任务轨迹

情景记忆（Episodic Memory）存的是"过去某个事件的完整轨迹"。

**典型内容**：

- 过去完成过的任务（"上周帮用户排查了 X 问题"）
- 当时的对话片段
- 当时的工具调用记录

**存储**：向量库 + 结构化 DB（事件 ID、时间戳、参与工具等元数据）。

**为什么需要单独一层**：工作记忆用完即弃，短期记忆会话结束就清，但"过去某个任务的完整轨迹"对后续任务很有参考价值——尤其是相似任务的复用。

```python
# 一个事件存储
def save_episode(event_id, user_id, trajectory):
    """trajectory 是当时完整的 messages 数组"""
    embedding = llm.embeddings.create(
        model="text-embedding-3-small",
        input=trajectory_summary(trajectory)  # 对完整轨迹做摘要再嵌入
    ).data[0].embedding
    
    db.execute(
        "INSERT INTO episodes (id, user_id, summary_embedding, trajectory, ts) "
        "VALUES (?, ?, ?, ?, ?)",
        (event_id, user_id, embedding, json.dumps(trajectory), now())
    )

# 召回类似事件
def find_similar_episodes(query, k=3):
    q_emb = embed(query)
    return db.execute(
        "SELECT trajectory FROM episodes "
        "ORDER BY summary_embedding <=> ? LIMIT ?",
        (q_emb, k)
    ).fetchall()
```

**典型用途**：

- 类似任务的轨迹复用（"上次用户问类似问题，我是这样回答的"）
- 错误模式识别（"上次这么调用工具，结果是 X，这次要不要换种方式"）
- 用户行为习惯分析

**情景记忆是 RAG 在 Agent 场景的特化**——检索的不是文档片段，是过去的事件轨迹。

## 程序性记忆：技能与流程

程序性记忆（Procedural Memory）是 Agent 的"怎么做某类任务"的沉淀。

**形式**：通常是 Markdown 文件（SKILL.md），带触发条件和步骤说明。

**典型内容**：

```markdown
---
name: code-review
description: "做代码审查的标准流程"
---

## 触发条件
当用户要求 review PR、审代码、检查安全漏洞时使用。

## 步骤
1. 用 git diff 拿到改动
2. 用 grep 检查敏感信息（密钥、密码）
3. 用静态分析工具跑一遍
4. 按"安全 → 性能 → 风格"顺序检查
5. 给出具体文件位置和建议
```

**特点**：

- **不是检索出来的，是加载进来的**。Agent 启动时把所有可用 Skill 的"摘要"（frontmatter 的 description）放进系统 Prompt，等触发时按需加载完整内容
- 由 Agent 或人维护，是 Agent 的"技能库"
- 比情景记忆更稳定——不依赖具体事件，是抽象出来的"方法"

```python
# Agent 启动时加载可用技能的元数据
def load_skills_metadata(skills_dir):
    skills = []
    for skill_file in glob(f"{skills_dir}/*/SKILL.md"):
        meta = parse_frontmatter(skill_file)
        skills.append({
            "name": meta["name"],
            "description": meta["description"],
            "path": skill_file,
        })
    return skills

# 系统 Prompt 里只放元数据
def build_system_prompt(skills):
    skill_list = "\n".join([f"- {s['name']}: {s['description']}" for s in skills])
    return f"""
你是一个 Agent。可用的技能：
{skill_list}

当用户的问题匹配某个技能的触发条件时，调用 read_skill(name) 加载完整内容。
"""
```

**程序性记忆和工作记忆的关系**：工作记忆装"当前任务在做什么"，程序性记忆装"这类任务通常怎么做"。两者互补。

**Skill 系统的实际例子**：Hermes Agent、Claude Code、Cursor 的 Rules 都是程序性记忆的工程实现。它们的共同点是：用文件而非数据库存储，因为人类要能读、能改、能 review。

## 五层的对比与工程权衡

| 层级 | 生命周期 | 存储介质 | 召回方式 | 容量 |
|---|---|---|---|---|
| 工作记忆 | 单次请求 | 上下文窗口 | 每轮自动加载 | 受模型限制 |
| 短期记忆 | 单次会话 | Redis | 主动查询注入 | GB 级 |
| 长期记忆 | 永久 | 向量库 | 语义检索（RAG） | TB 级 |
| 情景记忆 | 永久 | 向量库 + DB | 语义检索 + 时间过滤 | TB 级 |
| 程序性记忆 | 永久 | 文件 (Markdown) | 元数据扫描 + 触发加载 | 数十 MB |

**关键洞察**：

1. **生命周期决定存储介质**。短时用内存/Redis，长时用向量库，方法论用文件
2. **召回方式决定可用性**。不主动召回的记忆等于不存在
3. **不是所有层都要建**。简单 Agent 只需要工作记忆 + 程序性记忆；复杂 Agent 才需要长期 + 情景记忆

## 常见坑

**坑 1：把所有东西塞进工作记忆**

100K 上下文塞 50 轮历史 + 用户画像 + 知识库摘要，模型注意力稀释严重，反而答不准。该分层的别硬塞。

**坑 2：长期记忆写入策略太宽松**

每轮对话都往长期记忆写一条，三个月后向量库塞满了用户的闲聊。要过滤：什么值得写、什么不值得写。

**坑 3：情景记忆的轨迹太长**

一个事件几十轮对话，整条塞进向量库再检索，召回时上下文直接爆掉。轨迹要先做摘要再嵌入，原文另存引用，召回时按需展开。

**坑 4：忽视删除和导出**

长期记忆存了用户隐私，没提供删除接口，GDPR 直接炸。设计阶段就要考虑"删一个用户的记忆"、"导出某用户的记忆"两个操作。

**坑 5：程序性记忆和工作记忆混淆**

把工作记忆里的临时偏好写到 SKILL 文件里——下次再加载时这个偏好已经过期。SKILL 应该装"稳定的方法"，不装"用户偏好"。

**坑 6：召回不主动**

建了长期记忆库，但 Agent 不会主动去查——等于没建。Agent 的主循环里要显式调用"召回相关记忆"这一步，而不是期望模型自己会去查。

## 一句话总结

Agent 记忆分层的本质是"按生命周期把信息分桶，每桶用对的工具"。工作记忆装当前任务，短期记忆装会话上下文，长期记忆装用户画像和知识库（本质就是 RAG），情景记忆装任务轨迹，程序性记忆装技能流程。五层各司其职，召回策略各有不同。最反直觉的一点：**长期记忆就是 RAG**——别把"长期记忆"当成新东西发明，它就是知识库的另一种叫法。
