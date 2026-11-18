---
title: 用本地 Ollama 翻译一本英文教科书：踩过的那些坑
date: 2026-11-10 12:00:00
type: tech
tags:
  - Ollama
  - PDF
  - 翻译
  - 工程实践
categories:
  - 技术思考
---

最近想把我手上一本英文版编译原理教材翻译成中文自用——《Introduction to Compilers and Language Design》，247 页，纯文本 PDF，作者是 Notre Dame 的 Douglas Thain，开源免费。

思路很简单：**抽文本 → 逐段翻译 → 重建 PDF**。但真正动手之后发现，这套流程里每一个环节都藏着坑。这篇文章记录我从零到跑通的全程踩过的坑，以及怎么一个个解决的。

## 第一步：文本提取，就碰上了编码坑

第一个坑来自 pdftotext（Poppler 的工具）。一行命令：

```bash
pdftotext compiler.pdf compiler.txt
```

看起来没问题？Windows 上 pdftotext 默认以 Latin-1 输出，而 Python 3 读文件时默认 UTF-8。结果：

```
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xa9 in position 168: invalid start byte
```

更诡异的是，即便你指定了 `encoding='latin-1'` 读取，有些字也会被还原成 `\xad` 这样的软连字符（比如 "Chapter 1 ­ Introduction"，那个中间有个软连字符）。

**教训**：PDF 里的文字不一定是干净的。遇到乱码，先检查 source PDF 本身是不是扫描件（扫描版用 pdftotext 基本废了），再考虑编码问题。我们这本书是纯文本 PDF，但排版工具留下的特殊字符还是会干扰后续处理。

## 第二步：分块策略——你以为切得够细就够了吗

全书 68,963 词，247 页。如果用 Ollama 本地模型逐段翻译，每次请求大概需要 2-5 秒（gemma3:12b）。粗略估算：假设平均每段 300 字，大约需要 2000+ 次请求，耗时约 2 小时。

但问题是：**PDF 转出来的文本不是一段一段的均匀段落**。

### 坑一：TOC（目录）被当成正文翻译

第一次跑脚本，我发现前几个 chunk 全是从文件头开始的完整目录——整整 25K 字的目录条目被当作正文发给了翻译 API。这不是钱的问题，这是浪费时间的问题。

修复方式是在 chunking 阶段识别并跳过 TOC 区域——通常是从 "Contents" / "目录" 字样开始，到第一章出现为止。

### 坑二：短噪音段落

排完 TOC 之后，又发现了另一个问题：**大量小于 30 字符的独立行**——页码、章节小标题、图注标签等。统计下来有 931 个这样的噪音段。如果每个都单独发一次 API 请求，不仅慢，还会频繁触发速率限制。

修复方案：合并短段 + 过滤纯数字/罗马数字页码行。

```python
def is_skip_chunk(text):
    text = text.strip()
    if not text:
        return True
    # 纯罗马数字页码
    if re.match(r'^[ivxlcdm]+$', text, re.IGNORECASE) and len(text) <= 4:
        return True
    # 纯阿拉伯数字（页码）
    if re.match(r'^\d+$', text) and len(text) <= 3:
        return True
    # 纯点的行
    if re.match(r'^[\.\s]+$', text):
        return True
    # 太短的段跳过
    if len(text) < 3:
        return True
    # TOC 风格条目："1.1 Title . . . . . . 5"
    if re.match(r'^\d+\.\d+\s+.*\.\.\.', text):
        return True
    return False
```

### 坑三：chunk 大小失控

最头疼的一个 bug：设置了 `max_chunk_chars=300`，但实际输出的 chunk 最大有 2277 字。原因是句子拆分逻辑有缺陷——只按换行符分割，没有进一步对长行做截断。

最终修复：在 chunk 生成阶段强制按字符数截断，超过上限的行按句号/分号重新切分：

```python
def split_into_chunks(text, max_chunk_chars=280):
    lines = text.split('\n')
    chunks = []
    current_chunk = []
    current_len = 0

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if current_chunk:
                chunk_text = '\n'.join(current_chunk)
                if len(chunk_text) >= 20:
                    chunks.append(chunk_text)
                current_chunk = []
                current_len = 0
            continue

        if current_len + len(stripped) + 1 > max_chunk_chars and current_chunk:
            chunks.append('\n'.join(current_chunk))
            current_chunk = [stripped]
            current_len = len(stripped)
        else:
            current_chunk.append(stripped)
            current_len += len(stripped) + 1

    if current_chunk:
        chunk_text = '\n'.join(current_chunk)
        if len(chunk_text) >= 20:
            chunks.append(chunk_text)

    return chunks
```

修复后验证：`Max chunk: 299 chars ✓`，全部在限制之内。

## 第三步：API 选择与速率限制

最初想用 SenseNova API（国内兼容 OpenAI 接口的平台），速度快、质量不错。但很快遇到了 **429 速率限制**——每轮最多并发请求数是有限制的，批量翻译时很容易触发。

改用 Ollama 本地模型（gemma3:12b，约 8GB 显存占用），虽然慢一些（每 chunk 约 5-10 秒），但没有速率限制，可以安心跑着不用管它。

模型选择上做了个小实验：qwen3:14b 单次请求 timeout 了 90 秒，说明它太重；gemma3:12b 速度适中，翻译质量也可以接受。**本地推理的速度和模型大小直接相关，选对了模型能省不少时间。**

## 第四步：PDF 重建——WeasyPrint 在 Windows 上是噩梦

译完文本之后，需要重建 PDF。第一个想法是用 WeasyPrint（HTML → PDF），但装上发现它在 Windows 上依赖 GTK，折腾半天装不好。

退而求其次用了 **fpdf2**，一个纯 Python 的 PDF 生成库：

```bash
pip install fpdf2
```

安装秒完，功能也够用。对于教材这种以文字为主的文档，fpdf2 完全胜任——代码块用等宽字体，正文用常规字体，段落间距调整好就行。

## 第五步：进度保存——断点续传不能少

翻译跑了 1000+ 个 chunk，万一中途断了怎么办？每次都从头再来是不现实的。

解决方案：用 JSON 文件记录已翻译的 chunk 索引和内容，每次启动时加载进度继续：

```python
PROGRESS_FILE = 'compiler_zh.progress'

# 加载进度
translated_map = {}
if os.path.exists(PROGRESS_FILE):
    with open(PROGRESS_FILE, 'r', encoding='utf-8') as f:
        progress_data = json.load(f)
    translated_map = progress_data.get('translated', {})

# 每 20 个 chunk 保存一次进度
if chunk_num % 20 == 0:
    with open(PROGRESS_FILE, 'w', encoding='utf-8') as f:
        json.dump({'translated': translated_map, 'total': len(chunks)}, f, ensure_ascii=False)
```

当前进度：1115/1961 个 chunk 已完成，预计再跑半小时左右能结束。

## 总结：一套可用的本地 PDF 翻译流水线

经过反复调试，最终形成的 pipeline 是：

```
PDF → pdftotext → 编码修复 → 智能分块（跳过页码/目录）
    → Ollama gemma3:12b 逐段翻译 → JSON 进度持久化
    → fpdf2 重建 PDF
```

整个过程踩过的坑：

| 坑 | 症状 | 解法 |
|---|---|---|
| pdftotext 编码 | UnicodeDecodeError / `\xad` 乱码 | 明确指定 latin-1 读取，后处理替换特殊字符 |
| TOC 被翻译 | 前几百个 chunk 全是目录条目 | chunking 阶段识别并跳过 TOC 区域 |
| 短噪音段落多 | 931 个 <30 字符的独立行 | is_skip_chunk 过滤 + 短段合并 |
| chunk 超限 | max_chunk_chars=300 但实际 2277 | 强制按句号和换行双重截断 |
| API 速率限制 | SenseNova 报 429 | 切到本地 Ollama，牺牲速度换稳定 |
| WeasyPrint 装不上 | Windows GTK 依赖冲突 | 改用 fpdf2 |

这个流水线的核心价值在于：**全程本地运行，零 API 费用，不依赖任何云服务**。唯一的代价是时间——但对于一本 247 页的书来说，半天时间换来一本完整的中文教材，值了。

完整代码仓库在 `C:\yoyac-work\compiler_book_translation\`，有多个版本的迭代脚本，从最初的 translate.py 一路修到了 translate_gemma_v2.py。如果你想自己尝试，建议从 v2 版本起步——它包含了所有坑的修复。
