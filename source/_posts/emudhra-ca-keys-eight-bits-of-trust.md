---
title: eMudhra 的 8 个 CA 私钥其实是数字 4、56、115：八位信任是怎么失守的
date: 2026-10-19 17:00:00
type: tech
permalink: /2026/10/19/emudhra-ca-keys-eight-bits-of-trust/
tags:
  - 证书颁发机构
  - PKI
  - 椭圆曲线
  - TLS
  - 安全事件
categories:
  - 技术思考
description: eMudhra 的 8 个中间证书私钥都是个位数或两位数（4、56、115、155、156、230、237、66），任何人从公开证书上几毫秒就能复原。事件曝光了非浏览器 TLS 客户端生态的真实脆弱性。
---

## 先说结论

eMudhra 这家 CA 的 8 个中间证书，私钥其实是 **4、56、115、155、156、230、237、66**——都是单个字节能装下的数。从公开证书反推这些私钥，最多试 255 次点乘就够，任何一台笔记本毫秒级就能完成。

这件事 2026 年 10 月 17 日被报告，10 月 20 日 Mozilla 公开公告。从 2025 年 4 月证书创建到 2026 年 10 月被披露，**整整 17 个月里这些"私钥"实际上是公开的**——任何看过这些证书的人，都可能在毫秒级复原出来。我们不知道有没有人做了。

主流浏览器（Chrome / Firefox / Safari）已经更新根证书存储，**风险可控**。但所有不更新根证书存储、不检查 CT 日志、不默认检查吊销的 TLS 客户端——curl、Python、Node、Go、Java、git、包管理器、CI/CD 流水线、IoT 设备、Windows 代码签名链——**今天仍然是脆弱的**。

这篇文章所有内容都来自 Scott Helme 2026 年 10 月 19 日的原博文（[原文链接](https://scotthelme.co.uk/eight-bits-of-trust-emudhras-ca-keys-cracked-in-milliseconds/)），以及 Mozilla 10 月 20 日公开的事故工单。我的延伸分析会在每一处明确标注。

## 事情是怎么发生的

按原文时间线：

| 日期 | 事件 |
|---|---|
| 2025 年 4 月 | eMudhra 创建了这 8 个中间 CA（6 个 TLS 签发 + 2 个代码签名），私钥是单字节弱值 |
| 2025 年 5 月 | 全部 8 个中间证书被 Sectigo 的 `AAA Certificate Services` 根交叉签名 |
| 2026 年 10 月 17 日（周六） | 一名安全研究人员向 Apple / Google / Microsoft / Mozilla / eMudhra 报告了 8 个中间证书的私钥泄露 |
| 2026 年 10 月 17 日当晚 | Chrome 推送 CRLSet 更新，阻止这些证书 |
| 2026 年 10 月 17 日晚几小时后 | Mozilla 通过 OneCRL 在 Firefox 里阻止 |
| 2026 年 10 月 20 日（周二） | Mozilla 公开公告，发布 NSS 更新移除 eMudhra 根；Chrome 确认根会进 Root Store v43 |
| 2026 年 10 月 20 日 20:16 UTC | Mozilla 公开事故工单（bugzilla.mozilla.org/show_bug.cgi?id=2083449），eMudhra 在工单里给出了自己的说明 |

**8 个中间证书的构成**：

- 6 个 TLS 签发 CA（DV / OV / EV 三类，每类两代）
- 2 个代码签名 CA

所有 8 个都用 P-384 椭圆曲线。

## 椭圆曲线的私钥到底是什么

这部分是理解整个事件的数学基础，原文写得很清楚。

椭圆曲线（这里用 P-384）有这样一个固定点 G，是所有人都知道的"起点"。私钥是一个数 `d`，公钥是 `d × G`（这里的 `×` 是曲线上特殊的点乘运算，相当于把 G 加自己 d 次）。

```
私钥：d        （一个数）
公钥：d × G    （曲线上的一个点）
```

**正向**：拿到 d，算 d × G 很简单。

**反向**：拿到公钥 d × G，反推出 d——这是"椭圆曲线离散对数问题"（ECDLP），被认为是计算上不可行的。整个 ECC 的安全模型就建立在这一假设上。

但有一个前提：**d 必须足够大**。P-384 的私钥应该是一个随机的 384 位数，对应 2³⁸⁴ ≈ 10¹¹⁵ 种可能。没人会去 brute force 这么多。

## eMudhra 的私钥长这样

eMudhra 的 8 个私钥：

```
d = 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004
```

47 个 0 字节，最后一字节是 `0x04`。也就是十进制的 **4**。

一个正常的 P-384 私钥应该长这样：

```
d = 0x48ac06790886c80c48d31691fd4c0fe9ce3207f9807f2fe571d6e4ec426d78644298fc53df2b92566970e757ac998c34
```

**47 字节的随机数，每一位都是 0~255**。

eMudhra 的私钥**只有最后一字节有值**，前面全是 0。8 个证书的私钥都是这种结构。

Ian Carroll 在 MDSP 讨论串里用一句话概括了问题：

> They are inherently weak single-byte keys that anyone can factor, and the issue cannot be contained.
> （它们本质上是单字节弱密钥，任何人都能分解出来，而且这个问题无法被遏制。）

## Scott 是怎么验证的

Mozilla 在公告里附上了受影响的证书，Scott 把全部 16 个证书（8 把密钥，每把在两个签发的证书里各出现一次：一次是 eMudhra 签的，一次是 Sectigo 交叉签的）都拉下来做了 brute force。

暴力破解就是：从 `1 × G` 算到 `2 × G`、`3 × G`……跟证书里的公钥比对，匹配就找到 d 了。最多 255 步，秒级完成。

**全部 8 个都被立刻破解**，包括 6 个 TLS 和 2 个代码签名：

| 中间 CA | 类型 | 私钥 d |
|---|---|---|
| EM DV TLS CA - G3B | TLS | 156 |
| EM DV TLS CA - G3C | TLS | 230 |
| EM EV TLS CA - G3B | TLS | 115 |
| EM EV TLS CA - G3C | TLS | 56 |
| EM OV TLS CA - G3B | TLS | 155 |
| EM OV TLS CA - G3C | TLS | 4 |
| EM OV CS CA - G3B | 代码签名 | 66 |
| EM OV CS CA - G3C | 代码签名 | 237 |

**一个让人脊背发凉的事实**：`d = 4` 算出来的公钥，在 P-384 曲线上是一个完全合法的点。编码没问题，曲线没问题，所有结构性检查都通过。**唯一能发现它有问题的方式，就是去试**。

> 我的延伸分析：传统 CA 审计只查"证书结构合不合法"，不查"私钥大不大"——因为按规范 d 一定是 384 位随机数。当 d 实际上是个位/两位数时，所有结构检查都是绿灯。这类问题只能靠"对每个公开 CA 都做 brute force 试一下"来发现，而这显然不在常规审计里。

## 为什么"无法被遏制"

通常 CA 密钥泄露意味着有贼——有一个具体的"被偷的瞬间"，你可以追溯谁在那之后拿到了密钥。

这次不一样。**没有人偷任何东西**。从证书存在的当天（2025 年 4 月）开始，私钥实际上就是公开的——任何拿到证书的人，都能用毫秒级算力复原出来。

这是个 **17 个月的窗口**，没有任何办法知道期间是否有人利用了它。

Chrome 这边的解释是：因为 Chrome 强制 Certificate Transparency（CT 日志），而这些 CA 签发的任何 TLS 证书都没出现在 CT 日志里，所以 Chrome 用户没受影响。**这是真的**——CT 是浏览器防伪造的最后一道闸。

但 CT **检测到**了不等于**预防**到了。CT 是被动审计，不是主动阻止。而且很多软件根本不检查 CT。

## 谁今天仍然暴露

主流浏览器都更新了根证书存储，加上 CT 强制，基本安全：

- Chrome：CRLSet 阻止 + CT 强制
- Firefox：OneCRL 阻止 + CT 强制
- Safari：CT 强制

**其他所有东西都是另一个故事**。原文列举的关键风险：

### 1. curl | sh 安装器和自更新脚本

很多工具的安装和更新是通过 HTTPS 下载脚本或二进制，**不做签名校验**——rustup、nvm、Homebrew installer、各种 `install.sh` 页面、IoT 固件更新器。伪造一个这样的证书，等于让攻击者的代码以 root 身份运行。

### 2. CI/CD 流水线

GitHub Actions / GitLab Runner / Jenkins / 构建容器——它们下载依赖、推送构建产物，手上持有云密钥、镜像仓库 token、签名密钥。底层全是 curl、Python、Go、Node。基础镜像更新滞后，跑在共享网络上。

### 3. 服务端到服务端 API 调用

支付接口、Webhook、OAuth token 交换、云 SDK（AWS CLI 和 boto 用 certifi 包，Terraform 和 kubectl 用 Go 的内置 bundle）。**这些请求的 header 里带着 API 密钥和用户数据**。

### 4. IoT、嵌入式和 OT 设备

摄像头、路由器、汽车、医疗设备、智能家居、POS 终端、工业控制器——它们定期回家汇报数据和领更新。它们的 CA bundle **冻结到 2039 年**。

### 5. Windows 代码签名

这个不是 TLS，但同样的漏洞——Windows 直接信任 eMudhra 的代码签名根。用 `EM OV CS CA - G3B/G3C` 签的恶意软件，在不检查吊销的任何客户端看来都是"来自合法发布者的已签名软件"。

## Scott 在自己机器上的实测

他用一个本地服务器 + 一张伪造的 `api.stripe.com` 证书做了测试（选择这个域名是因为"所有人都同意它是高价值目标"）：

```
scott@Middle-Earth:~$ curl -v --resolve api.stripe.com:18888:127.0.0.1 https://api.stripe.com:18888/
...
* Server certificate:
*  subject: CN=api.stripe.com
*  start date: Oct 20 18:39:57 2026 GMT
*  expire date: Oct 21 18:44:57 2026 GMT
*  subjectAltName: host "api.stripe.com" matched cert's "api.stripe.com"
*  issuer: C=NL; O=eMudhra BV; CN=EM DV TLS CA - G3B
*  SSL certificate verify ok.
```

**默认配置下，curl 说 `SSL certificate verify ok`**——一张伪造的 `api.stripe.com` 证书，被本地 curl 当成了合法证书。

原文报告的测试结论：

- curl（默认配置）：`SSL certificate verify ok`
- Python：握手成功
- Node：`authorized: true`
- 所有 Linux 和 macOS 测试机都通过
- Windows：CryptoAPI 接受证书链，**除非手动开启吊销检查**；而且即使开启了，也只有一条路径被标记为吊销

> 我的延伸分析：测试里"吊销检查只能查到一条路径"是个细节但很致命——eMudhra 自己撤销了，Sectigo 也撤销了，两条路径理论上都应该被查到。如果客户端只查到一条，等于把"双重保险"用成了"单一保险"。

## 现在应该做什么

原文的官方建议（针对能更新的设备）：

1. **更新所有内置 CA bundle 的软件**：操作系统的 `ca-certificates` 包、certifi、Node、Homebrew，基础镜像更新后重建容器镜像
2. **不能更新或难更新的设备**是真正的麻烦——路由器、打印机、电视、固件冻结的智能家电——它们会**信任这些证书到 2039 年 7 月**到期

## 事故根因

10 月 20 日 Mozilla 把事故工单公开了。eMudhra 在工单里给出的说明是：

> It seems there was a bug in the script used during the ceremony, a second, weak key pair was created on the HSM, and having similar names a human error lead to the wrong keys being used for the CSR.

**大致翻译**：仪式用的脚本有 bug，HSM（硬件安全模块）上生成了一对弱密钥，但因为命名相似，人工错误导致 CSR 用了错的密钥对。

Scott 强调"这篇文章里的所有内容因为这条新信息都没有改动"——无论根因是脚本 bug、HSM 配置、还是人工错误，结果是一样的：8 把单字节私钥的证书，公开了 17 个月。

**另一条值得注意的信息**：Scott 确认了用一段简单 prompt 就能让 AI agent 复原这些 CA 的私钥——"Claude 用单条 prompt 就能复原"。

> 我的延伸分析：这条信息把"任何看过这些证书的人都能复原私钥"从一个数学论断变成了一个工程论断——AI agent 已经把"看到证书 → 写 brute force → 跑出来"这条链路缩到了一次对话。这把攻击门槛又降了一级。

## 这件事的教训

**第一，结构检查不替代强度检查**。所有证书结构检查都通过——因为规范默认 d 一定是 384 位。当 d 实际上是个位数时，结构性检查毫无作用。要防止这种错误，CA 在签发前必须做私钥强度校验（比如检查 d 的二进制长度）。

**第二，CT 日志是浏览器端的最后一道防线，但不是所有客户端的**。对 Chrome / Firefox / Safari 用户而言，CT 让这次事件基本无害。但对所有不查 CT 的客户端而言，CT 不存在。

**第三，吊销检查的覆盖率是个盲点**。原文测试显示 Windows 即使开启了吊销检查，也只查到一条路径。这意味着"双重撤销"实际只兑现了一次。

**第四，17 个月窗口期的不可追溯性**。CA 密钥泄露的标准剧本是"被偷了 → 找谁拿的"。这次没人偷，密钥从公开那天起就是公开的。我们永远不知道谁拿走了它。

**第五，整个生态对 CA 证书的盲目信任**——尤其是非浏览器客户端——比想象中更危险。CI/CD 流水线带着云密钥、API 密钥、签名密钥，跑在冻结的 CA bundle 上，连个吊销检查都没有。这是 PKI 生态里一个长期存在但很少被讨论的盲点。

## 一句话总结

eMudhra 的 8 个中间证书私钥是 4、56、115、155、156、230、237、66——每个都装得下一个字节，任何人毫秒级能复原。17 个月窗口里没人知道谁用了它。浏览器靠 CRLSet + CT 挡掉了，其他所有 TLS 客户端——CI/CD、API 调用、IoT、Windows 代码签名——今天还在裸奔。**八位信任。17 个月。这是整个非浏览器 PKI 生态脆弱性的集中暴露**。

---

**来源**：
- 原文：Scott Helme, [Eight Bits of Trust; eMudhra's CA keys cracked in milliseconds](https://scotthelme.co.uk/eight-bits-of-trust-emudhras-ca-keys-cracked-in-milliseconds/), 20 Oct 2026
- Mozilla 公告：[MDSP thread](https://groups.google.com/a/mozilla.org/g/dev-security-policy/c/0R3XLJL6FuE/m/Kp1v6CPuAAAJ)
- Mozilla 事故工单：[bugzilla.mozilla.org/show_bug.cgi?id=2083449](https://bugzilla.mozilla.org/show_bug.cgi?id=2083449)
- 研究公告：[emudhra.we-have-a-problem.com](https://emudhra.we-have-a-problem.com/)

> 声明：本文为基于 Scott Helme 原博文的中文翻译与解读，所有事实性内容来自原文，我的延伸分析（标注为"我的延伸分析"）属于个人判断，可能与原文观点不同。
