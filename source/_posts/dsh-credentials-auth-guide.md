---
title: dsh凭证注入与认证机制：密码、Key、Nginx 三层防护
date: 2026-09-10 10:00:00
permalink: /2026/09/10/dsh-credentials-auth-guide/
tags:
  - dsh
  - DeepSeek
  - 配置
  - 安全
  - Nginx
  - 教程
categories:
  - 技术随笔
---

# dsh凭证注入与认证机制：密码、Key、Nginx 三层防护

昨天修 dsh 图片输入报错的时候，顺带翻了一遍认证相关的代码。发现 dsh 的凭证管理其实有三层——**浏览器 Basic Auth**、**进程环境变量**、**本地配置文件**，每层各司其职。搞清楚了之后，整个 dsh 的安全边界就清晰了。

---

## 一、第一层：Nginx Basic Auth（外网访问网关）

dsh web 默认只监听 `127.0.0.1:3080`，不暴露到公网。公网访问必须经过 Nginx 反代，而 Nginx 配了 Basic Auth：

```nginx
server {
    listen 3081;
    server_name 43.153.148.187;

    auth_basic "dsh";
    auth_basic_user_file /www/server/panel/vhost/nginx/.htpasswd_dsh;

    location / {
        proxy_pass http://127.0.0.1:3080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

关键点：

1. **密码文件**：`/www/server/panel/vhost/nginx/.htpasswd_dsh`，用户名固定是 `dsh`，密码是 BT Panel 生成的 apr1 hash
2. **忘记密码怎么办**：重新生成 htpasswd 文件即可
   ```bash
   HASH=$(openssl passwd -apr1 "你的新密码")
   echo "dsh:${HASH}" > /www/server/panel/vhost/nginx/.htpasswd_dsh
   chmod 644 /www/server/panel/vhost/nginx/.htpasswd_dsh
   ```
3. **目录权限陷阱**：`/www/server/panel/vhost/nginx/` 默认是 700，nginx worker（www用户）无法读取。需要：
   ```bash
   chmod 711 /www/server/panel/vhost /www/server/panel/vhost/nginx
   ```
4. **crypto.randomUUID polyfill**：dsh 的前端用到了 `crypto.randomUUID()`，老版本浏览器不支持。Nginx 里配了一段 JS 注入：
   ```nginx
   location = /dsh-polyfill.js {
       default_type application/javascript;
       charset utf-8;
       return 200 'if(typeof crypto!==\"undefined\"&&!crypto.randomUUID){...}';
   }
   ```
   然后用 `sub_filter` 注入到所有 HTML 的 `</head>` 前面。

---

## 二、第二层：密码文件（dsh web 登录凭证）

Nginx 那层只是外网访问的门卫。dsh web 自己也有登录机制——存在 `/root/dsh-web-password.txt` 里：

```
yoy-3081!dsh
```

这个文件是什么？dsh 前端用这个用户名（`dsh`）+ 密码来构建 Basic Auth header，发给后端 API。我们的调试代码里就是这样用的：

```python
password = 'yoy-3081!dsh'
credentials = base64.b64encode(f'dsh:{password}'.encode()).decode()
req = urllib.request.Request(
    'http://127.0.0.1:3080/api/settings.describe',
    headers={'Authorization': f'Basic {credentials}'}
)
```

所以实际上有**两个密码**：
- Nginx 的 `.htpasswd_dsh`：拦的是 HTTP 层，没通过直接 401
- `/root/dsh-web-password.txt`：是 dsh 应用层认的，通过 Nginx 后还要对这个

两层密码可以不同，也可以相同。我的环境里恰好是一样的。

---

## 三、第三层：API Key 的环境变量注入

这是最关键的一层——dsh 怎么拿到 Sensenova / HCNSEC 的 API Key？

答案：**进程环境变量**，不是直接从配置文件读取。

### 配置文件里只写变量名

`/root/.dsh/settings.yaml` 里写的是：

```yaml
llm-pi-ai:
  providers:
    sense-nova:
      apiKeyEnv: SENSE_NOVA_API_KEY   # ← 只写变量名
      baseURL: https://token.sensenova.cn/v1
      ...
    hcnsec:
      apiKeyEnv: HCNSEC_API_KEY       # ← 只写变量名
      baseURL: https://api.hcnsec.cn/v1
      ...
```

注意是 `apiKeyEnv`，不是 `apiKey`。告诉 pi-ai："去环境变量里找这个 key"。

### 实际的 Key 存在哪里？

两个地方：

**1. 凭证文件**（供 dsh 启动时注入）

`/root/.dsh/.credentials.yaml`：
```yaml
version: 1
refs:
  DEEPSEEK_API_KEY: sk-hhh...7yYs
  SENSE_NOVA_API_KEY: sk-hhh...7yYs
  HCNSEC_API_KEY: sk-HcU...8aG5
```

**2. 进程环境**（实际运行时生效）

```bash
# 查看 dsh 进程的完整环境变量
cat /proc/$(pgrep -f 'dsh web' | head -1)/environ | tr '\0' '\n' | grep API_KEY
```

输出：
```
SENSENOVA_API_KEY=sk-hhh...7yYs
HCNSEC_API_KEY=sk-HcU...8aG5
```

注意：`SENSENOVA_API_KEY`（没有下划线）和 settings.yaml 里写的 `SENSE_NOVA_API_KEY`（有下划线）**不完全一致**。这说明 dsh 在启动时对环境变量名做了规范化处理——可能是去掉了下划线，或者两边都支持。

### 为什么不用明文写在 settings.yaml 里？

安全考量：
- settings.yaml 可能进了 git（虽然 .gitignore 通常排除，但有人忘加）
- 环境变量不在文件系统上，进程退出后就不存在
- 可以用容器、systemd EnvironmentFile、或者启动脚本控制注入时机

---

## 四、Hermes Agent 和 dsh 的 Key 是两套

这里容易混淆：

| | Hermes Agent | dsh |
|---|---|---|
| 配置文件 | `/root/.hermes/config.yaml` | `/root/.dsh/settings.yaml` |
| API Key 位置 | 直接写在 config 里 | 环境变量，从 .credentials.yaml 注入 |
| sensenova key | `sk-HcU...8aG5` (hcnsec provider) | `sk-hhh...7yYs` (sense-nova provider) |

两套 Key 不同，说明用了不同的账号或者不同的接入点。Hermes Agent 走的是 hcnsec 聚合代理，dsh 直接走 sensenova 官方接口。

---

## 五、启动参数里的 --trusted-host

```bash
nohup dsh web --no-open --host 127.0.0.1 --port 3080 \
  --trusted-host 43.153.148.187:3081 \
  --trusted-host 43.153.148.187 &
```

`--trusted-host` 的作用：告诉 dsh 哪些外部地址是可信的。这影响 WebSocket 连接和跨域策略。

如果不加这个参数，从公网 IP 访问时，前端会判定非回环地址，部分功能（比如 Settings 页面）会被禁用——这就是 skill 里提到的 "加载提供方目录失败" 问题。

---

## 六、完整的认证流程

用户从浏览器访问 `http://43.153.148.187:3081` 到发出第一个 API 请求，经历了这几步：

```
1. 浏览器输入 URL
   ↓
2. Nginx 拦截，返回 401 + WWW-Authenticate
   ↓
3. 浏览器弹出登录框，用户输入 dsh / yoy-3081!dsh
   ↓
4. Nginx 验证 .htpasswd_dsh，通过，转发到 127.0.0.1:3080
   ↓
5. dsh 前端用同样的凭据构建 Authorization header
   ↓
6. 前端请求 /api/settings.describe，携带 Basic Auth
   ↓
7. dsh 后端验证通过，返回 settings
   ↓
8. dsh 从环境变量读取 SENSE_NOVA_API_KEY / HCNSEC_API_KEY
   ↓
9. 实际调用 Sensenova API（带上自己的 Bearer Token）
```

每一层都在验证身份，但目的不同：
- Nginx Basic Auth：防止未授权访问（运维安全）
- dsh 应用层 Auth：标识当前用户（功能隔离）
- 环境变量里的 API Key：标识对上游模型的访问权（计费/配额）

---

## 七、常见问题排查

### 问题1：忘记 dsh web 密码

```bash
# 查看当前密码文件
cat /root/dsh-web-password.txt

# 重新设置（和应用层密码一致即可）
echo "新密码" > /root/dsh-web-password.txt
```

### 问题2：Nginx 401 怎么重置

```bash
# 生成新密码（会提示输入两次）
htpasswd -c /www/server/panel/vhost/nginx/.htpasswd_dsh dsh

# 如果没有 htpasswd 工具
HASH=$(openssl passwd -apr1 "你的密码")
echo "dsh:${HASH}" > /www/server/panel/vhost/nginx/.htpasswd_dsh
chmod 644 /www/server/panel/vhost/nginx/.htpasswd_dsh
```

### 问题3：API Key 失效了

```bash
# 1. 更新凭证文件
vim /root/.dsh/.credentials.yaml

# 2. 更新环境变量（重启 dsh 时自动注入）
# 不需要手动 export，dsh 启动时会读 .credentials.yaml

# 3. 重启 dsh
kill $(pgrep -f 'dsh web')
nohup dsh web --no-open --host 127.0.0.1 --port 3080 \
  --trusted-host 43.153.148.187:3081 &
```

---

**写在最后**

dsh 的安全设计是典型的"纵深防御"：Nginx 在外、应用 Auth 在中、API Key 在内。每一层解决不同维度的问题，组合起来既安全又灵活。

理解了这个分层，以后排查"认证相关"的问题就有方向了——先问自己：是哪个层面的认证出了问题？
