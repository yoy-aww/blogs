---
title: MCP：把 LLM 接外部工具做成一个协议
date: 2026-10-19 15:00:00
type: tech
permalink: /2026/10/19/mcp-model-context-protocol/
tags:
  - MCP
  - 协议
  - LLM
  - 工具生态
categories:
  - 技术思考
description: MCP 是 Anthropic 2024 年底开源的协议，把"LLM 怎么连外部工具/数据源"标准化了。类比 USB-C 之于硬件——讲清楚结构、传输层、Server 怎么写，以及和 Tool Calling、Skill 的关系。
---

## 先说结论

MCP（Model Context Protocol）是 Anthropic 2024 年 11 月开源的一个**协议**，目标是把"LLM 怎么连外部工具和数据源"标准化。

为什么需要它？因为之前每个 Agent 框架都有自己的工具接口：LangChain 用 `BaseTool`，LlamaIndex 用 `FunctionAgent`，自研 Agent 自己定义 JSON Schema。工具写得再多，换一个框架就得重写一遍适配层——和早期"每个硬件厂商自己定义 USB 接口"是同一个问题。

MCP 就是给 LLM 应用做"USB-C 标准化"：把工具封装成**MCP Server**（独立进程），任何 MCP Client（嵌在 LLM 应用里）都能发现并调用，跨框架、跨语言、跨进程。

这篇文章讲清楚 MCP 的结构、传输层、Server 实现，以及它和 Tool Calling、Skill 的关系。

## 为什么需要 MCP

### 工具的"接口碎片化"问题

回到 2024 年之前，你想给 LLM 应用加个"查数据库"的能力：

```python
# 自研 Agent：直接定义 function
def search_db(query):
    return db.execute(query).fetchall()

tools = [{"name": "search_db", "description": "...", "schema": {...}}]
```

迁到 LangChain，要改成：

```python
# LangChain：BaseTool 抽象
class SearchDBTool(BaseTool):
    name = "search_db"
    def _run(self, query):
        return db.execute(query).fetchall()
```

迁到 LlamaIndex，又要改：

```python
# LlamaIndex：FunctionAgent 接口
@dataclass
class SearchDB:
    def __call__(self, query):
        return db.execute(query).fetchall()
```

**同一个工具，写三遍**。工具多了以后这种适配成本指数级增长。

### MCP 的解决方案

把工具封装成**MCP Server**——一个独立进程，对外暴露标准协议：

```
[你的工具：数据库 / 文件系统 / API / 浏览器]
            ↓ 包装成
        [MCP Server]  ← 标准协议：tools / resources / prompts
            ↓ 被任何 MCP Client 调用
[LLM 应用：Claude / Cursor / 自研 Agent / ...]
```

工具作者只写一次 MCP Server，所有 MCP Client（VS Code、Claude Desktop、自研 Agent）都能直接用上。

## MCP 的核心结构

### 三方角色

```
┌──────────────────────┐
│    MCP Host          │  用户界面（Claude Desktop / Cursor / 自研）
│    ┌────────────┐    │
│    │ MCP Client │ ←──┼── 嵌入 Host，负责和 Server 通信
│    └────────────┘    │
└──────────┬───────────┘
           │
   stdio 或 HTTP+SSE
           │
┌──────────┴───────────┐
│    MCP Server        │  独立进程，提供能力
│   ┌─────────────┐    │
│   │ Tools       │    │  可调用的函数
│   │ Resources   │    │  可读的数据
│   │ Prompts     │    │  可触发的提示模板
│   └─────────────┘    │
└──────────────────────┘
```

**Host**：宿主应用，比如 Claude Desktop、Cursor、自研 Agent 应用。负责 UI 和用户体验。

**Client**：嵌在 Host 里的 MCP 客户端，负责发现 Server、调用工具、传递上下文。一个 Host 里可以有多个 Client（每个连一个 Server）。

**Server**：独立进程，提供工具能力。可以是本地进程（stdio），也可以是远程服务（HTTP+SSE）。

### 三类能力

MCP 协议定义了 Server 提供的三类能力：

| 类型 | 用途 | 例子 |
|---|---|---|
| **Tools** | LLM 主动调用的函数 | 搜索数据库、发邮件、调 API |
| **Resources** | 上下文数据（被动读取） | 文件系统、数据库表、配置 |
| **Prompts** | 预定义提示模板 | 代码审查模板、报告生成模板 |

- **Tools** 是动态的，LLM 决定什么时候调用
- **Resources** 是静态的，Host/Client 主动读取并放入上下文
- **Prompts** 是模板，用户或 LLM 触发

### 通信协议

MCP 基于 **JSON-RPC 2.0**，消息格式：

```json
// 客户端请求
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {"city": "北京"}
  }
}

// 服务端响应
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [{"type": "text", "text": "{\"temperature\": 22, \"condition\": \"晴\"}"}]
  }
}
```

## 传输层：stdio 还是 HTTP+SSE

MCP 支持两种传输方式：

### stdio（标准输入输出）

Server 是一个本地进程，Client 通过 stdin/stdout 通信。

**适合**：本地工具、单机场景、文件系统操作。

```python
# Client 启动 Server 进程
server_process = subprocess.Popen(
    ["node", "my-server.js"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
)
# 通信走 stdin/stdout 的 JSON-RPC
```

**优势**：简单、无需配置、本地工具天然适配。

### HTTP + SSE

Server 是一个 HTTP 服务，Client 通过 HTTP 请求 + SSE 流式接收响应。

**适合**：远程工具、需要认证的场景、多客户端共享。

```http
POST /mcp HTTP/1.1
Content-Type: application/json

{ "jsonrpc": "2.0", "method": "tools/call", "params": {...} }
```

**优势**：跨机器、支持认证（OAuth 2.1）、多客户端并发。

**怎么选**：本地工具用 stdio（绝大多数场景），共享服务用 HTTP+SSE。

## 实现一个 MCP Server

用 Python SDK（`mcp` 包）写一个最简单可用的 Server：

```python
# my_server.py
from mcp.server import Server
from mcp.server.stdio import stdio_server
import json

app = Server("demo-server")

# 声明工具
@app.list_tools()
async def list_tools():
    return [
        {
            "name": "get_weather",
            "description": "查询指定城市的实时天气",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "city": {"type": "string", "description": "城市名"}
                },
                "required": ["city"],
            },
        },
        {
            "name": "calculate",
            "description": "计算数学表达式",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "expression": {"type": "string"}
                },
                "required": ["expression"],
            },
        },
    ]

# 处理工具调用
@app.call_tool()
async def call_tool(name: str, arguments: dict):
    if name == "get_weather":
        city = arguments["city"]
        # 实际项目里调外部 API
        result = {"city": city, "temperature": 22, "condition": "晴"}
    elif name == "calculate":
        try:
            result = str(eval(arguments["expression"]))
        except Exception as e:
            result = f"错误: {e}"
    else:
        result = "未知工具"
    
    return [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}]

# 启动
async def main():
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

### 配置到 Claude Desktop

在 `claude_desktop_config.json` 里加：

```json
{
  "mcpServers": {
    "demo": {
      "command": "python",
      "args": ["C:/path/to/my_server.py"],
      "env": {}
    }
  }
}
```

重启 Claude Desktop，工具就出现了。

## MCP 和 Tool Calling 的关系

**Tool Calling 是 LLM 的能力，MCP 是工具的标准协议**。两者是不同层次的东西：

```
[LLM 模型层]  Tool Calling：让 LLM 能输出结构化调用请求
            ↓
[Agent 框架层] LangChain / LlamaIndex / 自研 Agent：消费 Tool Calling
            ↓
[工具接口层]  Tool Schema / MCP Server：工具的标准接口
            ↓
[工具实现层]  实际的代码、API、数据库
```

**Tool Calling** 是模型层面的能力——OpenAI、Anthropic、DeepSeek、Qwen 都支持。无论模型支不支持 MCP，你都可以用 Tool Calling 调任何工具，前提是工具以 LLM 期望的 JSON Schema 形式暴露。

**MCP** 是工具层面的标准——把"工具怎么暴露给 Agent"标准化。一个工具可以是"原生 MCP Server"，也可以是"被 MCP 适配层包装的旧工具"。

**一句话**：Tool Calling 是 LLM 的"手"，MCP 是工具的"USB 接口"。两者搭配才能形成一个完整的"手能握到工具"的链路。

## MCP 和 Skill 的关系

**MCP 和 Skill 是不同层次的东西，但都服务于 Agent 的"能力扩展"**：

| 维度 | MCP | Skill |
|---|---|---|
| 是什么 | 协议（怎么连工具） | 知识单元（怎么做某类任务） |
| 单位 | Server（进程） | 文件（Markdown） |
| 加载时机 | Agent 启动时连接 | 触发条件匹配时加载 |
| 内容 | 函数/资源/提示模板 | 步骤、流程、最佳实践 |
| 类比 | USB-C 接口 | 操作手册 |

**MCP 解决"能力接入"问题**——让工具能被 Agent 调用。

**Skill 解决"方法沉淀"问题**——告诉 Agent 拿到能力之后怎么用。

**两者互补**：一个完整的 Agent 系统同时需要 MCP（连接能力）和 Skill（沉淀方法）。

## 实战：常见 MCP Server 生态

MCP 推出一年，生态已经比较丰富。一些常见的官方/社区 Server：

| Server | 能力 | 部署 |
|---|---|---|
| `@modelcontextprotocol/server-filesystem` | 文件系统访问 | 本地 |
| `@modelcontextprotocol/server-postgres` | PostgreSQL 查询 | 本地 |
| `@modelcontextprotocol/server-github` | GitHub 操作 | 本地 |
| `@modelcontextprotocol/server-puppeteer` | 浏览器自动化 | 本地 |
| `@modelcontextprotocol/server-brave-search` | Brave 搜索 | 远程 |
| `@modelcontextprotocol/server-memory` | 知识图谱记忆 | 本地 |

### 自托管一个 MCP Server

```bash
# 安装一个社区 Server（以文件系统为例）
npx -y @modelcontextprotocol/server-filesystem /path/to/files

# 或者用 npx 启动远程 Server
npx -y @modelcontextprotocol/server-postgres postgresql://user:pass@host/db
```

### 多 Server 配置

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/my/data"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {"GITHUB_TOKEN": "ghp_xxx"}
    },
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {"BRAVE_API_KEY": "..."}
    }
  }
}
```

一个 Host 可以连多个 MCP Server，每个提供不同能力。Agent 启动时把所有 Server 的工具汇总，形成一个完整的"工具池"。

## 工程实践要点

### 1. 工具粒度要适中

一个 MCP Server 不要塞几十个工具，也不要一个工具分几十个 Server。常见经验：一个 Server 围绕一个领域（文件系统、GitHub、数据库），工具数 5-20 个。

### 2. 工具的 description 仍然是关键

LLM 决定调不调用工具，主要看 description。MCP 工具的 description 写法跟 Tool Calling 一样——动词开头、说明做什么、说明返回什么。

### 3. 错误处理要清晰

工具失败时返回结构化错误，让 LLM 能"读到"错误并决定下一步：

```python
return [{"type": "text", "text": json.dumps({"error": "数据库连接失败", "detail": "..."})}]
```

不要让工具抛异常——异常会让整个 MCP Server 崩掉。

### 4. 大结果要截断

工具返回的数据可能很大（一张表 1000 行），全塞进 LLM 上下文会爆掉。Server 端要主动截断或摘要：

```python
if len(results) > 50:
    results = results[:50]
    note = f"[结果已截断，原始 {total} 条，返回前 50 条]"
```

### 5. 远程 Server 要加认证

stdio 是本地信任的，HTTP+SSE 的远程 Server 必须加认证（OAuth 2.1 是 MCP 推荐方案）。别裸奔。

### 6. 工具幂等性

LLM 可能因为不确定而重复调用同一个工具。工具要设计成幂等的——多次调用结果一致。

### 7. 工具超时

工具执行时间要有上限。LLM 等一个慢工具 30 秒，整个 Agent 体验就崩了。Server 端要主动设置 timeout。

## 常见坑

**坑 1：把 MCP 当成"Tool Calling 的替代品"**

MCP 不是 LLM 能力，是工具接口标准。它解决的是"工具怎么被 Agent 调用"，不替代 LLM 的 Tool Calling 能力。

**坑 2：每个工具都做成一个 Server**

工具数量爆炸 = Server 数量爆炸 = 启动慢、管理难。Server 要按领域聚合，别按工具拆。

**坑 3：忽略工具的 description**

MCP 工具列表会自动暴露给 LLM，但 LLM 选不选你的工具，看 description。写得模糊 = 工具白做。

**坑 4：工具返回巨大结果**

一张大表全塞进 LLM 上下文，10K token 一下没了。Server 端要主动截断、分页、摘要。

**坑 5：远程 Server 不认证**

HTTP+SSE 的远程 Server 不加认证，任何人都能调你的工具。OAuth 2.1 是 MCP 推荐方案，别偷懒。

**坑 6：把 MCP 和 Skill 混为一谈**

MCP 是协议，Skill 是知识单元。两者层次不同，解决不同问题。MCP 让 Agent "能做"，Skill 让 Agent "知道怎么做"。

## MCP 的争议和现状

MCP 一年不到，争议也不少：

**争议一**：是不是过度设计？

有人认为 Tool Calling + JSON Schema 已经够用，再加一层 MCP 是 over-engineering。反驳是：工具规模超过 5 个之后，每个框架自己定义接口的成本太高，标准化收益明显。

**争议二**：Anthropic 主导，会不会被绑架？

MCP 是开源协议（Apache 2.0），归 Anthropic 维护，但 OpenAI 在 2025 年初宣布也支持 MCP，Google 跟进。事实上的"行业标准"已经形成。

**争议三**：本地 stdio 适合所有场景吗？

远程工具越来越多（团队共享、云服务等），HTTP+SSE 是趋势。但 OAuth 认证、Server 部署、版本管理这些复杂度还没完全解决。

## 一句话总结

MCP 的本质是给 LLM 应用做"USB-C 标准化"——把工具从每个 Agent 框架的私有接口抽出来，做成一个统一的协议。Host / Client / Server 三方结构，tools / resources / prompts 三类能力，stdio / HTTP+SSE 两种传输，覆盖 90% 的工具接入场景。它不替代 Tool Calling（LLM 能力），也不替代 Skill（方法沉淀），而是和它们一起组成现代 Agent 的"工具栈"。先把你的工具包装成一个 MCP Server，下游所有支持 MCP 的客户端都能直接用上——这是 2025 年工具生态的事实标准。
