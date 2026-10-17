---
title: Jev：当 AI 的输出直接是代码的值
date: 2026-10-17 10:00:00
type: tech
permalink: /2026/10/17/jev-typesafe-intro/
tags:
  - Jev
  - TypeSafe
  - System One
  - AI
  - 校准概率
categories:
  - 技术思考
---

## 先说结论

如果你需要 AI 做一个**你的代码会直接消费的判断**——不是给用户看的文字，而是给程序用的值——Jev 是目前最直接的方案。

**Jev 是 TypeSafe 的旗舰模型，也是第一个 System One 模型。** 它不生成文本：你给它一个"状态"（state）和若干带类型的"问题"（questions），它直接返回类型化值和概率分布，你的代码可以立刻对它做分支、排序、路由。没有文本生成，没有解析。

适合的场景：工单路由、内容分级、风控判断、多因子评分这类**判断明确、答案空间有限**的生产环节。不适合的场景：写文案、写代码、推理证明、开放式问答——这些仍然归传统 LLM 管。

## 错位：LLM 是给人读的

大语言模型的设计目标是**给人读的文字**。

一旦你想让它做一个判断、而判断结果要交给代码，就出现错位：你在把一个文本生成系统硬掰成结构化决策输出，然后还要把它的输出再解析回代码能依赖的东西。解析这一步永远不稳定——模型改个措辞、多吐一行解释，你的正则就炸了。

TypeSafe 的出发点是把这两件事拆开：

- LLM 负责"读起来舒服"；
- System One 模型负责"行为可预测"。

他们的判断是：大规模自动化未来约 99% 是机器对机器的交互，只有 1% 需要人。那设计目标就应该从"回复读起来好"转向"输出在软件里行为稳定"——这就是他们说的 **Machine Native Intelligence**：AI 具备软件的特性——结构化、可靠、可观测、可测试、快、一致、便宜。

名字里的"System One"来自卡尼曼《思考，快与慢》：System 1 是快直觉，System 2 是慢深思。System One 模型做的，就是给程序用的高速直觉判断。

## 三种基本问题：Choice / Score / Noul

Jev 能回答三种"带类型的问题"，官方称之为 primitives（原语）：

| 类型 | 问什么 | 返回什么 |
| --- | --- | --- |
| **Choice** | 从选项列表里选一个 | `choice`、`probabilities`、`confidence` |
| **Score** | 在评分量规上定位置 | `score`、`probabilities`、`confidence` |
| **Noul** | 这个陈述是真还是假 | `noul`（0–1 的概率） |

选型的经验法则是看**你的代码拿到答案后要干什么**：

- 答案是"已知选项集里挑一个"（工单分部门、文档分类、检测编程语言）→ **Choice**；
- 答案在一条尺度上（bug 严重度、客户愤怒程度、技能水平）→ **Score**，且各级含义由你定义；
- 干净的是/否，且概率本身就是信号（是否涉及退款、是否包含 PII）→ **Noul**。

两个类型都像是能对的时候，选那个答案能被你的代码直接接住的动作——一个 Choice 在 `refund` / `rebook` / `information` 之间，直接映射三条代码路径；一个 Score 映射一个阈值；一个 Noul 映射一个 `if`。

## 实际长什么样

TypeScript 示例（官方的工单路由用例）：

```ts
import { choice, noul, score, TypeSafeClient } from "@typesafe-ai/sdk";

const ticket = "Our API integration started returning 500 errors on every request about 20 minutes ago, and we can't process any customer orders until this is fixed.";

const client = new TypeSafeClient({ defaultModel: "jev-latest" }); // 读 TYPESAFE_API_KEY
const response = await client.systemOne({
  state: ticket,
  questions: {
    department: choice("Which team should handle this", {
      billing: "Payment or subscription issues",
      technical: "Bugs or integration problems",
      sales: "Pricing or account questions",
    }),
    frustration: score("How frustrated the customer appears", [
      "Calm, just stating facts",
      "Frustrated but civil",
      "Very angry, strong language",
    ]),
    is_urgent: noul("The message conveys urgency or time-sensitivity"),
  },
});

console.log(response.answers.department.choice);  // "technical"
console.log(response.answers.frustration.score);   // 0.67
console.log(response.answers.is_urgent.noul);      // 0.99
```

一次调用，三个问题，三种类型混着问。返回的每个答案都是**约束在你给的选项/等级空间里的值**——模型永远吐不出你列表之外的东西，代码不需要从散文里恢复任何值。

三个值得注意的细节：

1. **并行且互相隔离**。所有问题对同一个 state 独立评估，加问题几乎不增加响应时间，也不会产生"context 腐烂"（后一个问题被前一个污染）。
2. **TS SDK 有类型推导**。`response.answers.department.choice` 的静态类型就是 `"billing" | "technical" | "sales"`——类型安全一路带到分支逻辑里。
3. **Score 可以是量规中间的值**。官方示例里 frustration 返回 0.67，落在"冷静"和"礼貌但沮丧"之间——它给的是位置，不是档位。

不想写代码的话，官方有浏览器 Playground（console.typesafe.ai/playground）：贴一段文本，加几个问题，直接看答案。

## 原子问题，组合留给代码

这是 System One 最反直觉、也最核心的用法约束：

**每个问题只问一件事，且这件事是一个"懂行的人几秒钟内能下的判断"。**

"这条消息传达出紧迫感吗？"是好问题。"分析这条消息并确定最佳处理方案"是坏问题——它需要慢推理，信号在提示你：**拆开问**。

典型例子：与其问"给这个创业路演打分"，不如分开问市场空间、技术可行性、差异化，然后在代码里用你自己的公式加权。**优先级变了，你改的是代码里的一个系数，不是重写一段 prompt。** 每个单独判断保持可靠，权重组合方式始终在你手里。

## 置信度：让"我不确定"变成可用的信号

Choice 和 Score 的答案都带 `confidence`（0–1）：概率分布集中在一个选项上接近 1，摊平接近 0。官方给的工程用法是分三档：

- **高置信**：自动执行，不需要人；
- **中置信**：带谨慎地执行——请用户确认、标记复审、先补信息；
- **低置信**：不执行——转人工、追问澄清、换一套系统。

阈值不是全局一个数，而是**随风险变化**：同样是 0.75 的置信度，读余额可以直接放行，审批转账就该先找用户确认。你的代码编码的是风险容忍度，这是文档里我最喜欢的一句。

Noul 不带单独的 confidence——它本身就是"答 yes 的概率"，0.5 附近意味着模型自己也没把握。

## 它是怎么被训出来的：RLCD

背景补一句。预训练模型常见的两条后训练路线：RLHF（按人类偏好优化，训出聊天机器人）、RLVR（按可验证奖励优化，训出推理模型）。TypeSafe 走第三条：**RLCD（Reinforcement Learning for Calibrated Decisions）**——优化目标是"决策 + 校准概率"。

校准的含义（群体层面）：模型说 0.8 的那些答案，大致 80% 是对的；说 0.2 的，大致 20%。概率因此有了可计算的信任含义——这是它和"听起来很自信的文本"的本质区别。RLHF 会奖励讨喜的表达，校准概率奖励的是**可检验的不确定性**。

## 边界：它不做什么

- 目前**只接受文本输入**（字符串、JSON 对象、文本数组），图片、音频、视频暂不支持；
- 不写回复、不产出代码、不解释自己的推理——你的应用层负责"为什么这么判断"的呈现；
- 校准是群体性质，**不保证单个答案正确**——所以置信度分档门控不是可选项，是基本架构。

## 一个没回答的问题

这篇把"怎么用"讲清楚了，但没讲"什么时候值得用"。校准概率让"信任 AI 的判断"第一次有了可量化的形状，可"可信"的线画在哪里，取决于你的业务——判断错一次的成本是多少，你愿意为它付多少自动化。

这个判断，文档给不了。它是写代码的人的事。

---

*参考：[TypeSafe Introduction](https://docs.typesafe.ai/introduction)、[Quick Start](https://docs.typesafe.ai/introduction/quickstart)、[AI Primer](https://docs.typesafe.ai/introduction/machine-learning-primer)、[Primitives](https://docs.typesafe.ai/primitives)、[Confidence](https://docs.typesafe.ai/confidence)*
