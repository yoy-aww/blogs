---
title: 混合检索：向量 + BM25 + RRF 的工程实战
date: 2026-10-19 11:00:00
type: tech
permalink: /2026/10/19/hybrid-retrieval-vector-bm25-rrf/
tags:
  - 混合检索
  - BM25
  - 向量检索
  - RRF
  - Elasticsearch
categories:
  - 技术思考
description: 纯向量检索召回不准，纯 BM25 又不通语义。把两种检索各跑一遍，用 RRF 融合排名，效果比单独任何一种都强——这是 2024 年后的 RAG 共识。
---

## 先说结论

RAG 的检索环节，"用向量检索就够"这个想法已经被打脸很多次了。向量检索擅长语义相似，但碰上"报错码 E0203"、"产品型号 XJ-2024"、"作者张三"这种精确关键词查询，召回率断崖式下跌。反过来，BM25 擅长关键词精确匹配，但"怎么解决性能问题"和"性能优化技巧"这种语义同义表达，BM25 抓不到。

**两条腿走路才是正解**：向量检索拿语义相近的结果，BM25 拿关键词命中的结果，最后用 RRF（Reciprocal Rank Fusion）把两份排名融合成一份。这不是理论最优解，是 2024 年后被无数生产系统验证过的工程共识。

这篇文章讲清楚三种检索的分工、RRF 的算法细节、完整实现，以及工程实践。

## 三种检索的能力对比

| 维度 | 向量检索 | BM25 | 混合 |
|---|---|---|---|
| 原理 | Embedding + 余弦相似度 | 词频 + 逆文档频率 | 两者并行 + RRF 融合 |
| 擅长 | 语义相似（"bug 怎么修" ≈ "debug 技巧"） | 精确关键词（型号、错误码、人名） | 两者兼顾 |
| 短词查询 | 差 | 好 | 好 |
| 同义改写 | 好 | 差 | 好 |
| 需要训练数据 | 是（嵌入模型） | 否（无参数算法） | 是 |
| 延迟 | 中（需要嵌入） | 低（倒排索引） | 中（并行） |
| 实现复杂度 | 低 | 低 | 中 |

**一句话**：向量检索负责"意会"，BM25 负责"对字"，RRF 负责把两份结果按排名权重合并。

## 先认识 BM25

BM25 是 1994 年 Robertson 提出的经典信息检索算法，至今仍是 Elasticsearch / Lucene 的默认评分函数。

**公式**：

```
score(D, Q) = Σ  IDF(qi) * (f(qi, D) * (k1 + 1)) / (f(qi, D) + k1 * (1 - b + b * |D|/avgdl))
```

- `q_i`：查询中的第 i 个词
- `f(q_i, D)`：词在文档 D 中出现的次数
- `|D|`：文档长度
- `avgdl`：语料库平均文档长度
- `IDF(q_i)`：逆文档频率，衡量词的"稀有度"
- `k1`（默认 1.2）、`b`（默认 0.75）：可调超参数

**直观理解**：

- 词在文档里出现越多，分越高（但有饱和上限，k1 控制饱和速度）
- 词在语料库里越稀有，分越高（IDF 高）
- 文档越短，每个词的"贡献"相对越大（b 控制长度惩罚）

**为什么 BM25 适合精确关键词**：用户搜"E0203 错误"，BM25 直接拿 E0203 这个稀有词的 IDF 算分，命中即高分。而向量检索要把"E0203"嵌入到向量空间，可能和"E0204"的向量距离比"系统报错码"还近——这是向量检索的固有缺陷。

## 然后认识向量检索

向量检索就是"把文本嵌入到高维空间，按距离排序"。

```python
from openai import OpenAI
import numpy as np
import faiss

client = OpenAI(api_key="sk-...")

def embed(texts):
    resp = client.embeddings.create(
        model="text-embedding-3-small",
        input=texts,
    )
    return [d.embedding for d in resp.data]

# 建索引
chunks = [...]  # 切块后的文档
vectors = np.array(embed(chunks)).astype("float32")
vectors = faiss.normalize_L2(vectors)

index = faiss.IndexFlatIP(1536)
index.add(vectors)

def vector_search(query, k=10):
    qv = np.array([embed([query])[0]]).astype("float32")
    faiss.normalize_L2(qv)
    scores, indices = index.search(qv, k)
    return [(int(i), float(s)) for i, s in zip(indices[0], scores[0])]
```

向量检索强在语义层面："怎么让程序跑得快" 和 "性能优化技巧" 的向量距离很近，即便字面完全不一样也能匹配上。

**但它的弱点也很明确**：

- **短词/专有名词**：E0203、iPhone 15 Pro、张三——嵌入模型对这些"低语义内容"表征不好
- **数字**：日期、金额、版本号，向量空间里几乎没有区分度
- **代码标识符**：变量名、函数名、类名

## RRF：把两份排名融成一份

**RRF 公式**：

```
score(doc) = Σ_i  1 / (k + rank_i(doc))
```

- `i`：第 i 个检索源
- `rank_i(doc)`：文档在第 i 个检索源里的排名（从 1 开始）
- `k`：平滑常数，一般取 60

**为什么用 RRF 不用其他融合方式**：

| 融合方式 | 公式 | 问题 |
|---|---|---|
| 加权求和 | `Σ w_i * score_i` | 不同检索源分数量纲不同（向量相似度 0~1，BM25 几十），加权和需要归一化 |
| Min/Max | `min/max(score_i)` | 太敏感，单个低分拖垮整体 |
| 概率融合 | 见 Bayesian | 假设各检索源独立，实际不成立 |
| **RRF** | `Σ 1/(k+rank)` | **只用排名不用分数，天然鲁棒** |

**RRF 的核心优势**：它**只看每个检索源给出的排名，不看原始分数**。向量相似度可能 0.95，BM25 分数可能是 25.3——量纲完全不同，加权求和根本没法直接加。但排名都是"第几名"，天然可比。

**k 参数的作用**：

- k 越小（如 10），排名的"权重差异"越大——第 1 名比第 2 名优势明显
- k 越大（如 100），排名差异被平滑——第 1 名和第 10 名差距小

经验值 k=60 是 RRF 论文里的默认值，生产环境基本照搬。如果某次实验发现排名靠前但不准，可以调大 k 让排名更平滑。

**RRF 的直觉**：

```
某文档：
- 向量检索排名 2
- BM25 排名 5

RRF 分数 = 1/(60+2) + 1/(60+5) = 0.0161 + 0.0154 = 0.0315
```

**两边都排得靠前的文档，RRF 分最高**。这就是为什么混合检索能"各取所长"。

## 完整实现：混合检索 + RRF

```python
from typing import List, Dict, Tuple

# 假设你已经有 vector_search 和 bm25_search 两个函数
def vector_search(query: str, k: int = 10) -> List[Tuple[int, float]]:
    """返回 [(doc_id, similarity), ...]"""
    ...

def bm25_search(query: str, k: int = 10) -> List[Tuple[int, float]]:
    """返回 [(doc_id, bm25_score), ...]"""
    ...

def rrf_fuse(
    rankings: List[List[Tuple[int, float]]],
    k: int = 60,
    top_n: int = 10,
) -> List[Tuple[int, float]]:
    """RRF 融合多个检索源的排名。
    
    rankings: [[(doc_id, score), ...], [(doc_id, score), ...], ...]
    每个子列表是一个检索源的 Top-K 结果（按分数降序）
    """
    scores: Dict[int, float] = {}
    
    for ranking in rankings:
        for rank_idx, (doc_id, _score) in enumerate(ranking, start=1):
            delta = 1.0 / (k + rank_idx)
            scores[doc_id] = scores.get(doc_id, 0.0) + delta
    
    # 按 RRF 分数降序，取 Top-N
    return sorted(scores.items(), key=lambda x: -x[1])[:top_n]


def hybrid_search(query: str, k: int = 10, top_n: int = 10):
    vec_results = vector_search(query, k=k)
    bm25_results = bm25_search(query, k=k)
    fused = rrf_fuse([vec_results, bm25_results], k=60, top_n=top_n)
    return fused


# 使用
results = hybrid_search("E0203 错误的解决方案", k=10, top_n=5)
# 返回 [(doc_id, rrf_score), ...]
```

## 一个完整的 BM25 实现

用 ES 做 BM25 索引：

```python
from elasticsearch import Elasticsearch

es = Elasticsearch("http://localhost:9200")

# 建索引
es.indices.create(index="my_docs", body={
    "settings": {"number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
        "properties": {
            "title": {"type": "text"},
            "body": {"type": "text", "analyzer": "ik_max_word"},  # 中文分词
            "source": {"type": "keyword"},  # 不分析，整字段
        }
    }
})

# 写入文档
def index_docs(docs):
    from elasticsearch.helpers import bulk_index
    bulk_index(es, [
        {"_index": "my_docs", "_id": d["id"], "title": d["title"], 
         "body": d["body"], "source": d["source"]}
        for d in docs
    ])

def bm25_search(query, k=10):
    resp = es.search(index="my_docs", body={
        "size": k,
        "query": {
            "bool": {
                "should": [
                    {"match": {"title": {"query": query, "boost": 2}}},
                    {"match": {"body": query}},
                ]
            }
        }
    })
    return [(int(hit["_id"]), hit["_score"]) for hit in resp["hits"]["hits"]]
```

**注意**：

- 中文文档一定要用合适的分词器（ik_max_word、jieba），默认的 standard 分词器会把"性能优化"切成"性能 优化"两个词
- `boost` 给 title 字段加权重，标题命中比正文命中更重要
- `keyword` 类型不分析，用于精确匹配（如分类标签、产品 ID）

## ES 一站式方案：向量 + BM25 在同一个引擎里

ES 8.x 开始支持 `dense_vector` 类型，可以把向量和 BM25 放在同一个引擎里检索。

```json
// 索引 mapping
{
  "properties": {
    "title": {"type": "text"},
    "body": {"type": "text", "analyzer": "ik_max_word"},
    "embedding": {"type": "dense_vector", "dims": 1536, "index": true, "similarity": "cosine"}
  }
}

// 混合查询
{
  "size": 10,
  "query": {
    "bool": {
      "should": [
        {
          "match": {
            "body": {
              "query": "E0203 错误",
              "boost": 1
            }
          }
        },
        {
          "knn": {
            "field": "embedding",
            "query_vector": [/* 查询向量 */],
            "k": 10,
            "num_candidates": 100
          }
        }
      ]
    }
  }
}
```

ES 会自动给两路结果打分融合，但默认的融合公式不是 RRF。要在 ES 里用真正的 RRF，需要分别查两次再自己融合：

```python
def es_hybrid_rrf(query, query_vector, k=10):
    # 单独跑 BM25
    bm25_hits = es.search(index="my_docs", body={
        "size": k,
        "query": {"match": {"body": query}}
    })
    bm25_results = [(int(h["_id"]), h["_score"]) for h in bm25_hits["hits"]["hits"]]
    
    # 单独跑向量
    vec_hits = es.search(index="my_docs", body={
        "size": k,
        "knn": {
            "field": "embedding",
            "query_vector": query_vector,
            "k": k,
            "num_candidates": 100
        }
    })
    vec_results = [(int(h["_id"]), h["_score"]) for h in vec_hits["hits"]["hits"]]
    
    # 用 RRF 融合
    return rrf_fuse([vec_results, bm25_results], k=60, top_n=k)
```

## 工程实践要点

### 1. k 参数先固定 60，调参放后面

RRF 的 k=60 是论文默认值，绝大多数场景下效果已经足够好。先别花时间调它，把精力放在 embedding 模型选择和分块策略上。

### 2. 两路检索的 k 可以不一样

向量检索通常召回更多候选（k=20~50），BM25 召回少一些（k=10~20）。这是因为向量检索是 ANNS 近似，召回率不稳定；BM25 是精确倒排，召回可控。

```python
def hybrid_search(query, vec_k=20, bm25_k=15, top_n=10):
    vec_results = vector_search(query, k=vec_k)
    bm25_results = bm25_search(query, k=bm25_k)
    return rrf_fuse([vec_results, bm25_results], k=60, top_n=top_n)
```

### 3. 别忘了 Reranker

混合检索只是把"还行"的候选捞出来，最后还是值得过一道 Reranker：

```python
def hybrid_search_with_rerank(query, top_n=5):
    fused = hybrid_search(query, top_n=20)  # 先粗筛 20 个
    # 过 Reranker 精排
    candidates = [chunks[did] for did, _ in fused]
    reranked = rerank(query, candidates, top_n=top_n)
    return reranked
```

**混合检索 + Reranker** 是当前生产环境的"标配组合"。单 Reranker 不如单混合，单混合不如两者叠加。

### 4. 索引要保持同步

向量和 BM25 索引必须指向**同一份文档**。文档新增/删除/更新时，两边都要同步。ES 一站式方案的好处就是天然一致；分开部署要自己保证同步（用消息队列或事务）。

### 5. 元数据过滤

实际场景经常需要过滤（只看某个部门的文档、只看某个时间后的文档）。ES 的 filter 天然支持；纯向量库（FAISS）需要在检索后用 metadata 过滤，召回率会受影响。

```json
{
  "query": {
    "bool": {
      "must": [{"match": {"body": query}}],
      "filter": [
        {"term": {"department": "eng"}},
        {"range": {"updated_at": {"gte": "2024-01-01"}}}
      ]
    }
  }
}
```

### 6. 监控两路召回率

上线后要分别监控"纯向量"、"纯 BM25"、"RRF 融合"三组 Top-K 的命中率，看哪个环节是瓶颈。如果发现 RRF 没带来提升，可能是某一检索源的 embedding/分词器有问题。

## 常见坑

**坑 1：直接拿 BM25 分数和向量相似度加权求和**

向量相似度 0~1，BM25 分数可能几十上百，加权求和前必须做归一化（min-max 或 z-score）。RRF 不存在这个问题——它只看排名。

**坑 2：在 RRF 之后再算一次加权**

RRF 已经是融合结果，分数本身就是"排名加权后的综合分"，再算加权没意义。

**坑 3：BM25 用了错误的分词器**

默认 standard 分词器把中文"性能优化"切成"性能 优化"两个 token，BM25 失效。中文项目必须用 ik_max_word 或 jieba 之类的分词器。

**坑 4：向量模型和嵌入不匹配**

向量和 BM25 是两套索引，对应的文档内容必须一致。如果你更新了文档但只更新了一边，检索结果会"飘"。

**坑 5：两路检索的 k 设得一样**

向量检索（k=10）和 BM25（k=10）一样，但向量检索是近似，BM25 是精确。BM25 的 k=10 是"真正命中 10 个"，向量的 k=10 是"近似 10 个"。混合时让向量侧多召一些，给 RRF 更多候选融合。

## 什么时候不该用混合检索

混合检索不是万灵药，下面几个场景不适合：

- **极短文档库**（< 100 篇）：直接全文塞 Prompt 更准，没必要建索引
- **纯结构化数据**（JSON、表格）：BM25 + JSON Path 就够，不需要向量
- **延迟极端敏感**（< 50ms）：BM25 单独就能做到，混合检索延迟翻倍
- **数据量极小**：FAISS + BM25 都能跑，但维护成本大于收益

## 一句话总结

混合检索的本质是"承认单一检索方式有盲区"。向量检索负责语义相似，BM25 负责关键词命中，RRF 把两份排名融合成一份——这是 2024 年后被无数生产 RAG 系统验证过的工程共识。实现简单（两路检索 + 一个 RRF 函数，几十行代码），效果显著（召回率普遍提升 20-40%），是 RAG 检索环节的高性价比升级。先把它跑起来，再考虑 Reranker 等更进阶的优化。
