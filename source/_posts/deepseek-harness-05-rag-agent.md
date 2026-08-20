---
title: DeepSeek + RAG + Agent：构建可落地的 AI 应用完整指南
date: 2026-08-20 13:00:00
tags:
  - DeepSeek
  - RAG
  - Agent
  - 应用开发
  - 创业
description: 从技术选型到架构设计，手把手教你用 DeepSeek 构建 RAG 和 Agent 应用——包含代码示例、架构决策与踩坑指南。
---

## 什么是"真正能用"的 AI 应用

2025 年的时候，市面上充斥着各种"AI 应用"——AI 写作助手、AI 翻译工具、AI 聊天机器人。大多数都不过是把一个大模型的 API 包了一层 UI。它们有一个共同的问题：当模型"不知道"的时候，它们就开始编造。

真正有价值的 AI 应用必须解决两个问题：第一，让模型知道它不知道什么；第二，当模型不知道的时候，它能从外部获取正确的信息。这就是 RAG（Retrieval-Augmented Generation）要解决的问题。

而 Agent 更进一步——它不只是给模型提供信息，还让模型有能力"做"事情：调用工具、查询数据库、执行代码、发送邮件。

DeepSeek 在这两个方向上都提供了非常好的支持。V4-Flash 的 100 万 token 上下文让 RAG 的检索范围大幅扩大，而 API 层的 Tool Calls 支持让 Agent 架构变得简单。这篇文章我就从架构设计到代码实现，完整讲一遍。

## RAG 架构设计

### 什么是 RAG

RAG 的核心思想很简单：在让模型回答用户问题之前，先从外部知识库中检索相关信息，然后把检索到的内容作为上下文提供给模型。模型的回答就基于这些检索到的信息。

```
用户提问 → 向量检索 → 检索结果 + 用户问题 → LLM 生成回答
```

### 为什么 DeepSeek 特别适合 RAG

第一，V4-Flash 的 100 万 token 上下文是 RAG 的杀手级能力。传统的 RAG 系统受限于模型的上下文长度（通常 8K-32K tokens），只能检索少量相关文档。V4-Flash 的 100 万 token 意味着你可以直接把大量文档塞进上下文，让模型自己筛选——这是一种更简单、更强大的 RAG 范式。

第二，DeepSeek 的训练数据规模（32T+ tokens）让它对中文和英文都有很好的理解能力，适合做跨语言检索。

第三，价格优势。RAG 系统的输入 token 消耗通常很大（因为要检索大量文档），V4-Flash 的输入价格（3 元/百万 tokens）让大规模 RAG 在成本上变得可行。

### RAG 的两种模式

**模式一：传统 RAG（检索增强）**

适合场景：文档库较大（10 万+ 文档），用户问题多样化。

流程：
1. 将文档切片并计算向量嵌入
2. 用户提问时，计算问题的向量
3. 在向量数据库中搜索最相似的 K 个文档片段
4. 将检索结果拼接为上下文，发送给模型

**模式二：超长上下文 RAG（直接塞入）**

适合场景：文档库较小（1000 篇以内），模型上下文长度足够大。

流程：
1. 把所有相关文档直接拼接到上下文中
2. 告诉模型"下面这些是你的参考资料"
3. 模型基于完整上下文生成回答

在 V4-Flash 的 100 万 token 上下文支持下，模式二变得非常实用。对于 500 篇以内的文档库，直接塞入的方式反而更简单、更可靠——不需要复杂的向量检索系统。

## RAG 实现：完整代码示例

### 方案一：基于 LangChain 的传统 RAG

```python
from langchain_deepseek import DeepSeekChat
from langchain_community.vectorstores import Chroma
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.embeddings import DeepSeekEmbeddings
import os

# 初始化模型
llm = DeepSeekChat(
    model="deepseek-v4-flash",
    api_key=os.environ["DEEPSEEK_API_KEY"],
    base_url="https://api.deepseek.com"
)

# 嵌入模型（可以用 DeepSeek 的嵌入模型）
embeddings = DeepSeekEmbeddings(
    api_key=os.environ["DEEPSEEK_API_KEY"]
)

# 文档分割
text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=500,
    chunk_overlap=50,
    separators=["\n\n", "\n", "。", " ", ""]
)

# 构建向量数据库
def build_vector_store(documents):
    chunks = text_splitter.split_documents(documents)
    vectorstore = Chroma.from_documents(
        chunks, embeddings, persist_directory="./chroma_db"
    )
    return vectorstore

# 构建检索器
def build_retriever(vectorstore):
    return vectorstore.as_retriever(
        search_type="mmr",
        search_kwargs={"k": 5, "lambda_multiplier": 0.7}
    )

# RAG 链
from langchain.chains import create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain
from langchain_core.prompts import ChatPromptTemplate

prompt = ChatPromptTemplate.from_template("""
你是一个智能助手。基于以下参考资料回答用户问题：

参考资料：
{context}

用户问题：{input}

如果参考资料中没有相关信息，请明确说"根据我掌握的信息，无法回答这个问题"，不要编造答案。
""")

def build_rag_chain(retriever):
    combine_docs_chain = create_stuff_documents_chain(llm, prompt)
    return create_retrieval_chain(retriever, combine_docs_chain)

# 使用
chain = build_rag_chain(build_retriever(build_vector_store(documents)))
result = chain.invoke({"input": "DeepSeek V3 的架构是什么？"})
print(result["answer"])
```

### 方案二：基于超长上下文的简单 RAG

这是 V4-Flash 的 100 万 token 上下文带来的简化方案——不需要向量数据库，不需要检索器：

```python
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["DEEPSEEK_API_KEY"],
    base_url="https://api.deepseek.com"
)

def simple_rag(documents, user_question):
    # 将所有文档直接拼接
    context = "\n\n".join(documents)
    
    # 检查总长度是否在上下文限制内
    # V4-Flash 支持 100 万 token，约 50 万中文字
    total_chars = len(context) + len(user_question)
    if total_chars > 300000:  # 留一些余量
        # 如果太长，取最近/最相关的文档
        context = context[:290000]
        context += "\n\n[文档过长，已截断]"
    
    messages = [
        {"role": "system", "content": "你是一个智能助手。基于参考资料回答问题。"},
        {"role": "user", "content": f"参考资料：\n{context}\n\n问题：{user_question}"}
    ]
    
    response = client.chat.completions.create(
        model="deepseek-v4-flash",
        messages=messages,
        max_tokens=2000
    )
    return response.choices[0].message.content

# 使用
docs = load_all_documents()  # 从数据库或文件系统加载
answer = simple_rag(docs, "请总结这份报告的主要发现")
```

这种方案虽然简单，但对于中小规模的文档库（几千篇以内）效果非常好。它避免了向量检索中常见的"检索不到相关文档"的问题。

## Agent 架构设计

### Agent 的核心组件

一个完整的 Agent 系统包含三个核心组件：

1. **LLM（大语言模型）**：负责理解用户意图、规划任务步骤、决定调用哪些工具
2. **Tools（工具集）**：可以被 LLM 调用的外部功能，比如搜索、计算、查询数据库
3. **Memory（记忆）**：存储上下文信息，让 Agent 在多轮对话中保持一致性

### DeepSeek 的 Tool Calls 支持

DeepSeek 的 API 原生支持 Tool Calls，格式完全兼容 OpenAI：

```python
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["DEEPSEEK_API_KEY"],
    base_url="https://api.deepseek.com"
)

# 定义可用工具
tools = [
    {
        "type": "function",
        "function": {
            "name": "search_web",
            "description": "搜索互联网获取最新信息",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索关键词"
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_time",
            "description": "获取当前时间",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "calculate",
            "description": "执行数学计算",
            "parameters": {
                "type": "object",
                "properties": {
                    "expression": {
                        "type": "string",
                        "description": "数学表达式"
                    }
                },
                "required": ["expression"]
            }
        }
    }
]

# 工具函数实现
def search_web(query):
    # 这里替换为实际的搜索 API
    return f"搜索 '{query}' 的结果: 找到了 15 条相关记录"

def get_current_time():
    from datetime import datetime
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def calculate(expression):
    try:
        return str(eval(expression))
    except:
        return f"无法计算: {expression}"

# 调用 Agent
def run_agent(user_input, max_iterations=5):
    messages = [
        {"role": "system", "content": "你是一个有能力的智能助手，可以使用工具来解决复杂问题。"},
        {"role": "user", "content": user_input}
    ]
    
    for _ in range(max_iterations):
        response = client.chat.completions.create(
            model="deepseek-v4-flash",
            messages=messages,
            tools=tools,
            tool_choice="auto"
        )
        
        message = response.choices[0].message
        
        # 检查是否要调用工具
        if message.tool_calls:
            for tool_call in message.tool_calls:
                # 添加工具调用信息
                messages.append({
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [tool_call]
                })
                
                # 执行工具
                function_name = tool_call["function"]["name"]
                function_args = json.loads(tool_call["function"]["arguments"])
                
                if function_name == "search_web":
                    result = search_web(function_args["query"])
                elif function_name == "get_current_time":
                    result = get_current_time()
                elif function_name == "calculate":
                    result = calculate(function_args["expression"])
                else:
                    result = "未知工具"
                
                # 添加工具结果
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call["id"],
                    "content": result
                })
        else:
            # 直接回答
            return message.content
    
    return "对话超过最大轮次限制"

# 测试
answer = run_agent("今天的日期是什么？帮我计算 3.14 * 100")
print(answer)
```

### 一个完整的 Agent 应用：智能知识库助手

下面是一个更完整的 Agent 应用示例，结合了 RAG 和工具调用：

```python
import json
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["DEEPSEEK_API_KEY"],
    base_url="https://api.deepseek.com"
)

# 可用的工具集
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": "在知识库中搜索相关信息",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索关键词"
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "返回结果数量",
                        "default": 3
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_article_detail",
            "description": "获取文章的详细内容",
            "parameters": {
                "type": "object",
                "properties": {
                    "article_id": {
                        "type": "string",
                        "description": "文章 ID"
                    }
                },
                "required": ["article_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "summarize_document",
            "description": "对长文档生成摘要",
            "parameters": {
                "type": "object",
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "文档内容"
                    },
                    "max_length": {
                        "type": "integer",
                        "description": "摘要最大长度",
                        "default": 500
                    }
                },
                "required": ["content"]
            }
        }
    }
]

# 工具实现
def search_knowledge_base(query, max_results=3):
    # 实际项目中这里接向量数据库
    print(f"[搜索知识库] query={query}, max_results={max_results}")
    return json.dumps([
        {"id": "1", "title": "DeepSeek V3 技术报告", "score": 0.95},
        {"id": "2", "title": "MoE 架构详解", "score": 0.87}
    ], ensure_ascii=False)

def get_article_detail(article_id):
    print(f"[获取文章详情] id={article_id}")
    return {"id": article_id, "content": "文章内容..."}

def summarize_document(content, max_length=500):
    # 调用 DeepSeek 生成摘要
    response = client.chat.completions.create(
        model="deepseek-v4-flash",
        messages=[
            {"role": "system", "content": f"请用不超过{max_length}字总结以下内容"},
            {"role": "user", "content": content}
        ],
        max_tokens=max_length * 2
    )
    return response.choices[0].message.content

def execute_tool(tool_name, tool_args):
    functions = {
        "search_knowledge_base": search_knowledge_base,
        "get_article_detail": get_article_detail,
        "summarize_document": summarize_document
    }
    return functions[tool_name](**tool_args)

# Agent 主循环
def knowledge_agent(user_input, max_iterations=5):
    messages = [
        {"role": "system", "content": "你是一个知识库智能助手。你可以搜索知识库、获取文章详情、生成摘要。"},
        {"role": "user", "content": user_input}
    ]
    
    conversation_log = []
    
    for iteration in range(max_iterations):
        conversation_log.append(f"--- 第 {iteration+1} 轮 ---")
        
        response = client.chat.completions.create(
            model="deepseek-v4-flash",
            messages=messages,
            tools=TOOLS,
            tool_choice="auto",
            enable_thinking=True  # 开启思考模式以做出更好的工具调用决策
        )
        
        message = response.choices[0].message
        
        # 如果有推理过程，记录到日志
        if hasattr(message, 'reasoning_content') and message.reasoning_content:
            conversation_log.append(f"  [思考] {message.reasoning_content[:200]}...")
        
        if message.tool_calls:
            for tool_call in message.tool_calls:
                function_name = tool_call["function"]["name"]
                function_args = json.loads(tool_call["function"]["arguments"])
                conversation_log.append(f"  [工具调用] {function_name}({json.dumps(function_args, ensure_ascii=False)})")
                
                # 执行工具
                result = execute_tool(function_name, function_args)
                conversation_log.append(f"  [工具结果] {result[:200]}...")
                
                messages.append({
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [tool_call]
                })
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call["id"],
                    "content": result
                })
        else:
            conversation_log.append(f"  [最终回答] {message.content}")
            messages.append({"role": "assistant", "content": message.content})
            return message.content, conversation_log
    
    return "对话超过最大轮次限制", conversation_log

# 使用示例
answer, log = knowledge_agent("DeepSeek V3 的架构是什么？帮我生成一个摘要")
for entry in log:
    print(entry)
```

## 架构决策：什么时候用 RAG，什么时候用 Agent

### 纯 RAG 适用场景

- 用户问题有明确的知识来源
- 不需要执行外部操作
- 答案可以从现有文档中找到
- 典型的 QA 系统、文档问答、知识库助手

### 纯 Agent 适用场景

- 需要调用外部 API 获取实时数据
- 需要执行多步骤操作
- 需要与多个系统交互
- 典型的自动化工作流、数据分析助手、操作型机器人

### RAG + Agent 结合

对于复杂场景，两者结合效果最好：

```
用户请求
    ↓
Agent 分析意图
    ↓
[需要知识?] → RAG 检索 → 知识注入上下文
[需要工具?] → 调用工具 → 工具结果注入上下文
    ↓
LLM 生成最终回答
```

## 性能与成本控制

RAG 和 Agent 系统的 token 消耗通常比普通对话大很多。一些优化建议：

### RAG 优化

1. **控制检索数量**：通常检索 3-5 个文档片段就足够了。过多的上下文反而会降低模型的回答质量。
2. **使用缓存**：相同系统提示词的缓存命中率可以显著降低输入成本。
3. **考虑文档预处理**：在检索前对文档做摘要或提取关键信息，减少发送给模型的 token 量。

### Agent 优化

1. **限制工具调用轮数**：设置合理的 `max_iterations`（通常 3-5 轮），防止 Agent 陷入无限循环。
2. **选择正确的工具**：工具越多，Agent 的选择成本越高。只暴露真正需要的工具。
3. **思考模式的权衡**：Agent 的思考模式有助于做出更好的工具调用决策，但会增加 2-3 倍的 token 消耗。对于简单任务，可以关闭思考模式。

## 实际项目的架构建议

如果你正在开发一个基于 DeepSeek 的 AI 应用，我的建议架构是：

```
前端层：Web UI / 移动端 / CLI
    ↓
API 网关层：路由、认证、限流
    ↓
Agent 编排层：意图分析、工具路由、上下文管理
    ↓
能力层：
  - DeepSeek API（LLM 核心）
  - 向量数据库（RAG 检索）
  - 工具服务（搜索、计算、API 调用等）
    ↓
数据存储层：文档库、对话历史、用户数据
```

关键设计原则：

- Agent 编排层是核心——它决定何时调用 LLM、何时检索、何时调用工具
- 用 V4-Flash 处理 80% 的请求，V4-Pro 处理 20% 的复杂请求
- 所有外部依赖（向量数据库、API 等）都应该有 fallback 策略
- 记录完整的对话日志，用于后续分析和调试

## 总结

DeepSeek 为 RAG 和 Agent 应用提供了非常好的基础：100 万 token 的上下文长度、原生 Tool Calls 支持、以及极具竞争力的定价。这三个条件的组合，让构建真正"有用"的 AI 应用在技术和成本上都变得可行。

但技术从来不是唯一的问题。我在这条系列文章中反复强调的一点是：真正的价值不在于你能调用多强的模型，而在于你能否构建一个系统——它能知道什么时候该用模型，什么时候该检索，什么时候该调用工具。

把 DeepSeek 作为一个组件，而不是一个产品，这才是它真正的价值所在。