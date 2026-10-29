---
title: Windows 下 Node.js 调 Python 发邮件，中文为什么时好时坏？
date: 2026-10-29 00:00:00
type: tech
permalink: /2026/10/29/windows-node-python-email-encoding/
tags:
  - Windows
  - Node.js
  - Python
  - Email
  - Encoding
description: 用 Node.js 做前端、Python smtplib 做邮件发送，中文内容时好时坏。排查发现是两条执行路径、两个 Content-Transfer-Encoding 头在作祟。
---

## 先说结论

Windows 下用 Node.js 调 Python 发中文邮件，**时好时坏**的根因有两个：

1. **参数传递路径不同**：Node.js `spawn` 传中文参数到 Python 时，Windows 默认 GBK 编码会把 UTF-8 字节序列搞坏；直接用命令行跑 Python 脚本没问题，走 API 就乱码。
2. **双重 Content-Transfer-Encoding 头**：`email.mime.text.MIMEText` 会自动加一个 `base64` CTE 头，如果代码里又手动设了一个 `quoted-printable`，一封邮件里就有两个冲突的编码头——邮件客户端按第一个解码，数据却是另一种编码，必然乱码。

这篇文章记录的是**真实排查过程**，不是理论推导。所有结论都有对应的代码和日志为证。

---

## 背景：我要做什么

需要给客户发送固定模板的邮件，操作飞书邮箱网页太麻烦。于是做了一个 Web 应用：

- 前端：React 18 + TypeScript + Vite，运行在 `localhost:5173`
- 后端：Node.js 24 + Express，运行在 `localhost:3001`
- 邮件发送：Python `smtplib`，通过 `child_process.spawn` 从 Node.js 调用

飞书 SMTP 配置：
- 服务器：`smtp.feishu.cn:465`（SSL）
- 发件人：`anweiwei@wonderable.ai`
- 收信测试：`17710717723@163.com`（163 邮箱）

---

## 第一阶段：nodemailer 碰壁

最初后端直接用 `nodemailer` 发信。问题很快出现：**163 邮箱收到中文乱码**。

尝试了多种 nodemailer 配置：
- `encoding: 'utf-8'`
- `charset: 'utf-8'`
- `textEncoding: 'base64'`
- `contentType: 'text/html; charset=utf-8'`

全部无效。截图验证显示：飞书系统邮件正常，但 Node.js 发的中文邮件乱码。

**转向 Python**。Python 的 `smtplib` + `email` 标准库对中文邮件支持更成熟，而且可以完全控制 MIME 结构。

---

## 第二阶段：发现两条路径，结果不一致

改用 Python 后，我遇到一个诡异现象：**同一份代码，同一个收件人，有时正常有时乱码**。

排查后发现，有两条不同的发送路径：

| 路径 | 触发方式 | 结果 |
|---|---|---|
| 终端手动运行 | 我在 bash 里直接跑 `python smtp.py` | ✅ 正常 |
| API 网页发送 | 用户在界面点发送 → Node.js spawn Python | ❌ 乱码 |

为什么同一份代码结果不同？

### 根因：Windows 下 spawn 的命令行编码

Node.js 的 `child_process.spawn` 在 Windows 上调用 Python 时，命令行参数使用系统的默认编码（GBK），而不是 UTF-8。

我的原始代码是这样传参的：

```javascript
// 错误写法：命令行参数经过 GBK 编码，UTF-8 中文被破坏
const proc = spawn('python', ['smtp.py', to, subject, body]);
```

当 `subject` 是 `"测试中文邮件"` 时，Node.js 把它当作 UTF-8 字节序列传给 Windows 命令行，Windows 用 GBK 解码，结果 Python 收到的是一堆乱码字节。

而我在终端手动运行 `python smtp.py "测试中文邮件"` 时，PowerShell/bash 的编码处理不同，参数能正确传递。

### 修复：用临时 JSON 文件传参

解决方案是绕过命令行参数，改用文件传递：

```javascript
// 正确写法：写临时 JSON 文件，Python 从文件读取
const tmpFile = path.resolve(__dirname, '../.hermes-tmp/email_params.json');
fs.writeFileSync(tmpFile, JSON.stringify({ to, subject, body }), 'utf-8');
const proc = spawn('C:/Users/aww/AppData/Local/Python/pythoncore-3.14-64/python.exe', 
  ['smtp.py', tmpFile]);
```

Python 端读取：

```python
# smtp.py
import json, sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    params = json.load(f)

to = params['to']
subject = params['subject']
body = params['body']
```

两条路径现在行为一致了——都走 UTF-8 JSON 文件，不再有命令行编码问题。

---

## 第三阶段：真正的 bug——双重 CTE 头

参数传递修好后，我以为是 Windows 编码问题的全部。但用户发来截图，证明还有问题。

用户指出了一个关键观察：**中间有几封是正常的，后面又乱了**。

这提示我：不是所有邮件都走同一条代码路径。我回顾了之前的修改历史，发现了另一处 bug。

### 问题：两个冲突的 Content-Transfer-Encoding 头

Python 的 `email.mime.text.MIMEText` 在创建时会**自动**设置 `Content-Transfer-Encoding: base64`（当内容包含非 ASCII 字符时）。

但我在代码里又手动加了一行：

```python
msg = MIMEText(body, 'plain', 'utf-8')
msg['Content-Transfer-Encoding'] = 'quoted-printable'  # ← 这行是多余的！
```

结果这封邮件的 MIME 头变成了：

```
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64          ← MIMEText 自动加的
Content-Transfer-Encoding: quoted-printable ← 我手动加的
```

**同一封邮件有两个 CTE 头。** RFC 5322 没有明确规定这种情况怎么处理，但主流邮件客户端的行为是：用第一个 CTE 头来解码正文。

于是：
- 实际正文是 quoted-printable 编码的
- 163 邮箱客户端用 base64 去解码
- 结果：乱码

而之前那几封正常的邮件，是因为它们发送时代码里还没有那行手动设置——`MIMEText` 自动选的 base64 是干净的，没有冲突。

### 修复：让 MIMEText 自己决定

```python
# 正确写法：不手动设 CTE，让 MIMEText 自动选择
msg = MIMEText(body, 'plain', 'utf-8')
# 不要加 msg['Content-Transfer-Encoding'] = ...
```

同时，发件人字段也要简化——带中文昵称的 `From` 头会导致飞书 SMTP 的 HELO 报头问题：

```python
# 错误：带中文名，HELO 可能出问题
msg['From'] = formataddr(('安伟伟', 'anweiwei@wonderable.ai'))

# 正确：裸邮箱地址
msg['From'] = 'anweiwei@wonderable.ai'
```

---

## 最终代码

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import smtplib
from email.mime.text import MIMEText
from email.header import Header
import json
import sys

def send_email(params_file):
    with open(params_file, 'r', encoding='utf-8') as f:
        params = json.load(f)
    
    to = params['to']
    subject = params['subject']
    body = params['body']
    
    msg = MIMEText(body, 'plain', 'utf-8')  # 自动选 CTE，不手动覆盖
    msg['From'] = 'anweiwei@wonderable.ai'   # 裸邮箱，不带中文昵称
    msg['To'] = to
    msg['Subject'] = Header(subject, 'utf-8')
    
    server = smtplib.SMTP_SSL('smtp.feishu.cn', 465)
    server.login('anweiwei@wonderable.ai', '<授权码>')
    server.sendmail('anweiwei@wonderable.ai', [to], msg.as_string())
    server.quit()
    return {'success': True}

if __name__ == '__main__':
    send_email(sys.argv[1])
```

Node.js 调用端：

```javascript
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

async function sendEmail(to, subject, body) {
  const tmpFile = path.resolve(__dirname, '../.hermes-tmp/email_params.json');
  fs.mkdirSync(path.dirname(tmpFile), { recursive: true });
  fs.writeFileSync(tmpFile, JSON.stringify({ to, subject, body }), 'utf-8');
  
  const proc = spawn(
    'C:/Users/aww/AppData/Local/Python/pythoncore-3.14-64/python.exe',
    [tmpFile]
  );
  
  return new Promise((resolve) => {
    proc.on('close', (code) => resolve({ success: code === 0 }));
  });
}
```

---

## 经验总结

| 问题 | 根因 | 解决 |
|---|---|---|
| 命令行传中文乱码 | Windows spawn 用 GBK 编码参数 | 改用临时 JSON 文件传参 |
| 时好时坏的乱码 | 双重 Content-Transfer-Encoding 头冲突 | 删除手动 CTE 设置，让 MIMEText 自动决定 |
| 飞书 SMTP 异常 | From 头含中文昵称 | 只用裸邮箱地址 |

**最关键的洞察**：`email.mime.text.MIMEText(body, 'plain', 'utf-8')` 已经帮你处理了编码和 CTE 选择。手动干预往往适得其反。

这个项目已推送到 [yoy-aww/mails-agent](https://github.com/yoy-aww/mails-agent)，代码包含完整的前后端实现和编码修复历史。
