---
title: 我把 config.yaml 的默认模型改了，它纹丝不动
date: 2026-11-26 09:00:00
type: tech
permalink: /2026/11/26/config-default-is-factory-default-not-forced/
tags:
  - Hermes
  - 排障
  - 配置优先级
  - 反直觉
categories:
description: 改了 config.yaml 的 model.default，新会话却照旧用旧模型。顺着「设置存在哪」这条直觉白找了半小时，180 秒超时的 find、空手而归的 strings 都在里面。换个问题——不问「存在哪」，问「谁写的」——十分钟后在源码注释里拿到了真正的优先级链。
---

## 现象

我在 `config.yaml` 里写得很明确：

```yaml
model:
  default: agnes-2.5-flash
  provider: agnes
  base_url: https://apihub.agnes-ai.com/v1
```

然后我新开一个会话，发现跑的是 `sensenova-6.8-flash-lite`，provider 是 `custom`。

我改的是全局默认，它没听。

## 第一直觉：桌面端有隐藏设置文件

工具类应用改配置不生效，我第一反应是「肯定有另一个文件覆盖了它」。于是开始找桌面端的设置存储：

- `desktop/settings.json` → `NOT FOUND`
- `desktop.ini` → 是 Windows 文件夹属性文件，不是设置
- `projects.db` → 只有 `projects / project_folders / project_meta / discovered_repos` 四张表，跟模型无关
- Electron 的 `Local Storage/leveldb` → 里面就四个文件：`000005.ldb`、`026790.ldb`、`026792.ldb`、`026793.log`

我对那四个文件跑了 `strings` 再 grep 模型相关关键词，**空输出**。

顺带一提，中间有一条 `find "$HOME/AppData" -path "*hermes*" ...` 直接吃满了 180 秒超时被 kill。在 Windows 上对整个 `AppData` 做递归 find，基本是必炸的。

这一路找下来是**白找**。模型选择从头到尾就没存在 Electron 那侧。

## 换个问法：不问「存在哪」，问「谁写的」

卡住之后我把问题换了个方向。原来那个问题（覆盖配置存在哪个文件里）本质上是在猜实现，猜不中就是死路。

改成两个可以验证的动作：

**第一，找个对照组。** 我发现 cron 触发的会话用的确实是 `agnes-2.5-flash`——和 config.yaml 一致。这一条立刻排除了「config.yaml 写错了」和「provider 配置坏了」两种可能，把范围收窄到**只有桌面端会话被覆盖**。

**第二，直接查后端数据库。** `state.db` 的 `sessions` 表里有 `model` 和 `model_config` 两列，一列 session 一行记录。查了一下桌面端会话的分布：

| model | 会话数 |
| --- | --- |
| sensenova-6.8-flash-lite | 27 |
| agnes-3.0-flash | 9 |
| agnes-2.5-flash | 4 |
| qiniu/conatus-free | 2 |

四种加起来正好 42 个，27 个压在同一个模型上。最新的桌面会话 `model_config` 是 `{"model": "sensenova-6.8-flash-lite", "provider": "custom:huancheng-custom", ...}`。

也就是说：**它不是"被覆盖了"，是"被记住了"**。桌面端每次换模型，就把选择持久化进会话行，下次新会话接着用。

## 真相在源码注释里

去源码里找优先级规则，答案是一句现成的注释：

`model_switch.py:1191`

```
"""Resolve the effective model: session override > channel > global.
The single owner of the precedence rule ... A user-issued /model
(session override) always wins over per-channel/session-persisted
configuration, which wins over the global default."""
```

`api_server.py` 里那段更完整，它写的是：

```
# confirmed Browser model lock → session /model override →
# session-persisted model (POST /api/sessions {"model": ...}) →
# model_routes mapping ... → global
```

而 `models_dev.py:3503` 有一句我原本以为成立的话：

> `config.yaml model.default is the single source of truth for the active...`

这句话对一半。它是 source of truth，**但不是 forced**。前面还有三四层能赢过它。

顺带一个细节：`model_switch.py` 的注释里提到了 commit `7dd00bb47d`，说是为了收掉 gateway 和 api_server 各自独立实现一遍优先级规则造成的分叉。同一个规则写了两遍，最后必然不一致——这个我在自己项目里也踩过。

## 结论

**`config.yaml` 里的 `model.default` 是出厂默认，不是强制默认。**

它只在「你从来没手动选过模型」的时候生效。一旦你在 UI 上切过一次，那个选择就落在会话行上，之后每一次新会话都继承它——你的配置从那一刻起就只是个摆设，而且不会有任何提示。

排查这类「我改了配置但不生效」时，三个可复用的动作：

1. **先找对照组，别先找文件。** 找一个走默认路径的同类实例（这里是 cron 会话），确认你的配置本身是对的，再把范围收窄到"谁在覆盖"。
2. **别顺着"设置存在哪"猜。** 在配置系统复杂的应用里，覆盖项往往不在你猜的那个文件里。改成问"谁写的"——直接去看持久化层。
3. **优先级规则去源码注释里找，别自己拼。** 我花了半小时猜，一句 docstring 十秒讲完。

---

*附：这次白找的成本不小——`find` 吃满 180 秒超时，`strings` 空跑四轮。回头看，真正省时间的不是找到 leveldb，是我放弃"它在某个文件里"这个假设。*
