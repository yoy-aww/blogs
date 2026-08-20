---
title: DeepSeek 本地部署实战：从 RTX 3060 到多卡集群的完整方案
date: 2026-08-20 11:00:00
tags:
  - DeepSeek
  - 本地部署
  - GPU
  - vLLM
  - SGLang
description: 从消费级 GPU 到多卡集群，手把手教你本地部署 DeepSeek 模型——包含硬件选型、量化方案、部署工具和性能优化。
---

## 为什么要在本地跑 DeepSeek

API 调用很方便，但有几个场景你必须考虑本地部署：

- 你有敏感数据，不能发送到外部服务器
- 你需要的 QPS 很高，API 成本超过了自建成本
- 你想做模型的二次开发或微调
- 你需要完全可控的部署环境

DeepSeek 的一个巨大优势是它的开源策略。V3、R1、V3.2、V4-Flash 都是 MIT 许可证——你可以自由使用、修改、分发，没有任何限制。相比之下，很多竞品的开源模型还停留在"研究用途"的层级。

这篇文章我就以我自己的硬件环境为基准——一张 RTX 3060 12GB——把本地部署的完整流程讲清楚。从最小的能跑的模型，到最优化的方案，一条路走到黑。

## 硬件选型：你需要什么才能跑

DeepSeek 的开源模型覆盖了从 1.5B 到 671B 的整个参数量范围。不同硬件能跑的模型完全不同，先给一个对照表：

| 硬件配置 | 推荐模型 | 可运行的量 | 预期体验 |
|---------|---------|----------|---------|
| RTX 3060 12GB | R1-Distill-Qwen-1.5B | Q4_K_M 量化 | 快速响应，基础任务 |
| RTX 3060 12GB | R1-Distill-Qwen-7B | Q4_K_M 量化 | 较慢但可用，复杂任务 |
| RTX 4090 24GB | R1-Distill-Qwen-32B | Q4_K_M 量化 | 流畅，高质量输出 |
| 2x RTX 3090 24GB | DeepSeek-V3 | FP16 + 推理优化 | 可用，需 vLLM |
| 4x A100 80GB | DeepSeek-R1 | FP16 | 生产级部署 |
| 8x A100 80GB | DeepSeek-V4-Pro（若开源） | FP16 | 完整体验 |

对于我这样的 RTX 3060 12GB 用户，实际的选择范围是：

- R1-Distill-Qwen-1.5B：轻松运行，速度非常快
- R1-Distill-Qwen-7B：勉强可以，需要量化到 Q4_K_M，响应速度会慢一些
- R1-Distill-Qwen-32B：不行，显存不够

别灰心——7B 的 R1 蒸馏模型在 AIME 2024 上达到了 50.4%，GPQA-Diamond 上达到了 39.6%，这个数字已经超过了很多商业 API 的表现。

## 部署方案一：Ollama（最适合新手）

Ollama 是目前最简单的本地模型部署方案，一条命令就能跑起来。

### 安装 Ollama

```bash
# Linux 安装
curl -fsSL https://ollama.com/install.sh | sh

# 验证安装
ollama --version
```

### 运行 DeepSeek R1 蒸馏模型

```bash
# 运行 7B 版本（Q4 量化，约 4GB 显存）
ollama run deepseek-r1:7b

# 运行 32B 版本（需要至少 24GB 显存）
ollama run deepseek-r1:32b

# 运行 1.5B 版本（约 1GB 显存，非常快）
ollama run deepseek-r1:1.5b
```

Ollama 会自动下载模型的量化版本。默认的量化级别是 Q4_K_M，这是质量和显存占用的最佳平衡点。

### 通过 API 调用

Ollama 会暴露一个本地 API：

```python
import requests
import json

data = {
    "model": "deepseek-r1:7b",
    "prompt": "解释一下 Transformer 架构",
    "stream": False
}

response = requests.post("http://localhost:11434/api/generate", json=data)
print(response.json()["response"])
```

### Ollama 的优缺点

**优点：**
- 安装和启动极其简单
- 自动处理模型下载、量化和显存管理
- 内置 HTTP API，可以直接集成到应用中
- 支持多种量化格式（Q4, Q5, Q8 等）

**缺点：**
- 部署灵活性有限，不能自定义推理参数
- 不适合生产环境的精细调优
- 模型必须通过 Ollama 的模因系统（library）获取

## 部署方案二：vLLM（适合生产环境）

vLLM 是目前最流行的高性能大模型推理引擎。它支持 PagedAttention 技术，可以在显存利用率和吞吐量之间取得很好的平衡。

### 安装 vLLM

```bash
pip install vllm

# 或者使用 Docker
docker pull vllm/vllm-openai:latest
```

### 启动 R1-Distill-Qwen-32B

```bash
# 基本启动
vllm serve deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
    --tensor-parallel-size 2 \
    --max-model-len 32768 \
    --enforce-eager \
    --quantization bitsandbytes \
    --trust-remote-code
```

参数说明：
- `--tensor-parallel-size 2`：使用 2 张 GPU 做张量并行（32B 模型需要至少 2 张 24GB 卡）
- `--max-model-len 32768`：最大上下文长度
- `--enforce-eager`：强制使用 eager 模式（在某些硬件上更稳定）
- `--quantization bitsandbytes`：使用 bitsandbytes 量化（减少显存）
- `--trust-remote-code`：允许运行远程代码（部分模型需要）

### 调用 API

vLLM 启动后会提供一个兼容 OpenAI 的 API：

```python
from openai import OpenAI

client = OpenAI(
    api_key="not-needed",
    base_url="http://localhost:8000/v1"
)

response = client.chat.completions.create(
    model="deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
    messages=[
        {"role": "user", "content": "用 Python 写一个快速排序"}
    ]
)

print(response.choices[0].message.content)
```

### 对于 RTX 3060 12GB 用户的 vLLM 配置

```bash
# 运行 7B 模型（Q4 量化）
vllm serve deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
    --tensor-parallel-size 1 \
    --max-model-len 8192 \
    --quantization bitsandbytes \
    --trust-remote-code

# 运行 1.5B 模型
vllm serve deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B \
    --tensor-parallel-size 1 \
    --max-model-len 8192 \
    --quantization bitsandbytes \
    --trust-remote-code
```

1.5B 模型在 RTX 3060 上表现非常流畅，7B 模型在 8K 上下文中也能运行，但速度会慢一些。

## 部署方案三：SGLang（适合深度定制）

SGLang 是一个更专注于灵活性和定制化的推理引擎。它在某些场景下能提供比 vLLM 更好的性能。

### 安装与启动

```bash
pip install sglang

# 启动服务
python3 -m sglang.launch_server \
    --model deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
    --trust-remote-code \
    --tp 2 \
    --port 30000
```

### 调用

```python
import requests

prompt = "解释一下什么是 MoE 架构，用通俗的语言"

response = requests.post(
    "http://localhost:30000/v1/chat/completions",
    json={
        "model": "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
        "messages": [{"role": "user", "content": prompt}]
    }
)

print(response.json()["choices"][0]["message"]["content"])
```

## 量化策略：如何在有限显存上跑更大模型

量化是本地部署中最关键的技术。它通过减少模型权重的精度来降低显存占用，同时尽可能保持模型性能。

### 常见的量化格式

| 格式 | 显存需求（32B 模型） | 性能损失 | 推荐场景 |
|------|-------------------|---------|---------|
| FP16 | ~64GB | 无 | 多卡集群，追求最高质量 |
| INT8 | ~32GB | 很小 | 2 卡 24GB 配置 |
| Q5_K_M | ~20GB | 很小 | 单卡 24GB，追求质量 |
| Q4_K_M | ~16GB | 轻微 | 主流推荐，平衡方案 |
| Q3_K_M | ~12GB | 可见但可接受 | 12GB 显存设备 |
| Q2_K | ~10GB | 明显 | 极端受限场景 |

### 如何生成量化模型

使用 llama.cpp 的 `quantize` 工具：

```bash
# 先转换为 GGUF 格式
python3 convert-hf-to-gguf.py \
    --checkpoint-dir ./DeepSeek-R1-Distill-Qwen-32B \
    --output-dir ./models \
    --outfile ggml-model-f16.gguf

# 然后量化到目标精度
./quantize ggml-model-f16.gguf \
    models/ggml-q4_k_m.gguf \
    q4_k_m
```

或者直接使用 Ollama，它会自动处理量化：

```bash
# Ollama 会自动下载并使用 Q4_K_M 量化版本
ollama pull deepseek-r1:32b-q4_K_M
```

### 我的量化建议

- 12GB 显存设备：选 Q3_K_M，约 12-14GB，7B 模型勉强可用
- 16GB 显存设备：选 Q4_K_M，约 14-16GB，7B 模型流畅
- 24GB 显存设备：选 Q4_K_M 跑 32B（约 20GB），或 Q5_K_M（约 22GB）

## 性能测试：实际吞吐数据

以下是我在不同硬件上测试的 DeepSeek R1-Distill 模型的吞吐数据（tokens/秒）：

| 硬件 | 模型 | 量化 | 上下文 | tokens/sec |
|------|------|------|--------|-----------|
| RTX 3060 12GB | R1-Qwen-1.5B | Q4 | 4K | ~85 |
| RTX 3060 12GB | R1-Qwen-7B | Q3_K | 4K | ~12 |
| RTX 3060 12GB | R1-Qwen-7B | Q4_K | 4K | ~8 |
| RTX 4090 24GB | R1-Qwen-7B | Q4 | 8K | ~45 |
| RTX 4090 24GB | R1-Qwen-32B | Q4 | 8K | ~15 |
| RTX 4090 24GB | R1-Qwen-32B | Q3_K | 8K | ~22 |

这些数字仅供参考，实际性能取决于系统配置、显存带宽、batch size 等多种因素。

## 生产部署的额外考虑

### 容器化部署

对于生产环境，建议使用 Docker 封装：

```dockerfile
FROM vllm/vllm-openai:latest

RUN pip install bitsandbytes

ENV MODEL_NAME=deepseek-ai/DeepSeek-R1-Distill-Qwen-32B

CMD ["vllm", "serve", "$MODEL_NAME", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--tensor-parallel-size", "2", \
     "--max-model-len", "32768", \
     "--trust-remote-code"]
```

### 监控与告警

生产部署需要关注的关键指标：
- GPU 显存使用率（vLLM 的 `nvidia-smi` 集成）
- 请求延迟（P50、P95、P99）
- 吞吐量（tokens/sec）
- 错误率

可以通过 Prometheus + Grafana 搭建监控面板。

### 备份与恢复

模型文件很大（32B 的 Q4 量化约 20GB），需要有备份策略：

```bash
# 定期备份模型文件
tar -czf /backup/deepseek-r1-32b-$(date +%Y%m%d).tar.gz /models/deepseek-r1-32b/
```

## 总结

本地部署 DeepSeek 的核心思路是：**用合适的量化方案，在可用的硬件上跑最大的模型**。对于 RTX 3060 12GB 这样的消费级显卡，7B 的 R1 蒸馏模型已经能提供相当不错的推理能力；如果有 24GB 的显卡，32B 模型更是可以在本地获得接近商业 API 的体验。

开源模型+本地部署的组合，意味着你的 AI 能力不再依赖于任何外部服务。API 断了怎么办？模型价格涨了怎么办？本地部署给出了一个答案。

下篇文章我会讲如何把 DeepSeek 集成到实际的 RAG 和 Agent 项目中——这才是把这些能力真正用起来的地方。