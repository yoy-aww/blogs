---
title: RAG 不是检索加生成，是一套完整的知识接入流水线
date: 2026-10-19 09:00:00
type: tech
permalink: /2026/10/19/rag-knowledge-pipeline/
tags:
  - RAG
  - LLM
  - 知识管理
  - Agent
categories:
  - 技术思考
description: 把 RAG 拆成六个环节看：为什么要做、切块怎么切、向量怎么算、检索怎么排、Prompt 怎么拼，以及它和 Agent 的边界在哪里。
---

## 先说结论

RAG 经常被简化成"检索 + 生成"两字，但在工程上它是一套完整流水线：文档接入 → 切块 → 嵌入 → 索引 → 检索 → 重排 → Prompt 拼接 → 生成。任何一个环节偷懒，最后生成出来的答案就是错的——只是"错"的方式可能很隐蔽，看起来像模型没读懂，实际上是上游检索根本没把对的文档拉回来。

这篇文章把这条流水线按环节拆开看，重点讲每个环节的选择空间和常见坑。

## 为什么需要 RAG

大语言模型有三个天生限制：

**一是训练截止时间**。模型知识冻结在某一天，今天的新闻它不知道。

**二是上下文窗口有限**。即便有 100 万 token 上下文，也不可能把所有公司文档都塞进去。

**三是幻觉**。当模型不知道时，它倾向于编造一个看起来合理的答案，而不是说"我不知道"。

RAG 的思路很直接：在生成之前，先把外部知识检索出来，塞进 Prompt 的上下文里。这样模型的回答就有了根据，并且可以标注来源。

```
用户问题 → 检索相关文档 → 拼进 Prompt → LLM 基于上下文生成回答
```

听起来简单，但工程上的坑全在这条流水线的每个环节。

## 完整流水线

```
[文档源]  →  [解析]  →  [切块 Chunking]  →  [嵌入 Embedding]  →  [向量库]
                                                                 ↓
                                              [LLM 生成]  ←  [Prompt 拼接]  ←  [检索]  ←  [重排]  ←  [用户查询]
```

预处理阶段一次性建好索引，查询阶段每次请求走一遍。

## 切块：最被低估的环节

切块决定了下游所有事。切得太大，检索命中不精准；切得太小，上下文断裂。

```python
from langchain_text_splitters import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,        # 每块 500 字符（中文）
    chunk_overlap=50,      # 块间重叠 50 字符，避免边界信息丢失
    separators=["\n\n", "\n", "。", "；", "，", " ", ""],
)

chunks = splitter.split_documents(documents)
```

**几个经验值**：

- 中文文档：chunk_size 500–1000，overlap 50–100
- 英文文档：chunk_size 200–500 tokens，overlap 20–50
- 代码：按函数/类切，不要按字符切

**一个反直觉的事实**：很多 RAG 系统效果差，根因不是检索算法不好，是切块切坏了。比如把一份合同的"标的金额条款"切成了两个块，第一块讲金额，第二块讲期限，模型检索到第二块就完全无法回答金额问题。

**切块策略要跟着内容走**：

- 普通文档 → 按字符/段落递归切
- Markdown → 按标题层级切（一篇文档拆成多个章节）
- 代码 → 按 AST 切（函数、类、模块）
- 表格 → 保留结构（CSV/JSON），不要拍平成文本
- PDF 扫描版 → 先 OCR，再按版面切（避免把标题切到正文中间）

## 嵌入：把文本变成向量

嵌入（Embedding）是把一段文本映射到一个高维向量空间。语义相近的文本，向量距离也近。

```python
from openai import OpenAI

client = OpenAI(base_url="https://api.openai.com/v1", api_key="sk-...")

def embed(texts):
    resp = client.embeddings.create(
        model="text-embedding-3-small",
        input=texts,
    )
    return [d.embedding for d in resp.data]
```

**主流嵌入模型对比**：

| 模型 | 维度 | 上下文 | 特点 |
|---|---|---|---|
| text-embedding-3-small | 1536 | 8K | 性价比好，默认选择 |
| text-embedding-3-large | 3072 | 8K | 精度更高，贵 10 倍 |
| bge-m3 (BAAI) | 1024 | 8K | 多语言，开源可本地部署 |
| jina-embeddings-v2-base | 768 | 8K | 开源，中英双语友好 |
| nomic-embed-text | 768 | 8K | 开源，速度快 |

**怎么选**：

- 纯中文小项目：bge-m3 / bge-large-zh，本地跑，免费
- 中英混合，预算充足：text-embedding-3-large
- 多语言大规模：bge-m3 或 jina v2
- 极端成本敏感：本地跑 sentence-transformers

**一个重要原则**：索引和查询必须用**同一个嵌入模型**。换模型 = 整个索引作废，所有向量重新算一遍。

## 检索：从向量库拿结果

把嵌入向量存进向量库，查询时按相似度取 Top-K。

**主流向量库**：

| 类型 | 代表 | 适合 |
|---|---|---|
| 进程内 | FAISS, Annoy, hnswlib | 单机、原型、小规模（百万级） |
| 专用向量库 | Milvus, Qdrant, Weaviate, Chroma | 生产、需要元数据过滤 |
| 搜索引擎扩展 | Elasticsearch dense_vector, OpenSearch | 已经有 ES 的团队 |
| 关系数据库扩展 | pgvector, SQLite vec | 数据已经在 PG/SQLite 里 |

**一个简单的 FAISS 检索**：

```python
import numpy as np
import faiss

index = faiss.IndexFlatIP(768)  # 内积，归一化向量等价于余弦相似度
vectors = np.array(embed(chunks)).astype("float32")
vectors = faiss.normalize_L2(vectors)
index.add(vectors)

def retrieve(query, k=5):
    qv = np.array([embed([query])[0]]).astype("float32")
    faiss.normalize_L2(qv)
    scores, indices = index.search(qv, k)
    return [(chunks[i], s) for i, s in zip(indices[0], scores[0])]
```

**Top-K 怎么选**：K 太小可能漏召回，K 太大会引入噪声。常见 K=3~10。一个经验是 K=5 配 Reranker 用 1 个，比 K=10 不 rerank 效果好。

## 重排：把"还行"变成"真的对"

向量检索的第一阶段是个**近似最近邻**搜索，速度快但不准。重排（Reranker）用更强的模型对候选做精细打分。

```python
# 用 cross-encoder 做重排（bge-reranker-v2-m3 为例）
from sentence_transformers import CrossEncoder

reranker = CrossEncoder("BAAI/bge-reranker-v2-m3")

def rerank(query, candidates, top_n=3):
    pairs = [(query, doc.text) for doc in candidates]
    scores = reranker.predict(pairs)
    return sorted(zip(candidates, scores), key=lambda x: -x[1])[:top_n]
```

**重排模型对比**：

| 模型 | 速度 | 精度 | 部署 |
|---|---|---|---|
| bge-reranker-v2-m3 | 中 | 高 | 本地 GPU |
| cohere-rerank | 快 | 高 | API |
| bge-reranker-base | 慢 | 中 | 本地 GPU |

**为什么重排值得做**：向量检索召回 50 个候选，重排后取 Top 3，效果通常远好于直接取 Top 3。代价是延迟增加（reranker 要跑 cross-encoder，比双塔模型慢 10 倍左右）。

**取舍**：在线场景对延迟敏感，rerank 可以省；离线批处理或长文档问答，rerank 必做。

## Prompt 拼接：把检索结果塞回去

```python
def build_prompt(query, contexts, max_tokens=3000):
    context_text = "\n\n---\n\n".join(
        f"[来源: {i+1}] {doc.text}" for i, doc in enumerate(contexts)
    )
    # 简单截断，避免超过上下文窗口
    if len(context_text) > max_tokens * 2:
        context_text = context_text[:max_tokens * 2] + "\n\n[上下文已截断]"
    
    return f"""你是一个基于参考资料回答问题的助手。

参考资料：
{context_text}

用户问题：{query}

要求：
1. 只基于参考资料回答，参考资料里没有的内容明确说"无法从参考资料回答"
2. 引用具体段落时标注来源编号
3. 不要编造答案
"""
```

**几个 Prompt 工程要点**：

- **明确告诉模型"不知道就说不知道"**，这是抑制幻觉的关键
- **保留来源编号**，方便用户验证
- **超长上下文要截断**，并且告知模型"已截断"，避免模型基于不完整信息硬答
- **参考资料放前面，用户问题放后面**，多数模型对 Prompt 末尾的信息更敏感

## 生成：让 LLM 回答

```python
from openai import OpenAI

def generate(prompt, model="gpt-4o-mini"):
    resp = OpenAI().chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,  # 低温度，减少幻觉
    )
    return resp.choices[0].message.content
```

**温度参数**：RAG 场景一般用低温度（0–0.3），让模型忠实于参考资料。高温度适合创意写作，但不适合事实问答。

## 三种 RAG 架构演进

```
Naive RAG：         [文档] → [检索] → [LLM]           （简单，问题多）
Advanced RAG：      [文档] → [切块优化] → [检索优化] → [重排] → [LLM]
Modular RAG：       Agent 编排多个 RAG 模块，自主决定怎么检索、检索什么
```

**Naive RAG** 是最基础的"切块 + 嵌入 + 检索 + 拼 Prompt"。大多数原型停在这一层，问题也很多：检索不准、Prompt 太长稀释注意力、无法处理多跳问题。

**Advanced RAG** 在 Naive 基础上加了几个关键优化：Query 改写（把用户问题改写成更适合检索的形式）、HyDE（让 LLM 先生成一个假答案再拿它检索）、Hybrid Search（混合检索）、Reranking。这一层是生产环境的主流。

**Modular RAG** 把检索本身也变成 Agent 可调用的工具。Agent 自己决定：要不要检索？检索哪个库？查询词改不改？要不要追问用户？这是和 Agent 架构融合的方向。

## RAG 的常见坑

**坑 1：切块切坏了**

合同被切成"金额条款"和"期限条款"两块，用户问金额，检索到的是期限块，模型基于错误上下文作答。切块策略要跟着文档类型走，不能一刀切。

**坑 2：检索不到相关文档**

向量检索对精确关键词（型号、错误码、人名）召回差。这时需要混合检索（向量 + BM25），下一篇博客会单独讲。

**坑 3：上下文塞太多稀释注意力**

100K 上下文塞 100 个 chunk，模型注意力被分散，反而答不准。K 不要贪大，配 Reranker 比堆 K 好。

**坑 4：Prompt 没告诉模型"不知道就说不知道"**

模型看到参考资料里有部分内容，会基于这部分内容硬答剩下的部分，导致幻觉。Prompt 必须明确"参考资料没有的内容直接说不知道"。

**坑 5：嵌入模型换了但索引没重建**

换嵌入模型 = 向量空间换坐标系，旧向量在新坐标系里毫无意义。索引必须用同一个嵌入模型重新构建。

**坑 6：忽略引用**

模型基于参考资料回答，但用户看不到引用。一旦答错用户无法验证。生产级 RAG 必须标注来源，让用户能跳转原文。

## RAG 和 Tool Calling 的关系

Tool Calling 是 Agent 的核心机制——让 LLM 决定调用哪个工具、传什么参数。RAG 可以看作是 Tool Calling 的一个特例：把"检索"也作为一个工具暴露给 Agent。

```
[固定 RAG]   每次请求都检索 → Prompt → 生成
[Agent RAG]  Agent 决定要不要检索、检索什么、要不要追问用户
```

固定 RAG 简单可靠，适合"问题明确、文档源固定"的场景。Agent RAG 灵活强大，适合复杂场景。下一篇博客讲 Tool Calling，会展开讲这一点。

## 一句话总结

RAG 的本质不是"检索 + 生成"两个动词，而是把外部知识安全、可靠、可追溯地接入 LLM 的一整套流水线。流水线里每个环节都直接影响最终答案的质量，每个环节都有自己的工程权衡。把 RAG 想成"知识接入系统"而不是"两行代码的链路"，工程上才会少踩很多坑。
