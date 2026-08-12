---
title: "把安卓平板变成 Linux 电脑：Termux、F-Droid 与 AVNC 的组合实践"
date: 2026-08-12 20:00:00
tags: [Linux, Android, Termux, 远程桌面, VNC, 折腾]
description: "不需要 root，不需要电脑，只需要 Termux、F-Droid 和 AVNC 三个开源软件，就能在安卓平板上跑起一个完整的 Linux 桌面。这篇是完整实践记录。"
---

## 一块平板，和它本该有的样子

我手边有一块安卓平板。它的日常用法很无聊——看视频、刷网页、偶尔写点笔记。但从技术上讲，这块平板里有颗 ARM 处理器、有 8GB 以上内存、有 GPU，性能不比一台入门的 Chromebook 差。它只是被安卓系统"封印"了。

怎么解封？

传统方案有两个方向。一是 root 之后刷 Linux 发行版，比如 Ubuntu Touch、PostmarketOS——这条路对绝大多数人来说太折腾，而且会让平板变砖的风险直线上升。二是用 UserLAnd、Linux Deploy 这类应用，它们要么收费，要么需要 root，要么把体验做得像个半成品。

第三条路是 F-Droid 生态里的一整套免费开源工具组合。它不需要 root，不需要刷机，甚至不需要连接电脑——你在平板上自己就能完成全部操作。

核心思路其实很简单：Termux 在安卓里跑一个 Linux 发行版，装一个桌面环境和 VNC 服务端，然后用 AVNC 这个 VNC 客户端连上去，就像远程桌面一样在平板上操作 Linux。

听起来绕了一圈，但绕的每一步都是开源的、可控的、免费的。

---

## 三个角色，各管一段

### Termux：安卓里的终端模拟器

Termux 不是普通的终端模拟器。它在安卓上跑了一个接近完整 Linux 的用户态环境，有自己的包管理器 `pkg`，可以安装 Python、Node.js、GCC、Vim 等各种工具。它的 GitHub 仓库有超过 15 万 star，是安卓上事实标准的开发者终端。

但你装个 Python、跑个脚本，那只是 Termux 基本能力的皮毛。真正让它变得有野心的是 **proot-distro**。

proot-distro 是一个由 Termux 官方维护的容器管理工具，GitHub 上 3.4k star，170 个版本标签，最近还在活跃更新。它做的事情是：在 Termux 里通过 proot（用户态 root）模拟一个完整的 Linux 发行版——Ubuntu、Debian、Alpine、Arch、Fedora 都能装。你可以在这个"容器"里 `apt install` 任何东西，包括图形桌面。

它的原理不是真正的容器（安卓没有 namespace 权限），而是用 proot 通过符号链接把 Android 的根文件系统映射到一个 Linux 发行版的根上，再用 userspace 的 libc 替代内核调用。所以它不是 Docker，也不是 chroot，而是一个巧妙的"假装自己是 Linux"的方案。

### F-Droid：不依赖 Google 的应用商店

F-Droid 前面刚介绍过——它是一个只分发自由开源软件的应用商店，从源码自己编译 APK，不需要 Google Play Services。Termux 和 AVNC 都上架在 F-Droid 里。

F-Droid 在这个方案里的角色其实很明确：提供不依赖 Google 生态的 Android 应用分发渠道。如果你用着一台去 G 版平板，或者干脆不想装 Google Play，F-Droid 就是唯一靠谱的获取 Termux 和 AVNC 的途径。

顺便说一句，官方建议用 F-Droid 而不是 Google Play 装 Termux，因为 Google Play 版本的 Termux 有权限和兼容性限制——它不允许使用 `termux-setup-storage` 访问外部存储，而 F-Droid 版本没有这个限制。

### AVNC：安卓上的 VNC 客户端

AVNC 是 F-Droid 生态里一个专门做 VNC 客户端的开源项目，Kotlin 编写，GPLv3 协议。它的特点是：本地渲染、支持 SSL/TLS 加密、针对触屏优化。

在这个方案里，AVNC 扮演的角色是"显示器"。Linux 桌面跑在 Termux 里，它通过 VNC 协议把画面输出到 AVNC 上，你用平板触屏操作 AVNC，AVNC 把操作指令通过 VNC 协议传回 Termux 里的 VNC 服务端。

---

## 整体架构

```
┌─────────────────────────────────────────────┐
│              安卓平板屏幕                     │
│                                             │
│   ┌──────────────┐                          │
│   │   AVNC       │  ← 触屏操作              │
│   │ (VNC 客户端) │                          │
│   └──────┬───────┘                          │
│          │ VNC 协议 (127.0.0.1:5901)        │
│   ┌──────▼───────┐                          │
│   │  TigerVNC    │  ← VNC 服务端            │
│   │  (vncserver) │                          │
│   └──────┬───────┘                          │
│          │                                  │
│   ┌──────▼───────┐                          │
│   │    XFCE4     │  ← Linux 桌面环境         │
│   │  (桌面系统)  │                          │
│   └──────┬───────┘                          │
│          │                                  │
│   ┌──────▼───────┐                          │
│   │   Ubuntu     │  ← proot-distro 容器      │
│   │  (Linux 内核)│                          │
│   └──────┬───────┘                          │
│          │ proot 用户态模拟                  │
│   ┌──────▼───────┐                          │
│   │   Termux     │  ← 安卓终端               │
│   └──────────────┘                          │
└─────────────────────────────────────────────┘
```

从下往上看：Termux 是底座，proot-distro 在上面跑 Ubuntu，Ubuntu 里装 XFCE 桌面和 TigerVNC，VNC 把画面通过 localhost 传给 AVNC，AVNC 在平板屏幕上渲染出来。

整个链条里，每一个环节都是开源软件，而且全部可以在 F-Droid 里下载到。

---

## 搭建步骤

以下命令都是在 Termux 里输入的。假设你已经通过 F-Droid 安装了 Termux 和 AVNC。

### 第一步：安装 Linux 发行版

```bash
# 更新包索引
pkg update && pkg upgrade -y

# 安装 proot-distro
pkg install proot-distro -y

# 安装 Ubuntu（也可以选 debian、arch、fedora）
proot-distro install ubuntu

# 进入 Ubuntu
proot-distro login ubuntu
```

执行最后一行后，你的提示符会变成 `root@ubuntu:~#`，说明你已经进入了 Ubuntu 环境。这里你就是一个完整的 root 用户，可以随便 `apt install`。

### 第二步：装桌面 + VNC 服务

```bash
# 更新
apt update && apt upgrade -y

# 装 XFCE4 桌面（轻量，ARM 设备够用）
apt install -y xfce4 xfce4-goodies

# 装 VNC 服务端
apt install -y tigervnc-standalone-server tigervnc-common

# 装常用工具（可选）
apt install -y firefox curl wget vim
```

### 第三步：配置 VNC

```bash
# 设置 VNC 连接密码
vncpasswd

# 编辑启动脚本
nano ~/.vnc/xstartup
```

`xstartup` 的内容替换为：

```bash
#!/bin/bash
xrdb $HOME/.Xresources
startxfce4 &
```

```bash
# 赋予执行权限
chmod +x ~/.vnc/xstartup

# 启动 VNC 服务，分辨率匹配你的平板
vncserver :1 -geometry 1280x800 -depth 24
```

这里的 `1280x800` 是个示例——你应该改成自己平板的横屏分辨率。如果分辨率不匹配，桌面显示会拉伸或错位，操作手感会大打折扣。

### 第四步：AVNC 连接

1. 打开 AVNC 应用
2. 添加新连接：
   - 地址填 `127.0.0.1`（localhost）
   - 端口填 `5901`
   - 密码填你刚才设置的 vncpasswd
3. 点连接

一个完整的 Linux 桌面应该出现在你面前。

---

## 桌面环境选择

不是所有桌面都适合在 ARM 平板上跑。这里做一个真实的对比。

| 桌面环境 | 内存占用（空载） | XFCE/LXDE 特性 | 适合场景 | 推荐度 |
|---------|----------------|---------------|---------|-------|
| XFCE4 | ~250MB | 轻量级，模块化，配置灵活 | 日常使用、开发 | ★★★★☆ |
| LXDE/LXQt | ~180MB | 最轻量，但 UI 较朴素 | 低配平板、纯终端辅助 | ★★★☆☆ |
| MATE | ~350MB | 仿 GNOME 2 风格，较成熟 | 习惯传统桌面布局的人 | ★★★☆☆ |
| GNOME | ~600MB+ | 现代化，但资源占用大 | 不推荐 | ★★☆☆☆ |
| KDE Plasma | ~500MB+ | 高度可定制，3D 特效多 | 不推荐 | ★★☆☆☆ |

我的建议是 XFCE4。它不是最轻的，但功能完整度、插件生态和 LXDE 比不是一个级别。在 8GB 内存的平板上，XFCE 占 250MB 几乎可以忽略不计。

如果你的平板内存只有 4GB 甚至更低，那就换 LXDE——把第二步的 `xfce4 xfce4-goodies` 换成 `lxde`，`xstartup` 里改成 `startlxde &`。

---

## 它能做什么

跑起来一个 Linux 桌面，到底有什么用？我想到了几个场景。

**写代码。** 在平板上打开 XFCE 终端，装好 Python、Node.js、Git，就能写代码。配合一款 SSH 客户端，你还可以直接连到服务器上写。虽然没有 IDE 那么舒服，但轻量开发场景完全够用。

**远程管理。** 你可以用这台"平板 Linux"做跳板，VNC 连到你自己 VPS 上的桌面环境。你的 VPS 上跑着真正的 GUI 应用——浏览器、Office、甚至 ComfyUI 的 Web UI——而平板只是作为一个远程显示器。这对经常在外跑的人来说，省了一台电脑。

**学习 Linux。** 对想学 Linux 但不想装双系统的人来说，这比虚拟机友好得多。直接在安卓里 `apt` 装东西、写 Shell 脚本、配置网络——坏了大不了重装 proot-distro，没有任何风险。

**开发调试。** Termux 本身就是一个强大的终端工具，配合 Linux 容器，你可以在平板上跑 Docker 替代品（proot 模拟的容器）、编译程序、跑测试。

---

## 真实的限制

这个方案听起来很美好，但有些问题你必须清楚。

**没有 GPU 加速。** proot-distro 运行在用户态，安卓的 GPU 驱动对它来说是不可见的。你在 Linux 桌面里跑不了 OpenGL 3D 渲染，没法编译需要 GPU 的程序，也没法在 Linux 里直接跑 ComfyUI。桌面本身没问题，因为 XFCE 用的是软件渲染，但任何依赖硬件加速的操作都会卡死。

**性能有损耗。** proot 的符号链接映射比原生 Linux 多了一层开销。`apt install` 比真机上慢，编译代码比真机上慢，大型软件启动时间也更长。但日常使用——装软件、跑脚本、写代码——损耗在可接受范围内。

**音频是黑洞。** 在 proot-distro 的 Linux 里配置音频输出到安卓系统，非常麻烦，几乎没有靠谱的现成方案。如果你需要在 Linux 里播放声音，基本只能靠 SSH 隧道转发到外部，或者干脆放弃。

**触屏手势不完美。** AVNC 把桌面映射到触屏上，但 Linux 桌面是为鼠标设计的。双指缩放、滑动切换应用这些手势在 XFCE 里不会原生生效。你需要在 AVNC 设置里调"触摸板模式"来模拟鼠标，习惯之后能接受，但永远比不上原生安卓的流畅。

**没有 Wayland。** VNC 走的是 X11 协议，Wayland 在这个方案里走不通。如果你未来想试试 Waydroid（在 Linux 里跑安卓应用），那就需要在另一个方向上折腾了。

**每次重启要手动启动。** 平板重启后，VNC 进程会死。你需要回到 Termux，重新 `proot-distro login ubuntu -- vncserver :1 -geometry 1280x800 -depth 24` 才能恢复。写一个 shell 脚本做启动入口可以缓解，但无法实现开机自启（安卓不让你这么做）。

---

## 和其他方案的对比

| 方案 | 需要 root | 收费 | 能跑桌面 | GPU 加速 | 复杂度 | 评价 |
|------|---------|------|---------|---------|-------|------|
| Termux + proot-distro + VNC | 否 | 否 | 是 | 否 | 中 | 本文方案，纯开源，够用 |
| UserLAnd | 否 | 免费+内购 | 是 | 否 | 低 | 界面友好，但有广告 |
| Linux Deploy | 是 | 否 | 是 | 部分 | 高 | 需要 root，不推荐 |
| Ubuntu Touch 刷机 | 否 | 否 | 是 | 部分 | 极高 | 有变砖风险，不建议普通人试 |
| Termux + Waydroid | 否 | 否 | 否（跑安卓应用） | 部分 | 高 | 用途不同，不冲突 |
| 云电脑（如 Parsec 云） | 否 | 是 | 是 | 是 | 低 | 依赖网络和订阅费 |

对比之后，Termux + proot-distro + VNC 的优势和劣势都很清晰：它是唯一一个不需要 root、不需要付费、完全开源的方案。代价是慢一点、没有 GPU、音频麻烦。

---

## 参考链接

- Termux GitHub: https://github.com/termux/termux-app
- proot-distro GitHub: https://github.com/termux/proot-distro
- AVNC GitHub: https://github.com/gujjwal00/avnc
- F-Droid: https://f-droid.org/
- TigerVNC: https://tigervnc.org/
- XFCE: https://www.xfce.org/

## 总结

这块安卓平板，本来只是一块娱乐设备。但用 Termux、proot-distro、AVNC 和 F-Droid 把它们串起来之后，它变成了一台完整的 Linux 电脑——虽然没有 GPU、没有音频、每次要手动启动，但装软件、写代码、远程管理服务器这些日常开发任务，它都能胜任。

最重要的是，整个方案不依赖任何付费服务，不需要 root，不需要风险，所有软件都可以从 F-Droid 下载到。这是 F-Droid 生态里少见的、把"自由软件"从口号变成真实可用的东西。

如果你想让一块闲置的安卓平板有第二个生命，这个方案值得一试。