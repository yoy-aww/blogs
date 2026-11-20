---
title: 在 Windows 上装 Label Studio，三个坑都不是你猜的那个
date: 2026-11-18 12:00:00
type: tech
tags:
  - Label Studio
  - Windows
  - conda
  - Django
  - 排错
categories:
  - 工程实践
---

最近在 Windows 上装 Label Studio（开源的标注工具）来做图片标注，本来以为 `pip install label-studio` 一把梭，结果前前后后踩了三个坑，每一个的根因都跟直觉不太一样。这篇记录一下，给要在 Windows 上装 Label Studio（或者其他 Django 系工具）的人省点时间。

## 坑一：conda create 一直卡在 "Retrying after connection broken"

第一步就卡住了。`conda create -n biaozhu python=3.8.5` 半天不动，日志里反复出现：

```
Retrying (Retry(total=2, connect=None, read=None, redirect=None, status=None)) after connection broken by 'ReadTimeoutError(... Read timed out. (read timeout=9.15))'
```

地址指向 `repo.anaconda.com`。我已经把 channel 配成了清华镜像（`mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main`），为什么还在访问 anaconda.com？

排查发现根因是 `.condarc` 的**叠加**行为：我的用户级 `C:\Users\aww\miniconda3\.condarc` 里单独配了一条 `- defaults`。conda 启动时会把所有层级的 channel 合并，`defaults` 这个特殊名字会展开成 `repo.anaconda.com`，跟清华镜像混在一起。清华源解析正常，但 `defaults` 那一路超时，整个命令就卡死。

修复就是把 `.condarc` 里的 `defaults` 去掉，只留清华镜像：

```yaml
channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free
show_channel_urls: true
```

改完 `conda create` 立刻正常走完。

**教训：conda 的 channel 是多层配置文件叠加的，`defaults` 是个会隐式展开的坑，光看当前生效的 `conda config --show channels` 不一定能发现哪层配置文件里埋着它。**

## 坑二：环境建好了，conda activate 却找不到

环境建好之后 `conda activate biaozhu` 报错：

```
EnvironmentNameNotFound: Could not find conda environment: biaozhu
```

但 `conda env list` 明明列出来了：`C:\Users\aww\miniconda3\envs\biaozhu`。

根因是这台机器上装了**两套 conda**：`anaconda3` 和 `miniconda3`。当前 shell 激活的是 `anaconda3` 的 base，而环境建在 `miniconda3\envs\biaozhu` 下。两个安装各自独立，`anaconda3` 根本看不到 `miniconda3` 里建的环境。

`conda env list` 会把两套都列出来，但 `activate` 只在自己那套里找，所以看起来"明明存在却激活不了"。

处理方式是统一到 miniconda3：确认 `anaconda3` 里只有 base 没有别的重要环境后，把它卸掉，让 PATH 里的 conda 指向 miniconda3。

**教训：一台机器两套 conda 是经典的"幽灵环境"来源。`conda env list` 列出的是所有安装的并集，`activate` 只在自己那套里搜，两者结论不一致时先怀疑是不是装了两套。**

## 坑三：服务起来就崩，根因是主机名里有中文

前面两个还算常规，这个最反直觉。

环境修好、`label-studio` 装上之后，一启动就报：

```
Current platform is win32, apply sqlite fix
Can't load sqlite3.dll from current directory
```

然后服务进程直接没了。查了一圈，最后定位到：这台 Windows 机器的**主机名是中文**「天下第一脑」。Python 3.8 在调用 `socket.getfqdn('0.0.0.0')` 时，对主机名做 UTF-8 解码，中文主机名触发解码错误，Django 初始化阶段直接崩溃。

验证：用 Python 查询 `socket.getfqdn()` 返回的是 `('天下第一脑', [], ['100.66.235.21', ...])`，`socket.getfqdn()` 拿到的 hostname 带中文。

修复不是去改主机名（改主机名要重启、影响面大），而是给启动加一层补丁：覆盖 `getfqdn` 让 `'0.0.0.0'` 返回 `'localhost'`，再用启动脚本设好 `HOSTNAME=localhost` 跑补丁后的入口。改完服务成功监听 `0.0.0.0:8080`，curl 返回 HTTP 302（正常跳登录页），进程稳定运行。

事后又查了一下，其实 Python 3.10+ 早就修了 socket 解码这个 bug——我那个 `biaozhu` 环境还是 Python 3.8（已经是 EOL），所以补丁只是绕行，**升级到 Python 3.11 才是治本方案**，顺便把 google-auth、cryptography 这些已经告警的旧依赖一起解决了。

**教训：中文主机名会让 Django 系的启动逻辑崩在 `socket.getfqdn()` 上。这个坑跟项目代码无关，是运行环境层面的——Windows 主机名用中文的人装 Django 应用时要先想到它。**

## 小结

三个坑，两个在 conda 的环境管理上，一个在 Windows 主机名上。共同点是：**报错信息都指向了一个"看起来没问题"的地方，真正的根因藏在更外层**。conda 报超时其实是配置文件叠加，activate 找不到其实是两套安装，Django 崩溃其实是主机名编码。排这类问题的通用做法是别只盯着报错那一行，往上看一层——看配置从哪来、环境在哪个安装下、机器名是什么。
