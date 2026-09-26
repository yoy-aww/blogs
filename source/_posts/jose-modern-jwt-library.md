---
title: jose：现代 JWT 库到底好用在哪
date: 2026-09-26 11:00:00
type: tech
tags:
  - JWT
  - jose
  - Node.js
  - 安全
description: 从 jsonwebtoken 切到 jose 的几个真实理由：纯异步、零依赖、密钥轮换支持，以及一些容易忽略的坑。
---

## 先说结论

如果你今天要在 Node 18+ 上选一个 JWT 库，**我的答案是 jose**。理由有三条：

1. **纯异步，不阻塞事件循环**。`jsonwebtoken` 的 `jwt.sign()` 是同步的，在大量请求场景下会拖慢整个进程。`jose` 全异步。
2. **零运行时依赖**。`jose` 只用 Web Crypto API（浏览器和 Node 18+ 都有），不需要 native 模块、不需要编译。
3. **现代场景友好**。密钥轮换、JWK/JWKS 支持、ES256 等椭圆曲线算法，都是生产必需但 `jsonwebtoken` 支持得不好。

如果你的环境是 Node 14 及以下，或者你需要同步 API，那 `jsonwebtoken` 仍是合理选择。但 Node 18 已经 EOL 很久了，新项目应该用 jose。

## 为什么 jose 值得看一眼

JWT 在 Node 生态里老牌选手是 `jsonwebtoken`——文档多、Stack Overflow 答案多、用过的人多。但它有几个让人不太舒服的地方：

**同步签名**。`jwt.sign()` 是同步方法。在 Node 单线程模型下，任何同步的重计算都会卡事件循环。一秒 1000 个登录请求，每个签名 1ms，事件循环就被卡 1 秒——其他请求全排队。

**依赖 native 模块**。`jsonwebtoken` 底层用了 C++ 模块，部署时需要编译。在 Docker 镜像、CI、Serverless 环境里都会带来麻烦。

**JWKS 不支持**。生产系统经常需要密钥轮换和自动公钥分发，`jsonwebtoken` 对此支持有限。

`jose` 把这些都解决了——基于 Web Crypto API，纯 JS，全异步，原生支持 JWKS。名字也起得巧：`JOSE` 是 IETF 的 RFC 前缀（JSON Object Signing and Encryption），库名就是规范名。

## 安装

```bash
npm install jose
```

一个命令，没有依赖。`package.json` 里只多了一行。

## 快速上手

### 签发 token

```js
import { SignJWT } from 'jose';

const secret = new TextEncoder().encode('your-secret-key');

const token = await new SignJWT({ sub: 'alice', role: 'user' })
  .setProtectedHeader({ alg: 'HS256' })
  .setIssuedAt()
  .setExpirationTime('2h')
  .sign(secret);
```

注意是 `await`——**所有方法都是异步的**。这是 jose 的核心设计。

### 验证 token

```js
import { jwtVerify } from 'jose';

const { payload } = await jwtVerify(token, secret);
// payload = { sub: 'alice', role: 'user', iat: ..., exp: ... }
```

验证失败会抛异常，调用方用 `try/catch` 处理。

### 解码（不验证）

```js
import { decodeJwt } from 'jose';

const payload = decodeJwt(token);
```

`decodeJwt` 只是 Base64 解码，**不做签名验证**——别在生产环境用它当验证用。

## 为什么是全异步

这是 jose 最大的卖点，也是最容易被忽略的设计。

### 问题：同步签名会卡事件循环

Node 是单线程事件循环。任何同步的重计算都会卡住整个进程。`jsonwebtoken` 的 `jwt.sign()` 是同步的，在大量请求场景下：

```js
// jsonwebtoken（同步）
app.post('/login', (req, res) => {
  const token = jwt.sign(payload, secret, { expiresIn: '2h' });
  // 这一行虽然是"同步"，但实际会调用 native 模块
  // 在并发场景下可能阻塞事件循环
  res.json({ token });
});
```

如果一秒来 1000 个登录请求，每个签名要 1ms，那事件循环会被卡 1 秒——其他请求全排队。

### jose 的解决方案

```js
// jose（异步）
app.post('/login', async (req, res) => {
  const token = await new SignJWT(payload)
    .setExpirationTime('2h')
    .sign(secret);
  res.json({ token });
});
```

`await` 让出事件循环，其他请求可以并行处理。1000 个登录请求不会互相阻塞。

### 但 jose 也提供同步方法（慎用）

```js
import { SignJWT } from 'jose';

// 同步版本，仅在紧急场景用
const token = new SignJWT(payload)
  .setExpirationTime('2h')
  .signSync(secret);
```

`signSync` 和 `jwtVerify` 的同步版本是有的，但官方明确警告"会在事件循环里做同步计算，可能拖慢进程"。生产代码别用。

## 三种签名方式

jose 支持三种签发方式，分别用于不同场景。

### 1. 紧凑格式（默认）

```js
import { SignJWT } from 'jose';

const token = await new SignJWT({ sub: 'alice' })
  .setProtectedHeader({ alg: 'HS256' })
  .sign(secret);
// 输出：eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIi...
```

这就是我们熟悉的三段式 JWT。

### 2. JSON 序列化格式

```js
const token = await new SignJWT({ sub: 'alice' })
  .setProtectedHeader({ alg: 'HS256' })
  .signJSON(secret);
// 输出：{ "c2ct": "eyJhbG...", "p": "..." }
```

格式是人类可读的 JSON，便于日志打印。但体积更大，传输效率低。

### 3. 带额外签名的格式

```js
// 可以同时返回原始 token 和额外信息
const result = await new SignJWT({ sub: 'alice' })
  .setProtectedHeader({ alg: 'HS256' })
  .signWithSecret(secret, {
    additionalSignedHeaders: { kid: 'key-2026-01' }
  });
```

主要用于密钥轮换场景——在 header 里标记用了哪个密钥。

## 算法选择：HS256 还是 RS256

这是 jose 最容易讲错的地方。

### HS256：对称加密，教学和原型用

```js
import { SignJWT, jwtVerify } from 'jose';

const secret = new TextEncoder().encode('your-secret');

// 签发
const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'HS256' })
  .sign(secret);

// 验证
await jwtVerify(token, secret);
```

**同一个密钥**签发和验证。简单，但有一个致命问题：

> 任何拿到这个密钥的服务都能签 token。

如果 auth 服务和 hello 服务共享同一个密钥，hello 被攻陷 = auth 可以被伪造 token。在生产系统里这是不可接受的。

### RS256：非对称加密，生产推荐

```js
import { SignJWT, jwtVerify, exportKey } from 'jose';

// 生成密钥对
const { publicKey, privateKey } = await generateKeyPair('RS256');

// auth 服务用私钥签
const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'RS256' })
  .sign(privateKey);

// 其他服务用公钥验（公钥可以到处发）
await jwtVerify(token, publicKey);
```

**私钥只在 auth 服务里**，其他服务只拿公钥验证。即使 hello 被攻陷，攻击者也拿不到私钥，签不出有效 token。

### ES256：椭圆曲线，更快更短

```js
const { publicKey, privateKey } = await generateKeyPair('ES256');

const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'ES256' })
  .sign(privateKey);
```

签名比 RS256 短，速度快，是 WebAuthn 的标准算法。新项目推荐 ES256。

### 算法对比

| 算法 | 密钥类型 | 签名长度 | 速度 | 推荐场景 |
|------|----------|----------|------|----------|
| HS256 | 对称 | 32 字节 | 快 | 教学、原型、单服务 |
| RS256 | 非对称 | 256 字节 | 中 | 多服务、生产 |
| ES256 | 非对称 | 64 字节 | 快 | 新项目、移动端 |
| EdDSA | 非对称 | 64 字节 | 最快 | 高性能、WebAuthn |

**经验法则**：单服务/教学用 HS256，多服务生产用 RS256 或 ES256。

## 密钥管理：jose 的杀手特性

### 1. 从环境变量加载密钥

```js
import { importKey } from 'jose';

// 从 PEM 字符串加载 RSA 私钥
const privateKeyPem = process.env.JWT_PRIVATE_KEY;
const privateKey = await importKey(privateKeyPem, 'RS256');

// 从 Base64URL 加载对称密钥
const secretB64 = process.env.JWT_SECRET;
const secret = await importKey(
  new TextEncoder().encode(secretB64),
  'HS256'
);
```

### 2. JWKS（JSON Web Key Set）

这是 jose 最强大的特性之一。

**场景**：你有 10 个服务，每个都要验证 JWT。怎么把公钥分发给 10 个服务？

**JWKS 方案**：

```js
// auth 服务：暴露 JWKS 端点
app.get('/.well-known/jwks.json', async (req, res) => {
  const keys = await getPublicKeys();  // 你的密钥存储
  res.json({ keys });
});

// 其他服务：从 JWKS 端点拉公钥
import { createRemoteJWKSet, jwtVerify } from 'jose';

const JWKS = createRemoteJWKSet(new URL('https://auth.example.com/.well-known/jwks.json'));

app.use(async (req, res) => {
  const { payload } = await jwtVerify(req.token, JWKS);
  req.user = payload.sub;
});
```

**好处**：
- 公钥自动更新——auth 服务换了密钥，JWKS 端点返回新的
- 10 个服务不用手动同步密钥
- 标准协议（RFC 7517），所有 JWT 库都支持

### 3. 密钥轮换

生产系统需要定期换密钥。jose 支持多密钥验证：

```js
import { importKey } from 'jose';

// 同时支持新旧两个密钥
const currentKey = await importKey(process.env.CURRENT_KEY, 'RS256');
const previousKey = await importKey(process.env.PREVIOUS_KEY, 'RS256');

async function verifyWithRotation(token) {
  try {
    return await jwtVerify(token, currentKey);
  } catch {
    return await jwtVerify(token, previousKey);  // 旧 token 还能验
  }
}
```

更优雅的方案是用 JWKS——auth 服务在 JWKS 里同时返回新旧公钥，客户端自动按 `kid` 选择。

### 4. 用密钥标识符（kid）

```js
import { SignJWT } from 'jose';

const token = await new SignJWT(payload)
  .setProtectedHeader({ alg: 'ES256', kid: '2026-09' })
  .sign(privateKey);
```

`kid`（Key ID）告诉验证方"用哪个密钥验我"。JWKS 里每个密钥都有对应的 `kid`，验证方按 `kid` 找到对应公钥。

## 一个多服务场景

假设你在做一个多服务系统：

```
┌──────────┐    ┌──────────┐    ┌──────────┐
│  Web 端  │    │  iOS 端  │    │  Admin   │
└────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │               │
     └───────┬───────┴───────────────┘
             │
       ┌─────┴─────┐
       │   Auth    │  ← 唯一持有私钥
       │  Service  │
       └─────┬─────┘
             │
    ┌────────┼────────┐
    │        │        │
┌───┴───┐ ┌──┴───┐ ┌──┴───┐
│ User  │ │ Order│ │ Notify│  ← 都持有公钥
│ Svc   │ │ Svc  │ │ Svc   │
└───────┘ └──────┘ └──────┘
```

**部署步骤**：

1. **Auth 服务**生成 ES256 密钥对
2. Auth 服务把私钥存进 KMS（AWS Secrets Manager 等），永远不进代码
3. Auth 服务暴露 `/.well-known/jwks.json` 端点，返回公钥
4. User / Order / Notify 服务启动时拉 JWKS，缓存公钥
5. 客户端登录 Auth 拿到 token
6. 客户端调 User 服务，带 token
7. User 服务用缓存的公钥验 token，不需要问 Auth

**轮换密钥时**：

1. Auth 生成新密钥对
2. JWKS 端点同时返回新旧公钥（带不同 `kid`）
3. 客户端用新密钥签新 token
4. 旧 token 还能验（用旧公钥）
5. 旧 token 全部过期后，从 JWKS 移除旧公钥

**整个过程不影响任何客户端**——这是 JWKS + 密钥轮换的核心价值。

## jose 的常见坑

### 坑 1：把 decodeJwt 当验证用

```js
// ❌ 错误：decodeJwt 只做 Base64 解码，不验签名
const payload = decodeJwt(token);
if (payload.sub === 'alice') { /* 以为是验证通过 */ }

// ✅ 正确：jwtVerify 才验证签名和过期时间
await jwtVerify(token, secret);
```

`decodeJwt` 在调试时有用（看 token 内容），但**永远不要在生产代码里用它当验证**。

### 坑 2：忘记处理过期时间

```js
// ❌ 没设过期时间 = 永久凭证
const token = await new SignJWT(payload)
  .sign(secret);

// ✅ 必须设过期
const token = await new SignJWT(payload)
  .setExpirationTime('15m')
  .sign(secret);
```

JWT 一旦签发无法撤销，只能等过期。15 分钟 + refresh token 是常见方案。

### 坑 3：用 HS256 在生产

```js
// ❌ 多服务用 HS256 = 一个服务被攻陷全线崩
// auth 和 hello 共享 secret，hello 被攻陷后能伪造 token
```

生产系统用 RS256 或 ES256，私钥只在 auth 服务里。

### 坑 4：payload 里放敏感信息

```js
// ❌ payload 是 Base64 编码，不是加密
// 任何人都能解码看内容
const token = await new SignJWT({
  email: 'alice@example.com',
  ssn: '123-45-6789',  // 千万别放
  passwordHash: '...'  // 千万别放
}).sign(secret);

// ✅ 只放"本来就知道的"信息
const token = await new SignJWT({
  sub: 'alice',
  role: 'user'
}).sign(secret);
```

payload 是 **Base64 编码，不是加密**。任何人都能 `echo <token> | cut -d. -f2 | base64 -d` 看到内容。

### 坑 5：Node 版本太低

```
node -v
v16.20.0  ← jose 需要 v18+
```

jose 用了 `globalThis.crypto` 和 `Web Crypto API`，这些是 Node 18 才稳定的。Node 16 及以下会报 `crypto.subtle is not available`。

### 坑 6：忘记 await

```js
// ❌ jose 是异步的，不 await 会得到 Promise
const token = new SignJWT(payload).sign(secret);
// token 是 Promise，不是字符串
console.log(token);  // Promise { <pending> }

// ✅ 必须 await
const token = await new SignJWT(payload).sign(secret);
```

jose 的 API 设计很一致——所有加密操作都是 Promise。这是它和 `jsonwebtoken` 最大的差异，也是新手最容易踩的坑。

## 和 jsonwebtoken 对比

| 维度 | jose | jsonwebtoken |
|------|------|--------------|
| 同步/异步 | 全异步 | 同步为主 |
| 依赖 | 零依赖 | 依赖 `semver`、native 模块 |
| Node 要求 | v18+ | v0.10+ |
| 浏览器支持 | 是（基于 Web Crypto） | 部分（需要 polyfill） |
| RS256/ES256 | 原生支持 | 部分支持 |
| JWKS | 原生支持 | 不支持 |
| 密钥轮换 | 多密钥验证 | 手动处理 |
| 性能 | 异步，不阻塞 | 同步，可能阻塞 |
| 文档 | 新，但完整 | 老，多示例 |
| 社区 | 增长中 | 成熟 |

**什么时候选 jsonwebtoken**：
- 项目是 Node 14 及以下
- 需要同步 API（比如命令行工具）
- 团队已经熟悉，迁移成本大

**什么时候选 jose**：
- 新项目
- Node 18+
- 多服务架构
- 需要 JWKS / 密钥轮换
- 想要现代 API 设计

## 完整示例：多服务 JWT 认证

把上面的知识串起来，一个生产可用的最小实现。

### 密钥生成（一次性）

```js
// scripts/generate-keys.js
import { generateKeyPair, exportKey } from 'jose';
import { writeFile } from 'node:fs/promises';

const { publicKey, privateKey } = await generateKeyPair('ES256');

await writeFile('keys/public.pem', await exportKey(publicKey, 'spki', { format: 'pem' }));
await writeFile('keys/private.pem', await exportKey(privateKey, 'pkcs8', { format: 'pem' }));

console.log('密钥已生成');
```

### Auth 服务（签发 token）

```js
// auth/server.js
import { SignJWT, importKey, exportKey } from 'jose';
import { readFile } from 'node:fs/promises';
import express from 'express';

const app = express();
app.use(express.json());

const privateKeyPem = await readFile('keys/private.pem', 'utf8');
const privateKey = await importKey(privateKeyPem, 'ES256');

app.post('/login', async (req, res) => {
  const { username, password } = req.body;
  // ... 验证密码 ...

  const token = await new SignJWT({
    sub: username,
    role: 'user'
  })
    .setProtectedHeader({ alg: 'ES256', kid: '2026-09' })
    .setIssuedAt()
    .setExpirationTime('15m')
    .sign(privateKey);

  res.json({ token });
});

// 暴露 JWKS 端点
app.get('/.well-known/jwks.json', async (req, res) => {
  const publicKeyPem = await readFile('keys/public.pem', 'utf8');
  const publicKey = await importKey(publicKeyPem, 'ES256');
  const jwks = await exportKey(publicKey, 'jwk', { format: 'jwk' });
  res.json({ keys: [{ ...jwks, kid: '2026-09' }] });
});
```

### 业务服务（验证 token）

```js
// user/server.js
import { jwtVerify, createRemoteJWKSet } from 'jose';
import express from 'express';

const app = express();

const JWKS = createRemoteJWKSet(
  new URL('https://auth.example.com/.well-known/jwks.json')
);

app.use(async (req, res, next) => {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) return res.status(401).end();

  const token = auth.slice(7);
  try {
    const { payload } = await jwtVerify(token, JWKS);
    req.user = payload.sub;
    req.role = payload.role;
    next();
  } catch {
    res.status(401).end();
  }
});
```

### 客户端（调用业务服务）

```js
// client.js
const token = (await login('alice')).token;

const res = await fetch('https://user.example.com/profile', {
  headers: { 'Authorization': `Bearer ${token}` }
});
const profile = await res.json();
```

**整个流程**：
1. 客户端登录 auth 服务，拿到 ES256 签发的 token
2. 客户端调 user 服务，带 token
3. User 服务从 JWKS 拉公钥，验证 token
4. 验证通过，业务逻辑执行

**没有任何服务知道私钥**，除了 auth。其他服务只拿公钥。这是生产系统的标准模式。

## 还没讲的部分

JWT 只是认证的一半。还有几个话题这篇文章里没碰：

- **Refresh Token**：access token 15 分钟过期，怎么续期？
- **OAuth 2.0 / OIDC**：第三方登录怎么接入？
- **Session vs JWT**：什么时候用 session 反而更好？
- **密钥管理**：KMS、Vault、Age 这些工具实际怎么用？

这些我都还没真正跑通过。等你写完了再回过头看 jose，可能会发现"哦原来这个 API 是为了那个场景设计的"——这种"先有结论再补知识"的学习路径，我觉得挺有效的。

## 参考

- [jose GitHub](https://github.com/lucjan2/jose)
- [jose 文档](https://github.com/lucjan2/jose/blob/main/docs/README.md)
- [RFC 7519 - JSON Web Token](https://tools.ietf.org/html/rfc7519)
- [RFC 7517 - JSON Web Key](https://tools.ietf.org/html/rfc7517)
