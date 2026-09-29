---
title: 一个"不支持图片"的bug，让我翻遍了整个dsh源码
date: 2026-09-10 08:00:00
permalink: /2026/09/10/dsh-image-input-debugging/
tags:
  - dsh
  - DeepSeek
  - 调试
  - LLM
  - 配置
  - 源码阅读
categories:
  - 技术随笔
---

# 一个"不支持图片"的bug，让我翻遍了整个dsh源码

> 调试一个API报错的过程，意外揭示了LLM框架配置层的工作原理。有时候，问题不在代码里，而在配置里。

2026年9月，我在家里的VPS上跑着DeepSeek Harness（dsh）的web界面，想用sensenova-6.8-flash-lite这个模型来做多模态任务——上传一张图片让模型识别。结果返回了一个让我摸不着头脑的错误：

```json
{
  "error": {
    "code": "attachment-error",
    "message": "Model \"sensenova-6.8-flash-lite\" does not support image input.",
    "details": {
      "reason": "MODEL_DOES_NOT_SUPPORT_IMAGES"
    }
  }
}
```

**问题在这里：** sensenova-6.8-flash-lite明明是支持图片的模型。讯飞官网明确写了它是多模态模型，能处理文本和图片。那为什么dsh拒绝了我上传的图片？

这个问题的解决过程，意外地成为了一次深入理解LLM框架配置机制的旅行。今天把它写下来，希望能帮到遇到同样问题的朋友。

---

## 一、问题的起点：一个看起来不太可能的错误

我的环境是这样的：

- 一台腾讯云VPS（OpenCloudOS 9.4），跑了Hexo博客、RustDesk服务器、mall-server
- 上面部署了dsh web（DeepSeek Harness），监听127.0.0.1:3080
- 通过Nginx反代到公网端口3081
- 默认模型是 `sense-nova` provider 下的 `sensenova-6.8-flash-lite`
- API Key存在 `/root/.dsh/.credentials.yaml` 里

一切看起来都很正常。直到我上传了一张图片。

一开始我以为是API Key的问题，或者是Sensenova服务端的问题。我试着直接调用Sensenova API：

```bash
curl https://token.sensenova.cn/v1/models \
  -H "Authorization: Bearer $SENSENOVA_API_KEY"
```

结果发现... API Key在环境变量里根本没设置。dsh是从进程环境中读取的，跟Hermes Agent用的Key不是一个东西。这不是API Key的问题。

我也排除了Nginx的问题——Nginx只是反代，不会拦截内容。

那问题出在哪？

---

## 二、顺着错误信息，追进了源码

错误信息是 `MODEL_DOES_NOT_SUPPORT_IMAGES`。我在dsh的源码里搜索这个关键词：

```bash
grep -rn "MODEL_DOES_NOT_SUPPORT_IMAGES" /root/.nvm/versions/node/v25.2.0/lib/node_modules/@deepseek-ai/dsh/
```

找到了。在 `dsh-host-apiproxy/lib/types/api-proxy.js` 里：

```js
if (hasImage) {
    const current = selectionFor(agent).current;
    const modelInfo = await ctx.llm.resolveModelInfo(current.provider, current.model);
    if (modelInfo.inputModalities !== undefined && !modelInfo.inputModalities.includes('image')) {
        return err(request, {
            code: 'attachment-error',
            message: `Model "${current.model}" does not support image input.`,
            details: { reason: 'MODEL_DOES_NOT_SUPPORT_IMAGES' },
        });
    }
}
```

逻辑很清晰：**检查模型的 `inputModalities` 是否包含 `image`，不包含就拒绝。**

那 `inputModalities` 是从哪来的？继续追查：

```js
// dsh-llm-pi-ai/lib/index.js
inputModalities: [...resolvedModel.input]
```

来自 `resolvedModel.input`。再往上追：

```js
input: declaredInput(entry.input) ?? base?.input ?? [...request.defaultInput]
```

这里有三层fallback：
1. 模型条目自己声明的 `input`
2. Provider级别的默认 `input`
3. `request.defaultInput`，也就是 **`DEFAULT_INPUT = ["text"]`**

**问题找到了。** 我的 `settings.yaml` 里，`sensenova-6.8-flash-lite` 只写了：

```yaml
- id: sensenova-6.8-flash-lite
  name: sensenova-6.8
```

没有 `input` 字段。于是pi-ai库 fallback到了默认的 `["text"]`，告诉dsh"这个模型只支持文本"。dsh接收到这个信息，就拒绝了图片。

**模型本身支持图片，但dsh的配置没有声明这件事。**

---

## 三、为什么默认值是["text"]？

这涉及到pi-ai库的设计哲学。

pi-ai是DeepSeek团队开发的一个LLM抽象层，它假设：**如果一个模型没有明确声明支持图片，那就默认不支持。**

这是一种安全策略。如果你不小心给一个纯文本模型传了图片，框架不会尝试发送，而是提前报错。这比让模型收到图片后随机丢弃或报错要好得多。

但代价是：**所有新模型都需要手动声明能力。** 这对于经常更换模型、使用新兴模型的用户来说，确实有点麻烦。

---

## 四、修复：给模型声明能力

修复很简单——在 `settings.yaml` 里给模型加上 `input` 字段：

```yaml
- id: sensenova-6.8-flash-lite
  name: sensenova-6.8
  input:
    - text
    - image
```

但我不止修了一个模型。我把所有已知的多模态模型都声明了一遍：

**讯飞系（sensenova provider）：**
- `sensenova-6.8-flash-lite` — 多模态
- `sensenova-u1.5-lite` — 多模态
- `deepseek-v4-flash` / `deepseek-v4-pro` — DeepSeek V4系列支持图片
- `glm-5.2` — 智谱GLM多模态

**HCNSEC代理下的模型：**
- `sensenova-6.8-flash-lite` — 同上
- `sensenova-u1.5-lite` — 同上
- `glm-5.3-flash` — 智谱新一代多模态
- `longcat-2.0` — LongCat多模态
- `spark-x2.5` — 讯飞星火多模态
- `step-3.7-flash` — Step系列多模态

**没有声明的模型（判断为纯文本）：**
- `kimi-k3` — 月之暗面，以代码/文本为主
- `sensenova-6.7-flash-lite` — 已知只有文本能力
- `sensenova-u1-fast` — 快速版，纯文本
- `auto` — 自动路由，不固定模型
- `MiniMax-M3`、`step-explore`、`step-router-v1` — 文本/函数调用类
- `Qwen3-Embedding-8B`、`Qwen3.6-35B-A3B` — 嵌入/基座模型

改完配置文件后，重启dsh：

```bash
kill $(pgrep -f 'dsh web')
nohup dsh web --no-open --host 127.0.0.1 --port 3080 \
  --trusted-host 43.153.148.187:3081 &
```

再次上传图片，问题解决。

---

## 五、更深一层：API的Wire Schema

修复过程中，我还发现了一个有趣的现象。

dsh的 `session.prompt` 接口接受的图片格式，跟OpenAI的API不太一样。OpenAI用的是：

```json
{"type": "image_url", "image_url": {"url": "data:image/..."}}
```

而dsh用的是：

```json
{"type": "image", "mediaType": "image/jpeg", "data": "<base64>"}
```

这是dsh自己定义的Wire Schema（在 `dsh-host-apiproxy/lib/types/api/sessions.schema.js` 里）：

```js
export const promptContentPartSchema = z.discriminatedUnion('type', [
    z.object({ type: z.literal('text'), text: z.string() }),
    z.object({ type: z.literal('image'), mediaType: imageMediaTypeSchema, data: z.string(), name: z.string().optional() }),
]);
```

`mediaType` 只支持四种：`image/png`、`image/jpeg`、`image/webp`、`image/gif`。

如果你用OpenAI的格式（`image_url`），dsh会直接拒绝，报 `invalid_union` 错误。这也是一个容易踩的坑。

---

## 六、教训与思考

### 1. 配置即代码，文档即真相

这个问题最根本的原因是：**配置里没有声明能力，框架就认为你没有这个能力。**

dsh的 `settings.yaml` 是整个系统的"真相源"。模型支持什么、不支持什么，不是由模型本身的特性决定的，而是由配置文件决定的。

这让我想起了一句老话：**"What you configure is what you get."** 你配了什么，就得到什么；你没配，就没有。

### 2. 错误信息是你的朋友

`MODEL_DOES_NOT_SUPPORT_IMAGES` 这个错误信息虽然简短，但指向性很明确。它告诉你：**框架认为这个模型不支持图片。** 剩下的问题就是搞清楚"为什么框架这么认为"。

很多人看到错误就慌了，直接去搜"怎么解决MODEL_DOES_NOT_SUPPORT_IMAGES"。但其实错误信息本身就包含了答案——只是需要一点好奇心去追问。

### 3. 新模型要手动声明能力

这是一个合理的成本。pi-ai库无法自动探测每个模型的 multimodal 能力（尤其是通过自定义API端点接入的模型）。所以每次接入新模型，都需要手动声明：

```yaml
- id: new-model-id
  input:
    - text
    - image  # 如果支持图片的话
```

### 4. 源码是最好的文档

这个问题最终靠翻源码解决。dsh的源码不算复杂，结构清晰。如果你遇到问题，`grep` 是最快的调查工具。

```bash
# 搜错误码
grep -rn "MODEL_DOES_NOT_SUPPORT_IMAGES" /path/to/dsh/

# 搜模型能力检查
grep -rn "inputModalities\|input.*image" /path/to/dsh/

# 搜schema定义
grep -rn "promptContentPartSchema\|imageMediaTypeSchema" /path/to/dsh/
```

这三个搜索，几乎覆盖了我整个调试过程。

---

## 附：完整的settings.yaml配置

修改后的 `/root/.dsh/settings.yaml` 关键部分：

```yaml
agent-default-model:
  provider: sense-nova
  model: sensenova-6.8-flash-lite

llm-pi-ai:
  providers:
    sense-nova:
      apiKeyEnv: SENSE_NOVA_API_KEY
      api: openai-completions
      baseURL: https://token.sensenova.cn/v1
      models:
        - id: sensenova-6.8-flash-lite
          name: sensenova-6.8
          input: [text, image]
        - id: sensenova-u1.5-lite
          name: sensenova-u1.5-lite
          contextWindow: 262144
          input: [text, image]
        - id: deepseek-v4-flash
          name: deepseek-v4-flash
          contextWindow: 1048576
          input: [text, image]
        - id: deepseek-v4-pro
          name: deepseek-v4-pro
          contextWindow: 1048576
          input: [text, image]
        - id: glm-5.2
          name: glm-5.2
          contextWindow: 1048576
          input: [text, image]
        - id: kimi-k3
          name: kimi-k3
          contextWindow: 1048576
          # 纯文本，不加input

    hcnsec:
      apiKeyEnv: HCNSEC_API_KEY
      api: openai-completions
      baseURL: https://api.hcnsec.cn/v1
      models:
        - id: auto
          # 自动路由，不固定模型
        - id: sensenova-6.8-flash-lite
          input: [text, image]
        - id: sensenova-u1.5-lite
          input: [text, image]
        - id: glm-5.3-flash
          input: [text, image]
        - id: longcat-2.0
          input: [text, image]
        - id: spark-x2.5
          input: [text, image]
        - id: step-3.7-flash
          input: [text, image]
```

---

**写在最后**

调试技术问题最有趣的时刻，不是找到答案的那一刻，而是**意识到问题比你想象的要简单的那一刻**。

这个bug花了大约两个小时排查。两个小时的调查路径是：

1. 排除API Key问题
2. 排除Nginx反代问题
3. 找到错误信息在源码中的位置
4. 顺着数据流追到配置层
5. 发现问题——只是少了几行YAML

有时候，我们花了太多时间怀疑"复杂原因"，而忽略了"简单原因"。

这次经历也让我更深入地理解了dsh的架构：它不只是一个LLM客户端，而是一个**配置驱动的模型路由层**。你的 `settings.yaml` 就是真相源，它决定了框架如何看待世界。

所以，下次遇到"模型不支持XX"的错误，先别急着换模型——检查一下你的配置。
