---
title: Sensenova 限速：控制台显示正常，API 却报 429
date: 2026-11-09 00:00:00
type: tech
permalink: /2026/11/09/sensenova-rpm-limit-hidden-trap/
tags:
  - API
  - Sensenova
  - 速率限制
  - CodeBuddy
  - 排错
description: CodeBuddy 调 Sensenova API 报 429，但控制台显示余额充足。排查发现 RPM/TPM 限制和账户余额是两个独立维度，控制台不暴露前者。
---

## 先说结论

Sensenova 的控制台只显示 **余额（credits）**，**不显示 RPM（每分钟请求数）和 TPM（每分钟 token 数）的速率限制**。余额充足 ≠ 没有限速。

我最近用 CodeBuddy 调 `deepseek-v4-flash` 模型时连续收到 429 错误，但登录腾讯云控制台一看，余额还有好几千，完全看不出问题在哪。

排查了半天才搞明白：**RPM/TPM 是平台级限制，不在控制台的可视范围内**。

---

## 问题现象

CodeBuddy 报错信息：

```
Message: 请求过于频繁，请稍后再试
Error Code: 429
Raw Message: inference exceeds tpm/rpm limit
Type: rate_limit_error
Code: insufficient_quota
```

用户直觉反应："不可能啊，我刚充了值，余额还有这么多，怎么会限额？"

去 Sensenova 控制台一查，确实余额充足，没有任何告警。

---

## 真正的原因

经过日志分析和 curl 验证，确认了几个关键点：

### 1. 两个不同 key 走的是两个独立配额池

| Model | 端点 | Key 前缀 |
|-------|------|----------|
| `deepseek-v4-flash` | `token.sensenova.cn` | `sk-d***GOiX` |
| `sensenova-6.8-flash-lite` | `token.sensenova.cn` | `sk-h***7yYs` |

这两个 key 对应不同的 Sensenova 账户，各自有独立的 RPM/TPM 配额。**共用同一个域名不代表共享同一个配额**。

### 2. 429 响应来自 Sensenova 官方服务器，不是中间代理

通过检查响应头确认：

```bash
# 429 响应的 headers
HTTP/2 429
x-request-id: a43b7e5ed79a43a5991dd0fa91ad47ed
content-type: application/json

{
  "error": {
    "message": "inference exceeds tpm/rpm limit",
    "type": "rate_limit_error",
    "code": "insufficient_quota"
  }
}
```

注意：**没有** `x-oneapi-request-id` 或 `x-new-api-version` 这种第三方网关特有的 header。这说明请求直接到了 Sensenova 官方，没经过 OneAPI 中转。

### 3. 另一个 model 的问题更奇怪

同时使用的 `glm-5.1`（走 `api.iamhc.cn`，智谱 OpenRouter 兼容网关）返回的是完全不同的错误：

```json
{
  "error": {
    "code": "model_not_found",
    "message": "No available channel for model glm-5.1 under group auto (distributor)"
  }
}
```

这不是速率限制，而是 **OneAPI 网关上没有配置可用的 glm-5.1 渠道**。也就是说，你的 key 在 iamhc.cn 上能认证，但该网关下没有能转发到智谱模型的下游渠道。

---

## 排查过程

### Step 1：看 CodeBuddy 日志定位错误源

```bash
# 找到今天的日志目录
ls "C:/Users/aww/AppData/Roaming/CodeBuddy CN/logs/" | tail -5

# 搜索关键错误
grep -r "429\|insufficient_quota\|rpm\|tpm" \
  "C:/Users/aww/AppData/Roaming/CodeBuddy CN/logs/20261107T092533/" --include="*.log" | head -20
```

日志里能看到完整的请求 URL 和响应体：

```
[CustomFetch] custom model request failed with HTTP 429
url=https://token.sensenova.cn/v1/chat/completions
responseBody: {"error":{"message":"inference exceeds tpm/rpm limit","type":"rate_limit_error","code":"insufficient_quota"}}
```

### Step 2：用 curl 直接测试排除中间层干扰

```bash
# 测 deepseek-v4-flash（应该 429）
curl -s -w "\n%{http_code}" \
  -X POST "https://token.sensenova.cn/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-d***" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'
```

输出：
```
{"error":{"code":"","message":"inference exceeds tpm/rpm limit","type":"rate_limit_error","code":"insufficient_quota"}}
429
```

**结论：绕开 CodeBuddy 直接调 API，还是 429。确认是 Sensenova 平台的限制，不是 CodeBuddy 的问题。**

### Step 3：检查响应头确认是否走了代理

```bash
curl -v -X POST "https://token.sensenova.cn/v1/chat/completions" \
  -H "Authorization: Bearer sk-d***" \
  -d '{"model":"deepseek-v4-flash","messages":[...]}' 2>&1 | grep -E "^<"
```

正常 Sensenova 响应只有标准 header，没有 OneAPI 特有的 `x-oneapi-*` 系列。这证明是直接调用，不是经代理。

---

## 解决方案

### 临时方案：等 RPM 窗口重置

RPM 限制通常是按分钟计算的滑动窗口。等待 1-2 分钟后重试通常就能恢复。

可以在代码里加指数退避：

```python
import time

for attempt in range(5):
    try:
        response = call_api(...)
        break
    except RateLimitError:
        wait = min(60, 2 ** attempt)
        print(f"Rate limited, waiting {wait}s...")
        time.sleep(wait)
```

### 长期方案：升级配额或换 key

1. **登录 Sensenova 控制台**，查看具体账户的 RPM/TPM 上限（如果界面有显示的话）
2. **申请提额**：联系腾讯云客服，说明业务需求，申请提高 RPM/TPM 配额
3. **拆分 key**：如果两个 key 都在跑，考虑把请求分流到不同 key 上，避免单 key 打满限制
4. **换供应商**：如果这个限制严重影响业务，考虑切换到其他提供商（如 DeepSeek 官方、智谱官方等），它们的限额策略可能更宽松

---

## 一个意外的发现

在排查过程中还发现了一个有趣的现象：

**CodeBuddy 会在错误消息里脱敏 API key。**

日志里看到的是 `sk-H***8aG5`，实际 key 被部分隐藏了。这意味着：

1. 不能用日志里的 key 直接 curl 测试（会 401 Invalid token）
2. 需要手动从 `models.json` 里复制完整 key，或者重新生成一个新的测试 key

另外还发现一个 warning：

```
[CustomModelsProductProvider] user custom model id 'deepseek-v4-flash' 
conflicts with a built-in model; ambiguous bare-id migration prefers 
the built-in model — use a distinct id if the custom model should be 
migrated from legacy conversations
```

这意味着如果你同时在 `models.json` 里配置了自定义的 `deepseek-v4-flash`，又启用了内置的同名模型，CodeBuddy 可能会优先用内置的那个（走的可能是腾讯自己的通路，不是你配的 key）。

**修法**：给自定义模型起个不冲突的名字，比如 `custom-deepseek-v4-flash`，然后在 settings 里指定用这个名字。

---

## 总结

这次排查让我对云 API 服务有了更深的理解：

1. **控制台显示的余额 ≠ 没有限制**。很多平台把"余额充足"和"速率限制通过"分成两个独立的检查，前者在控制台可见，后者不可见。
2. **429 不一定意味着欠费**。看到 `insufficient_quota` 先别急着充值，先确认是余额不足还是 RPM/TPM 超限。
3. **用 curl 直接测试是排除问题的黄金标准**。绕过 IDE/框架的包装，直接调 API，能快速定位问题是在客户端还是在服务端。
4. **日志里的脱敏 key 不能直接用**。要测试得自己拿原始 key，或者生成新的测试 key。

---

## 参考

- Sensenova 控制台：https://console.sensenova.cn/
- CodeBuddy models.json 配置：`C:\Users\<username>\.codebuddy\models.json`
- CodeBuddy 日志目录：`C:\Users\<username>\AppData\Roaming\CodeBuddy CN\logs\`
