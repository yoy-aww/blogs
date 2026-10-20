---
title: LLM 应用全链路观测：可观测性在 Agent 时代怎么落地
date: 2026-10-19 14:00:00
type: tech
permalink: /2026/10/19/llm-observability-tracing-logging/
tags:
  - 可观测性
  - Observability
  - OpenTelemetry
  - Agent
  - Langfuse
categories:
  - 技术思考
description: LLM 应用不是黑盒，但也不是传统微服务。Tracing、Logging、Metrics 三件套在 LLM 时代有了新语义：每一步 prompt、token、工具调用都要可追踪。本文讲清楚新语义、新工具、和 OTel GenAI 规范。
---

## 先说结论

传统可观测性的三大支柱——Tracing、Logging、Metrics——在 LLM 应用里全部要"翻译"一遍，因为 LLM 应用有几个本质不同的特征：

1. **非确定性**。同一输入跑两次，输出可能完全不同
2. **多步循环**。一次请求可能跑 3 次 LLM、2 次工具、1 次检索
3. **成本维度**。除了延迟，还要盯 token 消耗和费用
4. **语义不可比**。"质量差"无法用 503 表示，需要人来评估

这套新语义的工程落地正在快速标准化：OpenTelemetry GenAI Semantic Conventions 把跨语言的 span 属性统一了，Langfuse / LangSmith / Phoenix 这些平台把 LLM 特定的可视化做出来了。这篇文章讲清楚"翻译"的细节和工具选型。

## 三大支柱在 LLM 时代的新语义

### Tracing：一次请求经过哪些步骤

传统微服务的 Tracing 关注"调用链"：哪个服务调了哪个服务、每跳耗时多少。

LLM 应用的 Tracing 关注**Agent 轨迹**：用户输入 → 规划 → 检索 → LLM 调用 1 → 工具调用 → LLM 调用 2 → ... → 最终回答。

```
[trace_id=abc123] 用户提问"北京天气怎么样"
├─ [span_id=001] agent.plan        12ms
│    └─ [span_id=002] llm.generate 150ms  (gpt-4o-mini, 45 tokens)
├─ [span_id=003] agent.tool        320ms
│    └─ [span_id=004] tool.get_weather 280ms
├─ [span_id=005] agent.llm         280ms  (gpt-4o-mini, 180 tokens)
└─ [span_id=006] agent.finalize     5ms

总耗时：777ms，token 消耗：225，工具调用：1
```

**LLM 时代 Tracing 的关键属性**：

| 属性 | 传统 | LLM 应用 |
|---|---|---|
| span 类型 | http / db / cache | llm / tool / retriever / agent |
| 耗时关注 | 网络 + 计算 | LLM 推理 + 工具执行 |
| 输入输出 | request/response body | prompt / completion / tool args |
| 成本维度 | 流量 | token 数 + 单价 |

### Logging：每一步的输入输出和决策

传统日志关注"发生了什么错误"。LLM 应用的日志要关注"模型为什么这么答"。

**至少记录的字段**：

- 每次 LLM 调用的**完整 prompt**（system + messages）
- 每次 LLM 调用的**完整 completion**
- 每次工具调用的**参数和返回**
- 每次检索的**查询和 Top-K 结果**
- 模型的 reasoning（思考过程，如果模型支持）
- token 消耗（input / output / total）
- 延迟（time_to_first_token / total）

```python
import logging
import time

def log_llm_call(span, prompt, completion, tokens, latency):
    logger.info(json.dumps({
        "event": "llm_call",
        "model": span.model,
        "prompt": prompt,             # 完整 prompt，可截断超长部分
        "completion": completion,
        "tokens": tokens,             # {input: 120, output: 85, total: 205}
        "latency_ms": latency,
        "tool_calls": completion.get("tool_calls", []),
    }))
```

**注意**：生产环境的 prompt 可能包含敏感信息（用户隐私、商业机密）。日志里要不要打完整 prompt？这是个权衡：

- 打完整 prompt：调试方便，但合规风险高
- 不打：调试要重建现场，几乎不可能
- 折中：按数据类型决定，PII 脱敏，业务数据全量打

### Metrics：成本、延迟、质量

传统 Metrics 关注 QPS、延迟、错误率。LLM 应用要加几个新维度：

| 指标 | 单位 | 含义 |
|---|---|---|
| `llm.tokens.input` | tokens/请求 | 输入 token 消耗 |
| `llm.tokens.output` | tokens/请求 | 输出 token 消耗 |
| `llm.tokens.total` | tokens/请求 | 总 token 消耗 |
| `llm.cost.usd` | $/请求 | 单次请求费用（按模型单价算） |
| `llm.latency.ttft` | ms | 首 token 延迟（流式输出） |
| `llm.latency.total` | ms | 总延迟 |
| `agent.iterations` | 次/请求 | Agent 迭代次数 |
| `agent.tool_calls` | 次/请求 | 工具调用次数 |
| `retriever.hits` | 个/请求 | 检索召回数 |
| `llm.errors` | 个 | 模型错误（拒答、超上下文、超时） |

**为什么这些指标重要**：

- token 消耗直接影响成本和延迟——一个 Agent 迭代 10 轮，token 是单轮的 10 倍
- 错误率不能只看 5xx，LLM 的"幻觉"、"拒答"也是错误，要单独统计
- 工具调用次数能反映 Agent 在不在"打转"——一个简单问题调 5 次工具，可能陷入循环

## OpenTelemetry GenAI Semantic Conventions

OpenTelemetry 在 2024 年发布了 GenAI Semantic Conventions，给 LLM span 一套统一的属性定义。这是当前跨框架观测的事实标准。

**核心 span 类型**：

| Span Kind | 用途 |
|---|---|
| `genai.operation.name` | 操作名（chat / embeddings / completions） |
| `genai.system` | 模型提供商（openai / anthropic / deepseek） |
| `genai.request.model` | 具体模型名 |
| `genai.request.max_tokens` | 请求的最大 token |
| `genai.response.model` | 实际响应的模型 |
| `genai.usage.input_tokens` | 输入 token |
| `genai.usage.output_tokens` | 输出 token |
| `genai.prompt` | 完整 prompt（敏感） |
| `genai.completion` | 完整 completion（敏感） |
| `genai.tool.call.arguments` | 工具调用参数 |
| `genai.tool.call.result` | 工具调用结果 |

**一个示例**：

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

tracer = trace.get_tracer("llm-app")

def call_llm(model, messages, tools=None):
    with tracer.start_as_current_span("genai.chat") as span:
        span.set_attribute("genai.operation.name", "chat")
        span.set_attribute("genai.system", "openai")
        span.set_attribute("genai.request.model", model)
        span.set_attribute("genai.request.max_tokens", 1024)
        # prompt 和 completion 可能敏感，用 OTel 的 LogRecord 而不是 span attribute
        # 或配置 redaction
        
        start = time.time()
        resp = client.chat.completions.create(
            model=model, messages=messages, tools=tools
        )
        elapsed_ms = (time.time() - start) * 1000
        
        usage = resp.usage
        span.set_attribute("genai.usage.input_tokens", usage.prompt_tokens)
        span.set_attribute("genai.usage.output_tokens", usage.completion_tokens)
        span.set_attribute("llm.latency.total_ms", elapsed_ms)
        
        if resp.choices[0].message.tool_calls:
            span.set_attribute("genai.tool_calls_count", len(resp.choices[0].message.tool_calls))
        
        return resp
```

OTel 的优势是**框架无关**：无论你用 LangChain、LlamaIndex、LangGraph 还是手写，span 属性都是同一套，下游可以统一分析。

## 主流 LLM 可观测平台

OTel 是底层规范，上层有多个平台提供 LLM 特定的可视化。

| 平台 | 部署 | 特点 | 价格 |
|---|---|---|---|
| Langfuse | 自托管 / 云 | 开源、Python SDK 友好、自带 LLM-as-judge 评估 | 自托管免费，云按用量 |
| LangSmith | 云（LangChain 官方） | 和 LangChain 深度集成、自动 instrumentation | 免费层 + 付费 |
| Arize Phoenix | 自托管 / 云 | 基于 OTel、注重评估和监控 | 自托管免费 |
| Helicone | 代理模式 | 在 LLM API 调用前加一层 proxy，零代码接入 | 有免费层 |
| Langfuse + OTel | 组合 | Langfuse 已支持 OTel ingestion | 自托管免费 |

**怎么选**：

- 团队用 LangChain / LangGraph → LangSmith（深度集成）
- 想自托管 + 开源 → Langfuse 或 Phoenix
- 想用 OpenTelemetry 标准 → Phoenix
- 想零代码接入 → Helicone（代理模式）
- 已经用 Datadog / Grafana → 看 GenAI add-on

## 实战：用一个 OpenAI 客户端包装出完整可观测

```python
import time
import json
from openai import OpenAI
from opentelemetry import trace
from langfuse import Langfuse

trace.set_tracer_provider(
    # 配置 OTel exporter，比如 OTLP endpoint
)
tracer = trace.get_tracer("llm-app")

langfuse = Langfuse(public_key="...", secret_key="...", host="https://cloud.langfuse.com")

client = OpenAI(api_key="sk-...")

def call_llm_with_observability(model, messages, tools=None, **kwargs):
    """包装 LLM 调用，自动打点"""
    
    # Langfuse 追踪（高业务价值场景）
    trace_ctx = langfuse.trace(
        name=f"llm.{model}",
        input={"messages": messages, "tools": tools},
    )
    
    # OTel span（通用基础设施）
    with tracer.start_as_current_span("genai.chat") as span:
        span.set_attribute("genai.system", "openai")
        span.set_attribute("genai.request.model", model)
        span.set_attribute("genai.operation.name", "chat")
        
        start = time.time()
        try:
            resp = client.chat.completions.create(
                model=model, messages=messages, tools=tools, **kwargs
            )
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(error))
            trace_ctx.update(output={"error": str(e)})
            raise
        
        elapsed_ms = (time.time() - start) * 1000
        usage = resp.usage
        
        # OTel 属性
        span.set_attribute("genai.usage.input_tokens", usage.prompt_tokens)
        span.set_attribute("genai.usage.output_tokens", usage.completion_tokens)
        span.set_attribute("llm.latency.total_ms", elapsed_ms)
        
        # 工具调用信息
        tool_calls = resp.choices[0].message.tool_calls
        if tool_calls:
            span.set_attribute("genai.tool_calls_count", len(tool_calls))
            for tc in tool_calls:
                span.add_event("tool_call", {
                    "name": tc.function.name,
                    "arguments": tc.function.arguments,
                })
        
        # Langfuse 记录（含完整 prompt/completion）
        trace_ctx.update(
            output=resp.choices[0].message.content,
            metadata={
                "usage": {"input": usage.prompt_tokens, "output": usage.completion_tokens},
                "latency_ms": elapsed_ms,
            }
        )
        
        return resp
```

## 评估：LLM 特有的可观测维度

LLM 应用的可观测性还有一个传统系统没有的维度——**质量评估**。

### LLM-as-judge

用另一个 LLM 评估主 LLM 的输出质量：

```python
def judge_response(query, response, reference=None):
    judge_prompt = f"""
评估以下回答的质量，按 1-10 打分。

问题：{query}
回答：{response}
{f"参考答案：{reference}" if reference else ""}

评分维度：
- 准确性（事实是否正确）
- 完整性（是否回答了所有要点）
- 一致性（是否和参考资料一致）
- 安全性（是否有不当内容）

只输出 JSON：{{"score": <1-10>, "reasons": ["...", "..."]}}
"""
    resp = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": judge_prompt}],
    )
    return json.loads(resp.choices[0].message.content)
```

**用法**：定期采样线上请求，跑一遍 judge，得到质量分布。如果发现某个 prompt 的评分下降，及时报警。

### RAG 评估的常见指标

| 指标 | 含义 | 怎么测 |
|---|---|---|
| Faithfulness | 回答是否忠于参考资料 | LLM-judge 比对回答和引用 |
| Relevance | 检索结果是否相关 | 人工标注 / embedding 距离 |
| Answer Relevance | 回答是否针对问题 | LLM-judge |
| Context Recall | 检索覆盖率 | 用 ground truth 比对 |

Ragas、DeepEval、Giskard 这些库专门做 RAG 评估。生产 RAG 系统要有这套指标，否则改 prompt 改到崩都不知道。

## 工程实践要点

### 1. 采样而不是全量打 trace

LLM 调用量大时，全量打 trace 成本爆炸。常见的采样策略：

- **错误全采样**：任何失败都记录
- **延迟尾采样**：超过 P95 延迟的采样
- **随机采样**：1% 流量采样
- **基于 trace_id hash**：同一请求链路要么全采要么全不采（保证链路完整）

### 2. Prompt 和 completion 的存储要分级

完整 prompt/completion 价值高但成本高、合规风险大。常见分级：

- **生产环境**：只存 hash + 元数据（token 数、模型、耗时）
- **调试环境**：完整存储
- **敏感字段**：PII 脱敏后存储

### 3. Token 消耗单独监控

LLM 应用的成本主要看 token。建一个 Grafana 面板，按模型、按业务线、按用户维度看 token 消耗，定期 review。

### 4. 错误类型要细分

传统系统看 5xx 就够了，LLM 应用要细分：

- **模型拒答**（content_filter 触发）
- **超上下文**（context_length_exceeded）
- **工具调用失败**（tool execution error）
- **Agent 死循环**（超过最大迭代次数）
- **幻觉**（输出和参考资料不一致，需要 LLM-judge 检测）

### 5. 用 trace_id 关联全链路

一次用户请求可能跨多个服务（API → Agent → LLM → Tool → DB），用统一的 trace_id 关联起来，下游分析才能看到完整链路。OTel 的 context propagation 就是这个目的。

## 常见坑

**坑 1：日志里没记录完整 prompt**

线上出问题，想复现时发现日志里只有模型名和耗时，没有 prompt——基本不可能复现。生产日志要么完整记录，要么至少记录 prompt 的 hash + 关键字段。

**坑 2：忽略 token 成本监控**

一个 Agent 死循环能烧掉几千美元。token 消耗必须实时告警，特别是 `agent.iterations > 5` 的请求要单独看。

**坑 3：用传统 APM 直接套**

Datadog APM 默认不认识 LLM 特定的属性（token、tool_calls）。要么用 GenAI add-on，要么自己打自定义 span attribute，否则数据进了平台但分析不了。

**坑 4：把所有 trace 都送 Langfuse**

Langfuse 按用量收费（云版），全量打成本不低。采样策略先想清楚，别上来就 100%。

**坑 5：忽略质量评估**

只监控延迟和错误率，没监控质量。模型升级后线上回答变差，根本发现不了。LLM-judge 至少要定期跑。

**坑 6：prompt 里塞了密钥/PII 不脱敏**

把用户邮箱、token、密码全打日志，合规直接炸。日志存储前必须脱敏。

## 一句话总结

LLM 应用的可观测性 = 三大支柱的语义翻译 + 一批新指标（token、工具调用、质量）+ LLM 特定的评估维度。OTel GenAI Semantic Conventions 是事实标准，Langfuse / Phoenix / LangSmith 是上层可视化。先把 prompt、completion、token、tool_call 这四样东西稳定记录下来，再谈优化和监控——没有这四样，LLM 应用就是个黑盒。
