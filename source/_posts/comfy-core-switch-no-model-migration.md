---
title: 换掉 ComfyUI 客户端不用重下 170G 模型：Desktop 的模型根本不在安装目录
date: 2026-11-27 09:30:00
type: tech
permalink: /2026/11/27/comfy-core-switch-no-model-migration/
tags:
  - ComfyUI
  - 模型管理
---

## 一句话结论

Comfy Desktop 把你的模型存在一个**共享目录**（`ComfyUI-Shared\models`），跟安装目录是分开的。所以当你不想再用它那个**闭源、要充积分**的 Comfy Agent 时，直接克隆开源核心版，用一行 `extra_model_paths.yaml` 指向那个共享目录，**170GB 的 MiniMax H3 模型零迁移、零重下**。全程没动过模型，也没花一分钱积分。

## 起因：那个「额度不足」弹窗

我机器上 Comfy Desktop 的侧边栏 Agent（聊天窗口）弹出「额度不足」。查了一圈，这个 Agent 背后是 Comfy 自己选的大模型，走 **Comfy 积分**计费。我本来想给它换成商汤的免费模型，结果发现官方根本没给这个口子：

- Comfy Cloud 定价页原文：「Model — Comfy picks the model for you. **Bringing your own LLM key is not supported yet.**」
- 官方文档 in-app-agent 页：「Comfy Agent is generally available in **Comfy Cloud**. Local support for **Comfy Desktop is coming soon**」

两条都来自官方。结论：**Comfy Agent 是闭源的云端服务功能，不是开源核心的一部分**——它的 LLM 调用是云端在收费，你改不了。

## 那 ComfyUI 到底开不开源？

分两层，这是关键认知：

- **核心引擎**（`Comfy-Org/ComfyUI`）→ **GPL-3.0 开源**，`git clone` 就能跑，无账户无积分。
- **Comfy Agent / Comfy Cloud** → **闭源服务**，积分计费，就是那个额度弹窗的来源。

所以「换版本」不是换内核，是**甩掉闭源服务那一层**。但你第一反应肯定是：那我本地那堆模型会不会没？

## 模型在哪？这是最反直觉的一点

我先把两个地方都看了，结论很干脆：

**安装目录里的 models 全是空的。**

```
C:\Users\aww\AppData\Local\Comfy-Desktop\ComfyUI-Installs\MiniMax\ComfyUI\models\
  vae/ 0     text_encoders/ 0     loras/ 0     checkpoints/ 0     diffusion_models/ 0
```

真正的模型在**共享目录**：

```
C:\Users\aww\AppData\Local\Comfy-Desktop\ComfyUI-Shared\models\
  diffusion_models/  59G
  text_encoders/     38G
  LLM/               24G
  checkpoints/       22G
  clip_vision/       6.6G
  ...
```

`Comfy Desktop` 的配置文件 `shared_model_paths.yaml` 写得很明白（它是自动生成的）：

```yaml
comfy.desktop_0:
  base_path: 'C:\Users\aww\AppData\Local\Comfy-Desktop\ComfyUI-Shared\models'
  is_default: true
```

我的 MiniMax H3 全套约 **170GB** 都在这个共享目录里：两个主模型（FL2VA / REF2VA，各约 20GB）、两个 LoRA、Qwen3-VL 文本编码器、音频 VAE、视频 VAE。**Desktop 所有安装共用这一个模型目录，跟每个安装的代码/环境是分离的。** 删安装、换版本，模型目录纹丝不动。

## 切换：零模型迁移的三步

**第 1 步：克隆核心版**

```bash
git clone --depth 1 https://github.com/Comfy-Org/ComfyUI.git "C:/yoyac-work/ComfyUI"
```

我拿到的是 v0.46.0（含 H3 支持）。

**第 2 步：用一行配置指向共享模型目录**

在 `C:\yoyac-work\ComfyUI\` 建 `extra_model_paths.yaml`：

```yaml
comfyui:
  base_path: C:\Users\aww\AppData\Local\Comfy-Desktop\ComfyUI-Shared\models
  checkpoints: checkpoints/
  diffusion_models: diffusion_models/
  text_encoders: text_encoders/
  vae: vae/
  loras: loras/
  ...
```

启动时日志会逐条打出来，比如 `[INFO] Adding extra search path diffusion_models ...ComfyUI-Shared\models\diffusion_models`。

**第 3 步：连 Python 环境都复用，省 2.5GB**

核心版装依赖本来要下载一堆 torch。我看了眼 Desktop 安装里的 `MiniMax\.venv`，里面**已经有** torch 2.12.1+cu130 和 comfy-kitchen 0.2.42——正是 v0.46 需要的。直接让核心版用这个现成环境，零下载：

```bat
@echo off
cd /d "C:\yoyac-work\ComfyUI"
"C:\Users\aww\AppData\Local\Comfy-Desktop\ComfyUI-Installs\MiniMax\ComfyUI\.venv\Scripts\python.exe" main.py --port 8190
```

## 侧边栏 Agent 也换了：官方闭源 → 第三方自带模型

官方 Agent 不能换模型，那我装一个能换的：`CrazyDashTool/ComfyUI-Agent`，作者原话就是「A local, bring-your-own-model alternative to the built-in Comfy Agent」。

装进 `custom_nodes\` 后，它的 `config.json` 里直接填我的商汤端点：

```json
{
  "provider": "openai",
  "base_url": "https://api.hcnsec.cn/v1",
  "model": "sensenova-6.8-flash",
  "bridge": "mcp"
}
```

它是 OpenAI 兼容端点，商汤日日新 `https://api.hcnsec.cn/v1` 直接用（我 doc-converter 项目里本来就在用这个）。端到端验证：**商汤文本响应 ✅ + tool calling ✅**（Agent 能操作画布）。

## 实测结果

- `start.bat` 双击启动，日志 `[INFO] ComfyUI version: 0.46.0`、`[INFO] To see the GUI go to: http://127.0.0.1:8190`、`[INFO] Total VRAM 12288 MB`（我的 RTX 3060 12GB）。
- H3 模型被核心版正常识别，一个文件都没重下。
- Agent 用的是**我的商汤额度**，跟 Comfy 积分体系彻底无关。

## 两个必须知道的坑

1. **别删 Desktop 的 MiniMax 安装**。它的 `.venv` 现在是核心版的运行环境（torch 2.12），删了核心版起不来。它和模型目录是两回事：删安装目录删的是代码和环境，`ComfyUI-Shared\models` 不在这条删除链上。
2. **git-bash 里跑 bat** 要 `MSYS_NO_PATHCONV=1 cmd /c "...\start.bat"`；正常双击或用 Windows cmd 没这问题。

## 一句话复盘

Comfy Desktop 的「模型」和「安装」是**两套独立目录**，模型在 `ComfyUI-Shared\models`（所有安装共享），所以从闭源客户端切到开源核心版，代价只是一行 `extra_model_paths.yaml` + 一个指向现成 `.venv` 的启动脚本，170GB 模型纹丝不动。真正要避开的是那个**闭源的 Comfy Agent**（积分墙），而不是 ComfyUI 本身——它一直开源。
