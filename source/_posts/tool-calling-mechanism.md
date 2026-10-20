---
title: Tool Calling 是让 LLM 动手的核心机制
date: 2026-10-19 10:00:00
type: tech
permalink: /2026/10/19/tool-calling-mechanism/
tags:
  - Tool-Calling
  - LLM
  - Agent
  - API-设计
categories:
  - 技术思考
description: Tool Calling 的本质是"让 LLM 输出结构化调用请求"。讲清楚机制、为什么比 Function Prompt 强、和 RAG 的关系，以及实际工程里的坑。
---

## 先说结论

Tool Calling（也叫 Function Calling）是大模型从"对话工具"进化到"Agent"的核心机制。它的本质是：让 LLM 按预设的 JSON Schema 输出**结构化的工具调用请求**，由外部代码执行，把结果喂回去，再让 LLM 基于结果继续思考或回答。

听起来抽象，但实现只有几十行代码。这篇文章讲清楚机制、和 Prompt 工程的对比、与 RAG 的关系，以及工程里的坑。

## 为什么需要 Tool Calling

LLM 有几个天生的限制：

- 不知道实时信息（训练截止时间）
- 不会计算精确数字（"算一下 0.3 的 100 次方"它会瞎猜）
- 不能操作外部系统（不能查数据库、发邮件、调 API）
- 上下文窗口有限

Tool Calling 就是把这些能力通过"工具"的形式挂给 LLM：你说"调个搜索工具"，它就输出一个 `{"name": "search", "args": {"q": "..."}}`，外部代码执行搜索，把结果返回，LLM 接着用。

**没有 Tool Calling，LLM 就是个会说话的书呆子；有了 Tool Calling，它才有"动手能力"。**

## 机制：四步走

```
1. 声明工具  →  用 JSON Schema 描述"我有哪些工具、参数长啥样"
2. 调用 LLM  →  带 tools 参数请求
3. LLM 输出  →  返回 tool_calls: [{name, args, id}]
4. 执行并回传  →  跑工具，把结果作为 role=tool 的消息加回对话
```

```json
// 1. 声明工具
{
  "type": "function",
  "function": {
    "name": "get_weather",
    "description": "查询某城市当前天气",
    "parameters": {
      "type": "object",
      "properties": {
        "city": { "type": "string", "description": "城市名，如 '北京'" }
      },
      "required": ["city"]
    }
  }
}

// 2. 调用 LLM
{
  "model": "gpt-4o-mini",
  "messages": [{"role": "user", "content": "北京今天天气怎么样？"}],
  "tools": [/* 上面的 tool 定义 */]
}

// 3. LLM 输出
{
  "message": {
    "role": "assistant",
    "tool_calls": [{
      "id": "call_abc123",
      "type": "function",
      "function": {
        "name": "get_weather",
        "arguments": "{\"city\": \"北京\"}"
      }
    }]
  }
}

// 4. 回传结果
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "content": "{\"temperature\": 22, \"condition\": \"晴\"}"
}
```

整个过程就是 LLM 在对话里加了一条"我想调工具"的消息，外部代码执行后把结果作为新消息塞回去。下一轮 LLM 就能看到结果。

## 完整代码示例

```python
import json
from openai import OpenAI

client = OpenAI(api_key="sk-...")

# 1. 声明工具
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "查询某城市当前天气",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {"type": "string", "description": "城市名"}
                },
                "required": ["city"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": "执行数学计算，支持加减乘除和括号",
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {"type": "string", "description": "数学表达式，如 '3+5*2'"}
                },
                "required": ["expression"]
            }
        }
    }
]

# 2. 实现工具
def get_weather(city):
    # 实际项目里调外部 API
    return {"city": city, "temperature": 22, "condition": "晴"}

def calculate(expression):
    try:
        return str(eval(expression))
    except:
        return f"无法计算: {expression}"

TOOLS_IMPL = {"get_weather": get_weather, "calculate": calculate}

# 3. Agent 主循环
def run_agent(user_input, max_iterations=5):
    messages = [
        {"role": "system", "content": "你是一个可以调用工具的助手"},
        {"role": "user", "content": user_input}
    ]
    
    for i in range(max_iterations):
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            tools=TOOLS,
            tool_choice="auto"  # auto / required / none / 指定工具名
        )
        msg = resp.choices[0].message
        
        if msg.tool_calls:
            # LLM 想调工具
            for tc in msg.tool_calls:
                # 记录 LLM 的调用请求
                messages.append({
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [tc]
                })
                
                # 执行工具
                name = tc.function.name
                args = json.loads(tc.function.arguments)
                result = TOOLS_IMPL[name](**args)
                
                # 把结果作为 tool 消息回传
                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": json.dumps(result, ensure_ascii=False)
                })
        else:
            # LLM 决定直接回答
            return msg.content
    
    return "超过最大迭代次数"

# 测试
print(run_agent("北京今天天气怎么样？顺便算一下 3.14 * 100"))
```

这个循环就是 Agent 的核心——LLM 决定调什么工具，外部代码执行，结果回传，LLM 继续，直到它决定直接回答用户。

## 为什么 Tool Calling 比"用 Prompt 调工具"强

早期（2022 年之前）大家都用 Prompt 工程模拟工具调用：

```
[system]
你是一个工具调用助手。可用工具：
- get_weather(city): 查询天气
- calculate(expr): 计算数学表达式

如果用户的问题需要工具，请输出如下 JSON：
{"tool": "get_weather", "args": {"city": "北京"}}

否则直接回答。
```

这种方案的问题：

| 维度 | Prompt 模拟 | Tool Calling |
|---|---|---|
| 输出格式 | 自由文本里嵌 JSON，经常格式错 | 结构化字段，模型原生支持 |
| 解析可靠性 | 需要正则/容错解析 | 框架直接拿 |
| 工具描述位置 | 堆在 system prompt，挤占上下文 | 走 tools 参数，不计入对话历史 |
| 多工具支持 | 难，容易混 | 原生支持 N 个工具 |
| 模型选择 | 看 Prompt 写得好不好 | tool_choice 控制强制/可选 |
| 推理效率 | 浪费 token | 模型有专门优化 |

**核心区别**：Tool Calling 把工具从 Prompt 里抽出来，变成了模型的**一等公民**。模型在训练时就学过怎么输出 tool_calls 字段，比"在自由文本里编 JSON"可靠得多。

## 各模型的 Tool Calling 支持

| 模型 | 支持情况 | 备注 |
|---|---|---|
| OpenAI gpt-4o / 4.1 / o1 | 完整支持 | 事实标准 |
| Anthropic Claude | 完整支持 | tool_choice: "any" 强制调 |
| Google Gemini | 完整支持 | 命名是 function_call |
| DeepSeek V3 / R1 | 完整支持 | R1 思考后再调用 |
| Qwen2.5 / Qwen3 | 完整支持 | 中文友好 |
| Llama 3.1 | 完整支持 | 社区版支持 |
| 早期 7B 小模型 | 部分支持 | 训练时未充分训练 |

**一个细节**：reasoning 模型（DeepSeek R1、OpenAI o1）会先思考再决定调什么工具，决策质量明显更好。代价是延迟。

## 工程实践要点

### 1. 工具的 description 写得像说明书

模型选不选你的工具，主要看 description。写得模糊 = 模型选错。

```json
// ❌ 模糊
"description": "查询天气"

// ✅ 清晰
"description": "查询指定城市的实时天气，返回温度（摄氏度）、天气状况、湿度。城市名必须是中文常用名，如 '北京'、'上海'。"
```

**好 description 的特征**：

- 说明**做什么**（动词开头）
- 说明**返回什么**（输出结构）
- 说明**输入要求**（参数格式、边界）
- 必要时给**例子**

### 2. 参数 schema 要完整

```json
// ❌ 没 required
"parameters": {"type": "object", "properties": {"city": {"type": "string"}}}

// ✅ 明确 required
"parameters": {
  "type": "object",
  "properties": {
    "city": {"type": "string", "description": "中文城市名"}
  },
  "required": ["city"]
}
```

不写 required 模型可能传空对象，导致工具调用失败。

### 3. 工具结果要 JSON 序列化回传

工具返回的不能是裸对象，必须是字符串（一般是 JSON 字符串）。OpenAI API 规定 tool 消息的 content 是字符串。

```python
# ❌ 错
messages.append({"role": "tool", "content": result_dict})

# ✅ 对
messages.append({"role": "tool", "content": json.dumps(result, ensure_ascii=False)})
```

### 4. 控制最大迭代次数

LLM 可能陷入循环——它调了一个工具，结果不满意，又调一次，又调一次……设个上限（一般 5-10 轮）保平安。

```python
for _ in range(max_iterations=5):
    ...
```

### 5. 谨慎使用 tool_choice

`tool_choice` 控制 LLM 怎么调工具：

- `"auto"`：模型自己决定（默认，推荐）
- `"required"`：必须调用某个工具
- `"none"`：禁止调用工具（强制生成回答）
- `{"type": "function", "function": {"name": "x"}}`：必须调用 x 工具

**99% 场景用 auto**，其他三个是特殊场景的逃生舱。

### 6. 处理并行工具调用

`tool_calls` 是个数组，模型可能一次性返回多个工具调用（比如同时查两个城市天气）。要按数组遍历执行：

```python
for tc in msg.tool_calls:  # 遍历所有调用
    ...
```

不要把 `msg.tool_calls` 当单个对象处理，会漏。

## 常见坑

**坑 1：把工具调用当成 Prompt 工程的一部分**

很多团队把工具描述塞进 system prompt 拼字符串，结果模型经常输出格式错误。这是 Tool Calling 之前时代的思路。用原生 `tools` 参数，别自己拼。

**坑 2：工具的 description 写得像注释**

`"description": "搜索"` —— 模型看这个根本不知道能搜什么。description 是给模型看的，写清楚做什么、参数怎么用、返回什么。

**坑 3：不限制迭代次数**

LLM 偶尔会陷入"调工具 → 不满意 → 再调 → 再不满意 → 再调"的循环。无限循环 = 无限 token 烧钱 + 用户等死。设 max_iterations=5~10。

**坑 4：工具返回值太大**

工具返回一个 1MB 的 JSON，全塞进上下文，既贵又稀释注意力。返回结果要裁剪，只保留关键字段。

**坑 5：忽略 tool_call_id**

`tool` 消息必须带 `tool_call_id`，对应之前 `tool_calls[i].id`。漏了会 API 报错。

**坑 6：在 tool 消息里塞 markdown**

`tool` 消息的 content 是字符串，不是渲染的 Markdown。别写 `**加粗**`、`[链接]()`，模型读的是原始字符串。要格式就用 JSON。

## Tool Calling 和 RAG 的关系

RAG 是 Tool Calling 的一个特例：把"检索"作为一个工具暴露给 Agent。

```python
# RAG-as-Tool 的写法
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": "在知识库中搜索相关内容。当问题涉及公司政策、产品文档、内部资料时使用。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "搜索关键词"},
                    "top_k": {"type": "integer", "description": "返回结果数，默认 3"}
                },
                "required": ["query"]
            }
        }
    }
]
```

**两种 RAG 模式的对比**：

| 维度 | 固定 RAG | RAG-as-Tool |
|---|---|---|
| 触发方式 | 每次都检索 | Agent 决定要不要检索 |
| 适用场景 | 问题明确、知识库固定 | 复杂场景、多种知识源 |
| 延迟 | 稳定 | 不确定（看 Agent 决策） |
| 灵活性 | 低 | 高 |
| 复杂度 | 低 | 高 |

固定 RAG 适合"知识库问答"这种明确场景；RAG-as-Tool 适合 Agent 架构，Agent 可以自主决定"我要查一下"或者"我记得，不用查"。

下一篇博客讲混合检索（向量 + BM25 + RRF），那是 RAG 检索环节的工程进阶。

## 一句话总结

Tool Calling 不是"让 LLM 多说话"，而是给它装上手——能调工具、能拿数据、能跟外部世界交互。机制简单（四步走），实现容易（几十行代码），工程要点全在工具的 description、参数 schema、迭代控制这三件事上。把它做好，LLM 就从"会聊天的书呆子"变成"会干活的 Agent"。
