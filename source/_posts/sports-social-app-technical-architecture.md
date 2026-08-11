---
title: 运动社交 App 技术选型方案
date: 2026-08-07 16:00:00
tags:
  - 创业
  - 技术架构
  - 选型
  - 开发
  - 系统设计
  - 运动社交
categories:
  - 技术分享
---

上一篇把功能拆清楚了。这一篇说技术——用什么堆出来，怎么部署，成本多少。

如果你不是开发者，可以跳着看，重点看"为什么这么选"和"要花多少钱"。

## 一、整体技术栈决策

这个产品不是高并发、高实时性产品。它的特征：

- **用户量级**：MVP 阶段 1000-5000 活跃用户
- **并发特征**：组局时间集中在下午/晚上/周末，非 7×24 小时
- **实时需求**：低（通知用推送，不需要 WebSocket 级别实时）
- **图片/视频**：有（活动照片、头像），但不是核心流量
- **地理位置**：有，但不需要高频更新

基于这些特征，技术选型的优先原则是：**简单 > 先进**，**省钱 > 炫酷**，**好维护 > 高性能**。

最终选型如下：

| 层级 | 选型 | 理由 |
|------|------|------|
| 前端 | React Native（Expo） | 跨平台一套代码，个人开发友好 |
| 后端 | Node.js + Express + Prisma | 全栈 JS，你一个人写起来不累 |
| 数据库 | PostgreSQL | 关系型，支持地理查询（PostGIS） |
| 缓存 | Redis | 缓存组局列表、用户信息 |
| 对象存储 | 阿里云 OSS / 腾讯云 COS | 存头像、活动照片 |
| 推送 | 微信消息推送 + 短信 | App 推送需要推送服务 |
| 部署 | 阿里云 ECS + Nginx | 便宜，够用 |
| 地图 | 腾讯位置服务 | 国内最准的地图 API |
| 支付 | 微信 Native 支付 | 不碰，MVP 阶段不碰支付 |

## 二、前端方案详解

### 为什么是 React Native + Expo

三个原因：

**原因一：一套代码两个平台**

你一个人开发，不可能同时维护 iOS 和 Android 两个代码库。React Native 写一套，两端都能跑。

**原因二：Expo 降低开发门槛**

Expo 是 React Native 的"零配置方案"。不需要配 Xcode，不需要配 Android Studio 签名证书。你写完代码，Expo 帮你打包、发 TestFlight、发 Google Play。

个人开发者如果没有 Mac 电脑，Expo 甚至可以通过 Web 端预览效果。

**原因三：开发效率高**

热更新（Hot Reloading）让你改了代码不用重新编译，马上在手机上看到效果。这对于快速迭代 MVP 至关重要。

### Expo 的局限性

也要说清楚 Expo 的缺点：

- 一些系统级 API（比如 NFC、蓝牙）在 Expo 中可能受限
- 包体积比原生大
- 某些性能敏感场景（比如 60fps 长列表）可能需要 Native Modules

但这个产品的核心功能是"列表浏览 + 表单填写 + 地图展示"，没有性能敏感的场景。Expo 完全够用。

### 前端架构

```
src/
├── screens/             # 页面
│   ├── HomeScreen.js    # 组局列表
│   ├── ActivityDetailScreen.js  # 组局详情
│   ├── CreateActivityScreen.js  # 发起组局
│   ├── ProfileScreen.js # 个人主页
│   ├── ActivityListScreen.js    # 我的活动
│   └── EditProfileScreen.js     # 编辑资料
├── components/          # 组件
│   ├── ActivityCard.js  # 组局卡片
│   ├── SportBadge.js    # 运动标签
│   ├── MapView.js       # 地图组件
│   └── RatingStars.js   # 评分组件
├── services/            # API 调用
│   └── api.js
├── navigation/          # 路由
└── utils/               # 工具函数
```

关键库：

| 库 | 用途 |
|------|------|
| @react-navigation/native | 路由导航 |
| expo-location | 地理位置 |
| expo-image-picker | 头像/照片上传 |
| expo-contacts | 读取通讯录（选） |
| react-native-maps | 地图展示 |
| react-native-paper | UI 组件库 |
| dayjs | 时间处理 |
| zustand | 状态管理（比 Redux 简单） |

## 三、后端方案详解

### 为什么是 Node.js + Express + Prisma

**Node.js**：前后端都用 JavaScript，不用切换语言。一个人做全栈最舒服。

**Express**：轻量，学习曲线短，MVP 够用。不上 Next.js/Nest.js，因为那些框架的复杂度对 MVP 是浪费。

**Prisma**：TypeScript ORM，自动做类型推导。写 SQL 是痛苦的，写 Prisma 是愉快的。

### 后端架构

```
server/
├── src/
│   ├── routes/          # 路由
│   │   ├── activities.js
│   │   ├── users.js
│   │   ├── apply.js
│   │   └── reviews.js
│   ├── controllers/     # 业务逻辑
│   ├── services/        # 服务层
│   ├── middleware/      # 中间件
│   │   ├── auth.js      # 登录验证
│   │   └── validate.js  # 参数校验
│   ├── prisma/          # 数据库模型
│   │   └── schema.prisma
│   └── index.js         # 入口
├── .env                 # 环境变量
└── package.json
```

### 核心 API 设计

```
POST   /api/auth/login          # 短信验证码登录
POST   /api/auth/verify         # 验证验证码
GET    /api/me                  # 获取当前用户信息
PUT    /api/me                  # 更新个人信息
POST   /api/me/verify-id        # 提交身份证认证

GET    /api/activities          # 获取附近组局列表
POST   /api/activities          # 创建组局
GET    /api/activities/:id      # 组局详情
PUT    /api/activities/:id      # 更新组局
DELETE /api/activities/:id      # 取消组局
POST   /api/activities/:id/checkin  # 组织者签到

POST   /api/activities/:id/apply    # 报名
DELETE /api/activities/:id/apply    # 取消报名
GET    /api/me/activities           # 我的活动

POST   /api/activities/:id/reviews  # 提交评价
GET    /api/users/:id/reviews       # 用户评价列表

GET    /api/venues                  # 场地列表
GET    /api/venues/nearby           # 附近场地
```

所有 API 返回统一格式：

```json
{
  "code": 200,
  "data": { ... },
  "message": "success"
}
```

失败返回：

```json
{
  "code": 400,
  "data": null,
  "message": "参数错误"
}
```

### Prisma Schema（关键部分）

```prisma
model User {
  id            String   @id @default(uuid())
  phone         String   @unique
  nickname      String
  avatar        String?
  latitude      Float?
  longitude     Float?
  idVerified    Boolean  @default(false)
  creditScore   Int      @default(100)
  sportTypes    String[] // ["basketball","fishing","running"]
  createdAt     DateTime @default(now())

  activities    Activity[] @relation("OrganizerActivities")
  applies       Apply[]
  reviewsFrom   Review[]
  reviewsTo     Review[]
}

model Activity {
  id            String   @id @default(uuid())
  organizerId   String
  organizer     User     @relation("OrganizerActivities", fields: [organizerId], references: [id])
  sportType     String
  title         String
  description   String?
  startTime     DateTime
  endTime       DateTime
  venueName     String
  venueLatitude Float
  venueLongitude Float
  capacity      Int
  fee           Decimal
  feeUnit       String   // "per_person" / "free"
  status        String   // "open" / "ongoing" / "completed" / "canceled"
  createdAt     DateTime @default(now())

  applies       Apply[]
  reviews       Review[]
}

model Apply {
  id          String   @id @default(uuid())
  activityId  String
  activity    Activity @relation(fields: [activityId], references: [id])
  userId      String
  user        User     @relation(fields: [userId], references: [id])
  status      String   // "applied" / "checked_in" / "canceled" / "absent"
  checkinAt   DateTime?
  createdAt   DateTime @default(now())

  @@unique([activityId, userId])
}

model Review {
  id           String   @id @default(uuid())
  activityId   String
  activity     Activity @relation(fields: [activityId], references: [id])
  fromUserId   String
  fromUser     User     @relation(fields: [fromUserId], references: [id])
  toUserId     String
  toUser       User     @relation(fields: [toUserId], references: [id])
  rating       Int      // 1-5
  comment      String?
  createdAt    DateTime @default(now())

  @@unique([activityId, fromUserId, toUserId])
}
```

## 四、地理查询的实现

这是这个产品最特殊的部分——"找附近的组局"。

### 用 PostGIS 做地理查询

PostgreSQL 的 PostGIS 扩展天然支持地理查询，不需要自己写复杂的地理算法。

示例查询——"找上海市的篮球组局"：

```sql
SELECT * FROM activities
WHERE sport_type = 'basketball'
  AND status = 'open'
  AND start_time >= NOW()
  AND EarthDistance(
      LLToGeo(31.2304, 121.4737),  -- 用户位置
      LLToGeo(venue_latitude, venue_longitude)
    ) < 10000  -- 10 公里内
ORDER BY EarthDistance(
    LLToGeo(31.2304, 121.4737),
    LLToGeo(venue_latitude, venue_longitude)
  ) ASC
LIMIT 20;
```

Prisma 中也可以用 `prisma-geo` 或 `prisma-geo-driver` 来做地理查询。

### 索引优化

 venue_latitude, venue_longitude 需要建 GIST 索引：

```sql
CREATE INDEX idx_activity_location ON activities
USING GIST (LLToGeo(venue_latitude, venue_longitude));
```

这个索引让地理查询在毫秒级别完成，而不是秒级。

## 五、地图选哪个

**推荐腾讯位置服务。**

理由：

- 国内定位最准（百度其次，高德再次）
- 免费额度充足（日限 50 万次调用）
- 有现成的 React Native SDK：`tencent-react-native-map`
- 支持逆地理编码（经纬度 → 地址名）

百度和高德也可以，但腾讯的 React Native 支持更完善。

## 六、部署方案

### 服务器

推荐阿里云 ECS t6 实例（2 核 2G），约 50 元/月。

配置：

- 操作系统：Ubuntu 22.04 LTS
- Web 服务：Nginx
- 反向代理 + 静态文件托管

### 数据库

MVP 阶段用同一台服务器的 PostgreSQL，不用单独买数据库服务。

PostgreSQL 的安装和启动：

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo apt install postgis  # 地理查询扩展
sudo systemctl start postgresql
sudo -u postgres psql -c "CREATE DATABASE sports_social;"
```

### 前端

Expo 构建后，可以生成：

- Android：生成 APK，用户直接下载安装
- iOS：通过 TestFlight 分发（需要 Apple Developer 账号，年费 $99）
- 网页版：Expo Web，直接部署在 Nginx 上

MVP 阶段优先做 Android，因为国内 Android 用户占比高，且上架 Google Play 不需要审核。

### 部署流程

```bash
# 1. 拉取代码
cd /home/app/sports-social
git pull

# 2. 重启后端
pm2 restart sports-social-backend

# 3. 重启 Nginx
sudo nginx -s reload

# 4. 数据库迁移（如有 Schema 变更）
cd server && npx prisma migrate dev
```

如果不想用 PM2，用 systemd 也可以，更轻量。

## 七、不需要做的事

以下这些技术是 MVP 阶段**绝对不要做**的：

- **不要自建 IM**：用微信小程序群/企业微信就够了。自建即时通讯是 100 万以上的坑
- **不要做支付系统**：费用通过微信转账结算。支付需要合规，别碰
- **不要做推荐算法**：10 个组局不需要算法。按时间和距离排序就够了
- **不要做实时 WebSocket**：推送用短信 + 微信消息就够了
- **不要上微服务**：一个单体 Express 应用跑 10 年也没问题
- **不要做 AI**：你的产品不需要 AI 来加分
- **不要做 PWA**：做 Android App 就够了

这些看起来是"技术亮点"，但对 MVP 阶段来说，每一个都是纯成本。

## 八、总成本

| 项目 | 月费 | 年费 |
|------|------|------|
| 阿里云 ECS t6（2 核 2G） | 50 元 | 600 元 |
| 域名 | 1 元 | 12 元 |
| 数据库（同服务器） | 0 元 | 0 元 |
| 对象存储（OSS） | 5 元 | 60 元 |
| 短信服务 | 按量，约 50 元 | 600 元 |
| 腾讯位置服务 | 免费 | 0 元 |
| 证书（SSL） | 免费（Let's Encrypt） | 0 元 |
| **合计** | **约 56 元/月** | **约 672 元/年** |

服务器一年不到 1000 块钱。

开发成本是唯一的真金白银：时间。

## 九、开发周期估算

如果一个人做：

| 阶段 | 工作量 | 时间 |
|------|--------|------|
| 后端 API | 30 个接口 | 2 周 |
| 前端首页 + 列表 | 核心页面 | 1 周 |
| 前端组局详情 + 发起 | 核心页面 | 1 周 |
| 前端个人主页 | 辅助页面 | 3 天 |
| 报名/评价流程 | 核心流程 | 5 天 |
| 地图集成 | 地理查询 | 3 天 |
| 推送 + 通知 | 辅助 | 3 天 |
| 联调 + 测试 | 全链路 | 1 周 |
| 部署 + 上线 | 环境配置 | 3 天 |
| **合计** | **MVP 上线** | **约 8 周** |

每天写 6-8 小时代码，两个月可以上线一个能用的 MVP。

## 十、技术栈的演进路径

MVP 阶段的技术选型，不需要考虑 100 万用户的事情。但当用户量真的到了那个量级时，需要做的演进如下：

| 用户量 | 需要升级的部分 |
|--------|---------------|
| 1000 活跃 | 不需要升级，MVP 方案够用 |
| 1 万活跃 | Redis 缓存组局列表，减少数据库压力 |
| 10 万活跃 | 数据库读写分离，增加只读副本 |
| 100 万活跃 | 上 CDN，上消息队列，上分库分表 |

在 1000 用户之前，不用想这些事。先把产品做出来，让用户用起来。

## 十一、一个技术人的忠告

做 MVP 的时候，最容易犯的错误是：**技术选型时想得太远**。

"我用 Rust 写后端，性能多好"——但你两周能写完吗？
"我用 Flutter，编译快"——但你一个没学过 Flutter 的人能一周上手吗？
"我上微服务，可扩展性好"——但微服务运维成本是单体的十倍。

选择你**现在就会用**的技术，而不是**你觉得最先进**的技术。

MVP 阶段的核心指标不是"架构有多优雅"，而是"多长时间能上线"。

技术选型的唯一正确标准是：**它能不能帮你以最少的精力、最快的速度，把一个可用的东西推到用户面前**。
