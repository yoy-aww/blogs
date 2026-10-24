---
title: WorldTUI-Small：用 RTX 3060 训练一个能跑 bash 的小终端模型
date: 2026-10-25 14:00:00
type: tech
permalink: /2026/10/25/worldtui-small-qlora-bash-terminal-training/
tags:
  - 模型训练
  - QLoRA
  - Terminal
  - Agent
  - 小模型
categories:
  - 技术思考
description: 基于 WorldTUI 思路，用 RTX 3060 12GB 训练一个能执行 bash 基础命令的小终端模型。从数据合成、预处理到 QLoRA 微调的完整流程与关键决策。
---

## 先说结论

让一个小模型学会"用终端"这件事，不需要 billion 级别参数。**150-200M token 的数据、QLoRA 4-bit 量化、RTX 3060 单卡**，就能训练出一个能在多轮交互中记住路径变化、执行基础 bash 命令的"终端工具模型"。

这不是通用 Agent——它是给 LLM Agent 当手脚用的专用工具，目标是：**Agent 说"跑一下这条命令"，模型能给出符合预期的终端输出**。

---

## 为什么做这件事

现代 LLM Agent 框架（Hermes、Claude Code 等）已经能调用工具，但调用的是**预置好的函数**——比如 `web_search`、`code_interpreter`。它们不会真正"进入一个终端环境"去执行任意命令序列。

如果有一个小模型能模拟终端行为，就能让 Agent 在复杂场景中执行**多步命令链**：先 cd 到某个目录，再检查文件，再运行脚本——而不是每次都调用独立 API。

原版 [WorldTUI](https://github.com/simon-edufin/worldtui)（Simon Edufinsson 2026）做了大约 2B token 的训练，覆盖 bash、vim、tmux、Python REPL 甚至 snake 游戏。但那需要 75 GPU-h（RTX 4090），对消费级硬件不友好。

我的目标很具体：**只做 bash 基础命令，目标显存 12GB，训练时间 24-48h**。

---

## 关键设计决策

### 1. 为什么选 QLoRA 而不是全参数训练

RTX 3060 12GB 装不下一个 360M 参数模型的全精度训练。

全精度训练需要的显存大致是：
- 模型权重：4 bytes × 360M ≈ 1.4 GB
- 梯度：同样 1.4 GB
- 优化器状态（Adam）：2 × 1.4 GB ≈ 2.8 GB
- 激活值：视 batch size 而定，约 2-4 GB

总计远超 12GB。

**QLoRA 的做法**：把基础模型权重 quantize 到 4-bit，只训练低秩适配器（LoRA r=16）。显存需求从 ~8GB 降到 ~6GB，训练速度几乎不变。对于 360M 这样的小模型，LoRA r=16 几乎不影响最终能力。

### 2. 为什么只选 bash 基础命令

原版 WorldTUI 覆盖 vim、tmux、Python REPL——这些每个都是"显存和时间的黑洞"。

bash 基础命令（约 15 个核心命令）足够覆盖 Agent 日常需求：
- 导航：`pwd`、`ls`、`cd`
- 查看：`cat`、`head`、`tail`、`wc`
- 操作：`mkdir`、`rm`、`touch`、`echo >`、`cp`、`mv`
- 搜索：`find`
- 系统信息：`whoami`、`date`、`uname`、`env`

**150-200M token 就能学扎实**，而不是像原版那样需要 2B token。

### 3. 训练目标是什么

不是做一个完整的终端模拟器（那需要捕捉光标位置、ANSI 颜色、滚动缓冲等），而是做一个**状态保持的命令执行器**：

- 记住 `cd` 后的工作目录变化
- 记住 `echo hello > file.txt` 后文件内容
- 在多轮交互中保持一致性

给下游 Agent 用的时候，Agent 只需要把模型输出当作"终端回显"来解析，不需要解析 ANSI 转义序列或光标坐标。

---

## 数据生成：伪终端模拟

数据是项目里最核心的部分。不能用真实终端（Docker 容器启动+初始化每个 session 要 10-30 秒），所以做了**伪终端仿真器**：

```python
@dataclass
class Terminal:
    rows: int = 24
    cols: int = 80
    grid: list[str] = field(default_factory=list)
    cursor_row: int = 0
    cursor_col: int = 0
```

核心逻辑：
1. 为每个 session 创建一个临时工作目录，预置不同 persona（developer、sysadmin、student）的文件结构
2. 从命令模板库中随机采样 8-20 条命令，填充变量（文件名、目录名等）
3. 用 `subprocess.run` 调用真实 bash 执行命令，记录 stdout/stderr
4. 维护一个 24×80 的字符网格，逐字符渲染输入和输出
5. 跟踪 `cd` 后的工作目录变化

输出格式是 JSONL，每行一个 session，包含初始屏幕快照和每个 event 的 input/output/screen_after。

**这一步的关键洞察**：不需要模拟完整的终端行为（比如 ANSI 颜色、光标移动），只需要输出"命令执行后的屏幕内容"。训练目标是从"初始屏幕 + 命令"预测"结果屏幕"。

---

## 预处理：从 JSONL 到 HF Datasets

`tokenize.py` 把 JSONL session 转成 HuggingFace Trainer 能直接使用的格式：

```
SCREEN_SIZE rows=24 cols=80
SCREEN_START
user@host:~$ █
SCREEN_END
INPUT_START
ls
INPUT_END
OUTPUT_START
main.py  utils.py  README.md
SCREEN_UPDATE
user@host:~$ main.py
           █
SCREEN_END
```

每个 event 变成 `INPUT_START → INPUT_END → OUTPUT_START → SCREEN_UPDATE → SCREEN_END` 的结构。

训练目标：给定 prompt（初始屏幕状态）+ 输入序列，模型需要预测完整的输出序列（包括命令输出和新的屏幕状态）。

使用 Qwen2.5-Coder-0.5B 的 tokenizer，max_length=1024，padding=True。

---

## 训练配置（预期）

```bash
python train.py \
  --data data/tokenized/ \
  --output checkpoints/qwen2.5-coder-0.5b-qlora \
  --model_name Qwen/Qwen2.5-Coder-0.5B-Instruct \
  --lora_r 16 \
  --lora_alpha 32 \
  --epochs 2 \
  --batch_size 4 \
  --lr 2e-4
```

- 基础模型：Qwen2.5-Coder-0.5B-Instruct（360M 参数，专为代码/指令优化）
- 量化：4-bit NF4（bitsandbytes）
- LoRA：r=16, alpha=32, target_modules=["q_proj", "v_proj"]
- 预计训练时间：12-24 小时（RTX 3060 12GB）

---

## 评测方案

训练完成后，用三个维度评估：

**1. ShellBench（自定义版）**
24 条 bash 命令测试，检查模型输出是否与真实 bash 执行结果匹配。包括：
- 单条命令：`ls`、`pwd`、`echo hello > test.txt`
- 组合命令：`cd src && ls`、`find . -name "*.py" | head -5`
- 错误处理：输入无效命令，检查是否返回合理错误信息

**2. Memory Test**
验证多轮交互中的状态保持能力：
```
→ echo "hello world" > msg.txt
→ cat msg.txt
→ cd ..
→ cat msg.txt  ← 应该仍然能读到内容
```

**3. Typo Test**
故意输入错误命令名（如 `lsi`、`cm`），检查模型是否能：
- 给出"command not found"类错误
- 或者尝试纠错并给出合理建议

---

## 为什么这是一个值得写的课题

这个项目的价值不在于"又一个训练小模型的实验"，而在于它回答了 Agent 工具系统的一个具体设计问题：

**当 Agent 需要"动手"时，是直接调 API 好，还是让一个小模型模拟终端好？**

前者精准但有限——只能调用预定义的函数；后者灵活但不可控——模型可能输出乱码或错误命令。

QLoRA 训练的终端模型处在两者之间：它保留了命令执行的灵活性（任何 bash 命令都能处理），同时通过训练数据控制了输出的规范性。

更广泛地说，这个项目展示了**消费级 GPU 也能做有意义的模型微调**——不需要 8×A100，不需要亿级 token，一个合理的选题 + 精简的数据 pipeline + QLoRA，就够了。

---

## 下一步

目前完成了数据生成和预处理脚本，训练脚本和评测脚本待实现。下一步计划：

1. 完成 `train.py` 的 QLoRA 微调流程
2. 生成 50k episodes 的训练数据
3. 跑通第一轮训练，记录 loss 曲线和显存占用
4. 实现 `chat.py` 交互式测试接口
5. 在 ShellBench 上跑 baseline 评测

如果一切顺利，预计 3-5 天内完成首轮训练，得到第一个可用 checkpoint。
