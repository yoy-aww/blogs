---
title: 我把 C 盘从「只剩 60GB」清出 138GB，才搞懂磁盘清理要分三层
date: 2026-11-28 09:30:00
type: tech
permalink: /2026/11/28/windows-disk-cleanup-three-layers/
tags:
  - Windows
  - 磁盘清理
  - 方法论
---

## 一句话结论

Windows 磁盘清理不是「删缓存」，是**分清三层**：① 纯垃圾（半截文件、重复副本、历史转储）——直接删；② 纯缓存可重建（npm-cache、`.log.1`、`__pycache__`）——删了下次按需重下，没负担；③ **在用的资产**（ComfyUI 模型、IDE 安装本体、虚拟环境）——不是垃圾，删错就是事故。这次从 C 盘可用 **60GB 清到 197.9GB**，净回收约 **138GB**，靠的是先给每个候选目录过一遍「在用检查清单」，再动手。

## 起因：C 盘告急，但「大户」不在你以为的地方

C 盘 1TB，**已用 938GB，只剩 60GB**。直觉上先怪 Hermes 缓存——一查，Hermes 全目录才 5.7GB，清完省 260MB，杯水车薪。

真正的大头是两层，都在你**没料到**的地方：

- `C:\Users\aww\.cache` = **43.2GB**，其中 `huggingface` 模型缓存 **40GB**
- 但更大的还在后头：ComfyUI 模型目录 = **163GB**（注意不是 16GB，是 166,963MB）。**比 HF 缓存大 4 倍**，这才是 857GB 已用的真正推手

一个反直觉的教训：**「缓存」目录不等于「可删」**。`.cache/huggingface` 里 40GB 大部分是**在用的模型**（Wan_2.1 17GB、Kolors 14.3GB），真正能删的只有一份重复下载和一个没下完的半截文件。而 ComfyUI 的 `models` 目录 163GB 里，有一半是死模型。

## 关键：动手前给每个候选过「在用检查清单」

清磁盘最怕的不是删得少，是**删错在用的东西**。这次每删一样前都先验证，四件事救了命：

**1. 硬链接 vs 独立副本——决定删了会不会真释放空间。**
HF 缓存的 `blobs/` 和 `snapshots/` 可能是硬链接共享，也可能各是一份。实测 `bge-large-zh` 的 `blobs` = **0MB**，说明两份快照是**独立副本**，删掉 `snapshots/0cc67d9...` 那份会真正释放 **1.24GB**，而不只是删个链接。

**2. 别删「在用的模型」。**
删前确认 Wan_2.1 在 ComfyUI 的 `diffusion_models/` 里有实体文件（`wan2.1_i2v_480p_14B_fp8` 15.6GB），删了工作流就断——**留**。反而 `minimax_h3_fl2va`（20GB）是旧版，实际跑的是新版 `ref2va`——**删**。

**3. 「IDE 缓存」可能根本不是缓存。**
JetBrains 占了 7GB，以为能清。一拆发现 `PyCharm2026.3/cache`、`system` 这些子目录**根本不存在**，7GB ≈ **6GB 是 Toolbox 的 IDE 安装本体** + 1GB 配置。删了等于卸载 PyCharm/WebStorm。**这不是垃圾，是资产，不能当缓存删。**

**4. 「删了 32 个，跳过 131 个」不是失败。**
删 node_modules 时脚本报 `deleted=32, skipped=131`，看着像漏删。实际是 `os.walk` 找出了**嵌套**的 node_modules（`mallRN/node_modules/expo/node_modules`），删掉外层后内层自然消失，删除时已是 `not_exists`。用 `find -maxdepth 4 -name node_modules` 验证 = **0 个残留**，`failed=0`。

## 一个值得说的插曲：删完后发现「模板引用已删的模型」

删掉 `minimax_h3_fl2va` 后 grep 验证时发现，ComfyUI 自带的 `blueprints/Image to Video (MiniMax H3).json` **模板**引用的正是我删掉的 `fl2va` + `fl2v` LoRA。乍看像删错了——其实不是：**blueprint 是 ComfyUI 自带的旧模板，你实际跑的工作流用的是 `ref2va` + `ref2v_turbo_4step` LoRA**（11 月 24 日下载完成，cron 监控的就是它）。这是**模板与实体不一致**，不是数据丢失。所以判断「删得对不对」不能只看有没有文件引用它，要看**实际在跑的链路**用没用它。

## 顺手的两个 Windows 坑（省时间）

- **量目录大小别用 `du`**：遍历 TB 级目录，`du` 每个子目录起一个 300s 超时的子进程，直接卡死 420s。Windows 上 `robocopy /L` dry-run 或 PowerShell 才是秒级标准做法。
- **PowerShell 5.1 把无 BOM 的 UTF-8 脚本当 GBK 读**：脚本里带中文注释，直接语法崩溃。写成**纯 ASCII** 的 `.ps1` 就稳了。

## 战果（全部实测数字）

| 项 | 大小 | 判断 |
|---|---|---|
| `__pycache__` + 轮转日志 + 请求转储 | ~260MB | 纯垃圾，删 |
| bge 重复快照 | 1.24GB | 独立副本，删 |
| laion `.incomplete` 半截 | 0.82GB | 没下完，删 |
| **163 个 node_modules** | 3.59GB | 全清，要用时 `npm install` |
| Local npm-cache | 7.21GB | 纯缓存，删 |
| `minimax_h3_fl2va` 旧版 | 20GB | 死模型，删 |
| `qwen3vl_32b_nvfp4` 非量化 | 17GB | 有量化版在用，删 |
| `svd` + `sd_xl_turbo` | 16.5GB | 未用，删 |
| Kolors HF 缓存副本 | 16.9GB | ComfyUI 那份保留（独立副本），删 |
| `chatglm3` + `kolors_unet` + `ViT.H.14` | 20.6GB | 拍板删 |

**C 盘可用：60GB → 197.9GB，净回收约 138GB。**

## 留给你的一句话

下次清理前先问三个问题：这文件**有没有第二份**（重复吗）？**有没有实体文件在用**（查 `diffusion_models/`、`snapshots/` 而非只查引用）？删了是**重下**还是**重装**（npm-cache 重下，Toolbox 重装）？三个都答完，再动手。
