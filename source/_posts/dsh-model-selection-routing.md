---
title: dsh模型选择与Session路由：一层一层的优先级
date: 2026-09-10 11:00:00
permalink: /2026/09/10/dsh-model-selection-routing/
tags:
  - dsh
  - DeepSeek
  - 架构
  - 源码阅读
  - LLM
  - 教程
categories:
  - 技术随笔
---

# dsh模型选择与Session路由：一层一层的优先级

昨天修图片输入的时候，我在源码里看到了一段有趣的逻辑——模型选择不是一次性决定的，而是**每读一次都重新计算**，优先级从三个来源叠加。这种设计让 per-session 覆盖变得简单又可靠。

---

## 一、模型选择的三层优先级

在 `dsh-host-apiproxy/lib/types/api-proxy.js` 里，有一个 `selectionFor(agent)` 函数，它返回一个响应式对象：

```js
function selectionFor(agent) {
    const installed = selections.get(agent);
    if (installed !== undefined) return installed;

    let picked;  // ← 运行时覆盖值

    const selection = {
        get current() {
            // 第1优先：运行时手动设置的覆盖值
            if (picked !== undefined) return picked;

            // 第2优先：session 日志里记录的 config
            const logged = agent.session.requestHeader()?.config;
            if (logged === undefined)
                return defaults.defaultModelSelection();

            return {
                provider: logged.provider,
                model: logged.model,
                ...(logged.reasoningEffort === undefined
                    ? {}
                    : { reasoningEffort: logged.reasoningEffort }),
            };
        },
        set current(next) {
            picked = next;
        },
        assembled: undefined,
    };

    installModelSelection(agent.ctx, selection);
    selections.set(agent, selection);
    return selection;
}
```

三层优先级：

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1（最高） | `picked`（运行时覆盖） | 用户在 UI 里选了某个模型，临时覆盖当前 session |
| 2 | `agent.session.requestHeader()?.config` | session 日志里持久化的 provider/model |
| 3（最低） | `defaults.defaultModelSelection()` | settings.yaml 里的 `agent-default-model` |

**关键设计**：每次读 `.current` 都重新计算，不会缓存。这意味着你在 UI 里切换模型，下一秒就能生效——不需要重启。

---

## 二、defaultModelSelection 从哪来？

```js
const agentOptions = () => {
    const { provider, model } = defaults.defaultModelSelection();
    return { provider, model };
};
```

`defaults` 来自 dsh 启动时加载的 settings：

```js
// dsh-host-apiproxy/lib/index.js
defaultModelSelection: () => ctx.agentDefaultModel.currentSelection(),
```

最终读的是 `/root/.dsh/settings.yaml` 里的：

```yaml
agent-default-model:
  provider: sense-nova
  model: sensenova-6.8-flash-lite
```

所以**全局默认模型**就这一个配置决定。

---

## 三、Session 级别的持久化

每创建一个 session，dsh 会在 session 日志里记录当时的 model selection：

```js
// 当用户创建或恢复一个 session 时
agent.session.setRequestHeader({
    config: {
        provider: selection.provider,
        model: selection.model,
        reasoningEffort: selection.reasoningEffort,
    }
});
```

这个 header 会持久化到 session 的 JSONL 日志里。下次恢复这个 session 时：

```js
const logged = agent.session.requestHeader()?.config;
// logged = { provider: "sense-nova", model: "sensenova-6.8-flash-lite" }
```

dsh 会读出来，作为第二优先级的来源。

**这意味着什么？**

你的每个 session 都有自己的"默认模型"。新建 session 时会继承上次用的模型，不会每次都回到全局默认。这在多模型场景下很实用——写代码的 session 用 DeepSeek，聊天的 session 用 GLM，互不干扰。

---

## 四、per-session 覆盖怎么用？

当你在 dsh web UI 的 Settings 页面选了一个不同的模型，实际上是调用了：

```js
selection.current = {
    provider: 'hcnsec',
    model: 'glm-5.3-flash',
};
```

这会设置 `picked` 变量（第一优先级）。之后的所有请求都会用这个 provider/model，直到你：
- 再次切换（覆盖 `picked`）
- 清除覆盖（把 `picked` 设为 undefined）

在源码里，清除覆盖发生在 `unmountPresetFor` 里——卸载 preset 时清除 per-session 的临时选择。

---

## 五、图片检查时用的是哪一层？

回到昨天的 bug。图片 admission 检查发生在 `session.prompt` 处理里：

```js
const current = selectionFor(agent).current;
const modelInfo = await ctx.llm.resolveModelInfo(current.provider, current.model);
if (modelInfo.inputModalities !== undefined && !modelInfo.inputModalities.includes('image')) {
    return err(request, {
        code: 'attachment-error',
        message: `Model "${current.model}" does not support image input.`,
        details: { reason: 'MODEL_DOES_NOT_SUPPORT_IMAGES' },
    });
}
```

注意这里读的是 `selectionFor(agent).current`——也就是三层优先级合并后的结果。所以：

- 如果用户在 UI 临时切到了不支持图片的模型 → 图片被拒（正确行为）
- 如果 session 日志记录的是不支持图片的模型 → 图片被拒（正确行为）
- 如果全局默认不支持图片 → 图片被拒（正确行为）

这也解释了昨天遇到的第二个错误：`Model "auto" does not support image input.`——那个 session 的 requestHeader 里记录的模型是 `auto`，而 `auto` 没有声明 `input` 能力。

---

## 六、模型能力的解析链

`resolveModelInfo` 的内部逻辑：

```js
modelInfo(snapshot, provider, model) {
    const profile = this.profileOf(snapshot, provider);
    const resolvedModel = this.modelOf(snapshot, provider, model);

    return {
        provider,
        id: model,
        name: resolvedModel.name,
        inputModalities: [...resolvedModel.input],   // ← 来自 settings.yaml
        context: { contextWindow: resolvedModel.contextWindow },
        ...reasoningInfo(resolvedModel, defaultLevel)
    };
}
```

`resolvedModel.input` 的赋值：

```js
input: declaredInput(entry.input) ?? base?.input ?? [...request.defaultInput]
```

其中：
- `entry.input`：模型条目自己声明的（如 `[text, image]`）
- `base?.input`：provider 级别的默认
- `request.defaultInput`：pi-ai 的全局默认，即 `["text"]`

所以：
- 声明了 `input` → 用声明的值
- 没声明 → fallback 到 `["text"]`
- 结果是 `["text"]` → 图片被拒

---

## 七、实际例子：一个 session 的完整选择过程

假设你做了以下操作：

1. 全局默认：`sense-nova / sensenova-6.8-flash-lite`
2. 创建 session A，在 UI 切换到 `hcnsec / glm-5.3-flash`
3. 继续用 session A 发了几个消息
4. 在 UI 切回 `sense-nova / sensenova-6.8-flash-lite`
5. 创建 session B（没动过 UI）

各阶段 `selection.current` 的值：

| 时刻 | picked | session.log | default | 最终 current |
|------|--------|-------------|---------|-------------|
| 步骤1后 | undefined | 无 | sense-nova/6.8 | sense-nova/6.8 |
| 步骤2后 | hcnsec/glm-5.3 | 无 | — | hcnsec/glm-5.3 |
| 步骤3后 | hcnsec/glm-5.3 | hcnsec/glm-5.3 | — | hcnsec/glm-5.3 |
| 步骤4后 | sense-nova/6.8 | hcnsec/glm-5.3 | — | sense-nova/6.8 |
| 步骤5后 | undefined | 无 | sense-nova/6.8 | sense-nova/6.8 |

可以看到：
- `picked` 消失后，`session.log` 接管
- 新 session 没有 log，回到 `default`

---

## 八、总结

dsh 的模型选择是一个**动态计算、三层叠加**的系统：

```
用户UI切换 → picked（最高，临时）
    ↓ 未设置
session日志 → requestHeader.config（中等，持久）
    ↓ 未记录
全局默认 → settings.yaml agent-default-model（最低，兜底）
```

这个设计的优点：
- 灵活性：可以随时切换，不影响其他 session
- 持久性：每个 session 记住自己的偏好
- 可靠性：永远有兜底，不会选到 null

理解了这套机制，遇到"模型选错了"、"切换不生效"、"新 session 用了奇怪的模型"这类问题，就有排查方向了。
