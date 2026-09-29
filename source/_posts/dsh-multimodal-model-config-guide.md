---
title: dsh多模态模型配置指南：哪些模型支持图片，怎么声明
date: 2026-09-10 09:00:00
permalink: /2026/09/10/dsh-multimodal-model-config-guide/
tags:
  - dsh
  - DeepSeek
  - 配置
  - 多模态
  - 教程
  - LLM
categories:
  - 技术随笔
---

昨天我遇到了一个奇怪的问题：在 dsh（DeepSeek Harness）里给 sensenova-6.8-flash-lite 上传图片，结果报错"Model does not support image input"。后来发现原因很简单——**模型的 `input` 能力没有在配置里声明**，pi-ai 默认只认文本。

修好之后我整理了所有模型的多模态能力，顺便把完整的配置方法写下来，方便以后用到。

---

## 一、dsh 是怎么判断模型是否支持图片的？

dsh 的 LLM 层用的是 pi-ai 库。它在收到图片请求时，会检查模型的 `inputModalities`：

```js
// pi-ai 源码
if (containsImage && !model.input.includes("image")) {
    throw new LlmError(`pi-ai model "${model.id}" does not support image input`, "UNSUPPORTED_CONTENT");
}
```

而模型的能力来自你的 `settings.yaml`：

```yaml
models:
  - id: sensenova-6.8-flash-lite
    input:          # ← 这个字段决定了一切
      - text
      - image
```

如果不写 `input`，pi-ai 使用默认值 `["text"]`，图片就被拒了。

**记住一条规则：不声明 = 不支持。**

---

## 二、各模型多模态能力对照表

根据供应商文档和源码逻辑，整理如下：

### sense-nova 提供商（讯飞 Sensenova）

| 模型 ID | 支持图片 | 上下文窗口 | 备注 |
|---------|---------|-----------|------|
| sensenova-6.8-flash-lite | ✅ | 未声明 | 讯飞主力多模态模型 |
| sensenova-6.7-flash-lite | ❌ | 262144 | 纯文本 |
| sensenova-u1-fast | ❌ | 262144 | 快速版，纯文本 |
| sensenova-u1.5-lite | ✅ | 262144 | 多模态 |
| deepseek-v4-flash | ✅ | 1048576 | DeepSeek V4 系列支持图片 |
| deepseek-v4-pro | ✅ | 1048576 | DeepSeek V4 系列支持图片 |
| glm-5.2 | ✅ | 1048576 | 智谱 GLM 多模态 |
| kimi-k3 | ❌ | 1048576 | 月之暗面，代码/文本为主 |

### hcnsec 提供商（HCNSEC 聚合代理）

| 模型 ID | 支持图片 | 备注 |
|---------|---------|------|
| auto | ⚠️ 不确定 | 自动路由，不固定模型，声明意义不大 |
| DeepSeek-V4-Flash | ✅ | 同 sense-nova 的 deepseek-v4-flash |
| DeepSeek-V4-Pro | ✅ | 同 sense-nova 的 deepseek-v4-pro |
| glm-5.3-flash | ✅ | 智谱新一代多模态 |
| longcat-2.0 | ✅ | LongCat 多模态 |
| spark-x2.5 | ✅ | 讯飞星火多模态 |
| step-3.7-flash | ✅ | Step 系列多模态 |
| sensenova-6.8-flash-lite | ✅ | 同 sense-nova |
| sensenova-u1.5-lite | ✅ | 同 sense-nova |
| kimi-k3 | ❌ | 纯文本 |
| MiniMax-M3 | ❌ | 文本/函数调用 |
| step-explore | ❌ | 文本探索类 |
| step-router-v1 | ❌ | 路由/函数调用类 |
| Qwen3-Embedding-8B | ❌ | 嵌入/基座模型 |
| Qwen3.6-35B-A3B | ❌ | 嵌入/基座模型 |

### 判定原则

- **有 "flash"、"lite"、"v4" 且来自 DeepSeek/GLM/讯飞星火/LongCat 的**，通常支持图片
- **有 "embedding"、"router"、"explore"、"fast" 的**，通常是纯文本
- **"auto" 这种路由模型**，声明了也没用，因为实际路由到的模型不确定
- **拿不准的时候**，加上 `input: [text, image]` 也没坏处——pi-ai 会在发送时做二次校验，不会造成额外问题

---

## 三、怎么修改配置

配置文件位置：`/root/.dsh/settings.yaml`

### 步骤一：编辑文件

用 vim 打开：

```bash
vim /root/.dsh/settings.yaml
```

### 步骤二：找到目标模型，加上 input 字段

**修改前：**

```yaml
- id: sensenova-6.8-flash-lite
  name: sensenova-6.8
```

**修改后：**

```yaml
- id: sensenova-6.8-flash-lite
  name: sensenova-6.8
  input:
    - text
    - image
```

注意 YAML 缩进要用空格，不要用 tab。

### 步骤三：重启 dsh

```bash
kill $(pgrep -f 'dsh web')
nohup dsh web --no-open --host 127.0.0.1 --port 3080 \
  --trusted-host 43.153.148.187:3081 &
sleep 3
ss -tlnp | grep 3080
```

### 步骤四：验证

在 dsh web 里上传一张图片，如果不再报 `MODEL_DOES_NOT_SUPPORT_IMAGES`，就说明配置生效了。

---

## 四、完整的 settings.yaml 参考

以下是我修改后的完整配置，供参考：

```yaml
agent-default-model:
  provider: sense-nova
  model: sensenova-6.8-flash-lite

llm-deepseek: {}

llm-pi-ai:
  providers:
    sense-nova:
      apiKeyEnv: SENSE_NOVA_API_KEY
      api: openai-completions
      baseURL: https://token.sensenova.cn/v1
      models:
        - id: sensenova-6.8-flash-lite
          name: sensenova-6.8
          input:
            - text
            - image
        - id: sensenova-6.7-flash-lite
          name: sensenova-6.7-flash-lite
          contextWindow: 262144
        - id: deepseek-v4-flash
          name: deepseek-v4-flash
          contextWindow: 1048576
          input:
            - text
            - image
        - id: glm-5.2
          name: glm-5.2
          contextWindow: 1048576
          input:
            - text
            - image
        - id: sensenova-u1-fast
          name: sensenova-u1-fast
          contextWindow: 262144
        - id: sensenova-u1.5-lite
          name: sensenova-u1.5-lite
          contextWindow: 262144
          input:
            - text
            - image
        - id: deepseek-v4-pro
          name: deepseek-v4-pro
          contextWindow: 1048576
          input:
            - text
            - image
        - id: kimi-k3
          name: kimi-k3
          contextWindow: 1048576

    hcnsec:
      apiKeyEnv: HCNSEC_API_KEY
      api: openai-completions
      baseURL: https://api.hcnsec.cn/v1
      models:
        - id: auto
        - id: DeepSeek-V4-Flash
        - id: DeepSeek-V4-Pro
        - id: glm-5.3-flash
          input:
            - text
            - image
        - id: kimi-k3
        - id: longcat-2.0
          input:
            - text
            - image
        - id: MiniMax-M3
        - id: Qwen3-Embedding-8B
        - id: Qwen3.6-35B-A3B
        - id: sensenova-6.8-flash-lite
          input:
            - text
            - image
        - id: sensenova-u1.5-lite
          input:
            - text
            - image
        - id: spark-x2.5
          input:
            - text
            - image
        - id: step-3.7-flash
          input:
            - text
            - image
        - id: step-explore
        - id: step-router-v1
```

---

## 五、一个容易踩的坑：API 格式

dsh 的 `session.prompt` 接口接受的图片格式，和 OpenAI API **不一样**。

**OpenAI 格式（不能用）：**

```json
{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
```

**dsh 格式（正确）：**

```json
{"type": "image", "mediaType": "image/jpeg", "data": "<base64>"}
```

支持的 mediaType 只有四种：`image/png`、`image/jpeg`、`image/webp`、`image/gif`。

用错了格式会报 `invalid_union` 错误，和 `MODEL_DOES_NOT_SUPPORT_IMAGES` 长得很像，容易混淆。

---

## 六、总结

1. **dsh 不自动探测模型能力**，你的 `settings.yaml` 就是真相源
2. **想支持图片，必须显式声明** `input: [text, image]`
3. **不确定某个模型是否支持图片？** 加上声明通常没坏处，pi-ai 会在发送时做二次校验
4. **API 格式要匹配**，dsh 用 `mediaType` + `data`，不是 `image_url`

如果你在用其他我没列出来的模型，可以把模型 ID 告诉我，我帮你确认要不要加声明。
