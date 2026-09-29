---
title: 从零搭建 BPMN 工作流平台：踩坑、架构与取舍
date: 2026-09-28 10:00:00
tags:
  - BPMN
  - 工作流
  - Flowable
  - 架构
  - Node.js
  - Docker
categories:
  - 技术分享
---

工作流是商业软件里最被低估的部分。大部分公司用着 Jira 的审批流、钉钉的请假流程、ERP 里的报销单，但从没想过"这背后到底是什么"。

上个月花了一个周末，从零搭了一个完整的 BPMN 工作流平台。前端可视化建模，后端流程引擎，Docker 一键部署。过程中踩了不少坑——Flowable 版本兼容性、REST API 404、Spring Boot 3 迁移问题。这篇文章把整个架构、技术选型、踩坑记录和成本都写出来。

如果你是一个想搞清楚"工作流到底是怎么回事"的开发者，这篇文章可能会省你三天搜索时间。

## 一、为什么要自己搭工作流

市面上现成的工作流产品不少：

| 产品 | 免费方案 | 限制 |
|------|---------|------|
| Camunda | 社区版 | UI 不好用，Java 生态 |
| Activiti | 社区版 | 已停止维护（被 Flowable 替代） |
| Activiti Cloud | 已停 | 迁移到 camunda-cloud |
| Flowable | 开源免费 | 无内置 UI，需要自己开发 |
| 钉钉审批 | 免费 | 锁在钉钉生态内 |
| 飞书审批 | 免费 | 锁在飞书生态内 |

这些产品有一个共同问题：**你不拥有流程引擎**。流程定义、任务数据、业务逻辑全在别人的平台上。如果哪天不续订了、平台倒闭了、或者你需要深度定制——你什么都做不了。

自己搭工作流平台的好处：

1. **完全拥有**：流程定义、任务数据、引擎代码全部在自己手里
2. **深度定制**：想加什么字段、什么逻辑都行
3. **学习价值**：理解工作流引擎的底层原理，以后再用任何平台都不会被忽悠
4. **成本可控**：开源方案，服务器一个月 50 块钱

当然，代价是：**你需要自己开发 UI**。Flowable 和 Camunda 都没有提供开箱即用的前端界面。这也是这个项目最主要的开发工作量。

## 二、整体架构

先看架构图：

```
┌─────────────────────────────────────────────────────┐
│               前端 (React + TS + Vite)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │ 流程建模      │  │ 任务处理      │  │ 实例监控  │  │
│  │ bpmn-js      │  │ 任务列表     │  │ 启动/终止 │  │
│  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘  │
│         └─────────────────┼────────────────┘         │
│                           │ HTTP REST                 │
└───────────────────────────┼───────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────┐
│            中间层 (Node.js + Express + TS)             │
│  /api/health  /api/process  /api/task  /api/instance │
│                                                       │
│  ┌─────────────────────────────────────────────┐     │
│  │  FlowableClient 接口                         │     │
│  │   MODE=mock     → 内存 Mock (无需 Docker)    │     │
│  │   MODE=flowable → REST 调用 Flowable 引擎    │     │
│  └─────────────────────────────────────────────┘     │
└───────────────────────────┼───────────────────────────┘
                            ▼ (可选)
┌─────────────────────────────────────────────────────┐
│              Flowable Engine (Java 17+)                │
│              + MySQL 8.0                              │
│  /repository  /runtime  /task  /history              │
└─────────────────────────────────────────────────────┘
```

三层架构，但关键设计是**中间层**。

### 为什么加中间层

最直接的做法是前端直接调用 Flowable REST API。但这样有几个问题：

1. **安全**：Flowable 的认证信息暴露在浏览器里
2. **耦合**：前端代码依赖 Flowable 的 API 格式，换引擎就要改前端
3. **调试困难**：浏览器 DevTools 看到的是一堆 JSON，不清楚业务含义

中间层的作用：

- **统一 API**：前端只调用 `/api/process/deploy`、`/api/task/complete`，不关心底层是 Flowable 还是 Activiti
- **安全隔离**：Flowable 的 URL、用户名、密码只在后端
- **双模式**：`MODE=mock` 时完全不需要 Docker，前后端直接跑在学习环境中；`MODE=flowable` 时切换到真实引擎

这个设计的核心接口：

```typescript
// 所有模式共用的接口
interface FlowableClient {
  deploy(xml: string, name: string): Promise<ProcessDefinition>
  listDefinitions(): Promise<ProcessDefinition[]>
  startInstance(definitionKey: string, businessKey: string, variables: any): Promise<ProcessInstance>
  listInstances(): Promise<ProcessInstance[]>
  terminateInstance(id: string): Promise<void>
  getActivities(instanceId: string): Promise<Activity[]>
  listTasks(assignee?: string): Promise<UserTask[]>
  getTask(id: string): Promise<UserTask>
  completeTask(id: string, variables: any): Promise<void>
  assignTask(id: string, assignee: string): Promise<void>
  addComment(taskId: string, message: string): Promise<void>
  health(): Promise<HealthStatus>
}
```

两个实现，通过环境变量切换：

```typescript
// backend/src/index.ts
const mode = config.mode // 'mock' 或 'flowable'

const client: FlowableClient =
  mode === 'flowable'
    ? new FlowableRestClient(config)
    : new MockFlowableClient()
```

这个设计的好处是：**学习阶段不需要装 Docker**。`MODE=mock` 时所有数据存在内存里，关掉服务就丢了，但足够理解流程是怎么走的。等要生产时再切换到 `flowable` 模式。

## 三、技术选型

### 前端：React + bpmn-js

前端选了 React 18 + TypeScript + Vite，这没什么好说的，我熟悉的栈。

关键组件是 **bpmn-js**。这是 Camunda 开源的 BPMN 2.0 可视化建模器，也是 Camunda Modeler 的底层库。

为什么选 bpmn-js 而不是其他方案：

| 方案 | 说明 |
|------|------|
| **bpmn-js** | Camunda 官方，BPMN 2.0 原生，开源 (MIT)，模块化 |
| Camunda Modeler | 桌面应用，不能嵌入网页 |
| 自研画布 | 可以，但 BPMN 2.0 规范有上百种元素，自己实现不现实 |
| 其他第三方库 | 要么收费，要么维护不活跃 |

bpmn-js 的基本用法：

```typescript
import { Modeler } from 'bpmn-js/lib/Modeler'
import propertiesPanelModule from 'bpmn-js-properties-panel'
import propertiesProviderModule from 'bpmn-js-properties-panel/lib/PropertiesPanelModule'

const modeler = new Modeler({
  container: document.getElementById('canvas'),
  additionalModules: [propertiesPanelModule, propertiesProviderModule],
  keyboard: { bindTo: window },
})

await modeler.importXML(xml)
```

`importXML` 把 BPMN XML 渲染成可视化画布，用户可以直接拖拽节点、连线、修改属性。

### 后端：Node.js + Express

后端选 Node.js 24 + Express + TypeScript。

为什么不用 Java？因为中间层只是 API 网关，业务逻辑很少，不需要 JVM。Node.js 的好处：

- 和前端同一个语言栈，一个人写全栈不累
- 不需要 JVM，部署简单（一个 Node 进程就行）
- Express 足够轻量，MVP 阶段不需要 Nest.js 或 Fastify

### 流程引擎：Flowable

流程引擎选了 **Flowable 7.1.0**。

Flowable 是 Activiti 5 的分叉版本（Activiti 5 被 Alfresco 收购后停止开源，核心开发者创建了 Flowable）。它的功能比 Activiti 5 更完整，而且持续维护。

**为什么不选 Camunda？** Camunda 7 也是开源的，但 Camunda 8 完全关闭了社区版（只给了免费的 SaaS 试用）。Flowable 承诺保持开源（Apache 2.0）。

Flowable 的核心功能：

- **流程引擎**：执行 BPMN 2.0 定义的流程
- **CMMN 引擎**：面向案例管理的流程标准
- **DMN 引擎**：决策表
- **Form Engine**：表单设计
- **IDM 引擎**：身份管理（用户、组、权限）

我用了 Process Engine + REST API，其他引擎暂时没用。

## 四、Flowable 部署的踩坑记录

这部分是重点。Flowable 的部署过程远没有想象中那么顺利。

### 坑 1：Flowable 6.8 vs Spring Boot 3

一开始用的是 Flowable 6.8.1，Spring Boot 2.x。启动正常，但 REST API 端点返回 404。

排查后发现：Flowable 6.8.x 使用 `javax.servlet`，而 Spring Boot 3.x 使用 `jakarta.servlet`。命名空间不同导致 REST 控制器无法注册。

**解决方案**：升级到 Flowable 7.1.0 + Spring Boot 3.x。

```xml
<!-- pom.xml -->
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.0</version>
</parent>

<properties>
    <flowable.version>7.1.0</flowable.version>
</properties>

<dependencies>
    <dependency>
        <groupId>org.flowable</groupId>
        <artifactId>flowable-spring-boot-starter</artifactId>
        <version>${flowable.version}</version>
    </dependency>
    <dependency>
        <groupId>org.flowable</groupId>
        <artifactId>flowable-spring-boot-starter-rest</artifactId>
        <version>${flowable.version}</version>
    </dependency>
</dependencies>
```

### 坑 2：REST API 依赖名称变了

Flowable 6.x 的 REST 依赖是 `flowable-rest`，但 7.x 改了名字：

```xml
<!-- 6.x (错误，7.x 不存在这个 artifact) -->
<artifactId>flowable-rest</artifactId>

<!-- 7.x (正确) -->
<artifactId>flowable-spring-boot-starter-rest</artifactId>
```

而且 `flowable-spring-boot-starter-rest` 会拉入一堆子模块：

```
flowable-spring-boot-starter-process-rest
flowable-spring-boot-starter-app-rest
flowable-spring-boot-starter-cmmn-rest
flowable-spring-boot-starter-dmn-rest
flowable-event-registry-rest
```

### 坑 3：REST 控制器不注册

即使正确引入了依赖，REST API 仍然返回 404。

根因：`RestApiAutoConfiguration`（自动配置类）只通过 `@Bean` 创建配置对象（`RestResponseFactory`、`RestUrls` 等），但**不包含 `@ComponentScan`**。也就是说，自动配置创建了 Bean，但没有扫描 REST 控制器（`@RestController` 注解的类）。

**解决方案**：手动写一个配置类，同时做两件事：

```java
package com.bpmn.demo;

import org.flowable.spring.boot.RestApiAutoConfiguration;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

@Configuration
@Import(RestApiAutoConfiguration.class)  // 先创建配置 Bean
@ComponentScan(basePackages = {
    "org.flowable.rest.service.api"  // 再扫描 REST 控制器
})
public class RestApiConfiguration {
}
```

### 坑 4：Bean 名冲突

尝试扫描 `org.flowable.rest` 和 `org.flowable.idm.rest` 时，两个包下都有 `GroupResource` 类，导致 Spring 启动失败：

```
ConflictingBeanDefinitionException: Annotation-specified bean name 'groupResource'
for bean class [org.flowable.idm.rest.service.api.GroupResource] conflicts
with existing, non-compatible bean definition of same name and class
[org.flowable.rest.service.api.GroupResource]
```

**解决方案**：只扫描 `org.flowable.rest.service.api`（不含 `idm`），避开冲突。

### 坑 5：application.yml 的 YAML 解析

Flowable 的 `application.yml` 有一个微妙的陷阱：

```yaml
# 错误！这个 YAML 解析结果和你想的不一样
spring:
  application:
    name: flowable
  datasource:
    url: jdbc:mysql://localhost:3306/flowable
  jpa:
    hibernate:
      ddl-auto: none
flowable:
  database-schema-update: true
```

问题在于 `spring` 键出现了两次（一次是 `application.name`，一次是 `datasource`）。YAML 规范要求同一个键只能出现一次，重复的键会被后面的覆盖。

正确写法：

```yaml
spring:
  application:
    name: flowable
  datasource:
    url: jdbc:mysql://localhost:3306/flowable
    username: root
    password: root
  jpa:
    hibernate:
      ddl-auto: none

flowable:
  database-schema-update: true
  async-executor-activate: false
```

## 五、Docker Compose 部署

最终用 Docker Compose 编排了四个服务：

```yaml
# docker-compose.yml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "8082:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./frontend/dist:/usr/share/nginx/html:ro
    depends_on:
      - backend
      - flowable

  backend:
    build: ./backend
    ports:
      - "3002:3000"
    environment:
      MODE: flowable
      FLOWABLE_URL: http://flowable:8080
      FLOWABLE_USER: flowable
      FLOWABLE_PASSWORD: ***
    depends_on:
      - flowable

  flowable:
    build: ./infra/flowable-app
    ports:
      - "8081:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/flowable?useSSL=false&allowPublicKeyRetrieval=true
      SPRING_DATASOURCE_USERNAME: root
      SPRING_DATASOURCE_PASSWORD: root
    depends_on:
      mysql:
        condition: service_healthy

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: flowable
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  mysql-data:
```

### Flowable Dockerfile（多阶段构建）

```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# 运行阶段
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

多阶段构建的好处：构建镜像很大（Maven + JDK），但运行镜像只有 200MB（JRE only）。

### 前端 Dockerfile

前端用 Vite 构建，产物是静态文件，不需要 Node 运行时：

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json .
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

但实际部署中，我用 `volume` 挂载替代了 COPY，这样本地构建一次前端，Docker 不需要重复编译。

## 六、前端页面实现

### 建模页面 (ModelerPage)

核心组件是 `BpmnEditor`，封装了 bpmn-js Modeler：

```tsx
// BpmnEditor.tsx (简化版)
const BpmnEditor = ({ xml, onDeploy, onLoad }: Props) => {
  const [modeler, setModeler] = useState<Modeler | null>(null)

  useEffect(() => {
    const modeler = new Modeler({
      container: containerRef.current,
      additionalModules: [propertiesPanelModule, propertiesProviderModule],
    })
    setModeler(modeler)

    if (xml) {
      modeler.importXML(xml)
    }
    return () => modeler.destroy()
  }, [])

  const handleDeploy = async () => {
    const svgData = await modeler.saveXML()
    onDeploy(svgData.xml)
  }

  return (
    <div className="editor-container">
      <div ref={containerRef} className="canvas" />
      <button onClick={handleDeploy}>部署流程</button>
    </div>
  )
}
```

### 任务页面 (TaskPage)

任务页面的核心交互：

1. 左侧：任务列表（按负责人筛选）
2. 右侧：选中任务的详情（变量、评论、操作按钮）

```tsx
// TaskPage.tsx (简化版)
const TaskPage = () => {
  const [tasks, setTasks] = useState<UserTask[]>([])
  const [selected, setSelected] = useState<UserTask | null>(null)
  const [comments, setComments] = useState<Comment[]>([])

  useEffect(() => {
    api.getTasks().then(setTasks)
  }, [])

  const handleComplete = async () => {
    await api.completeTask(selected.id, {})
    await api.getTasks().then(setTasks)
    setSelected(null)
  }

  return (
    <div className="task-page">
      <TaskList tasks={tasks} selected={selected} onSelect={setSelected} />
      {selected && (
        <TaskDetail task={selected} onComplete={handleComplete} />
      )}
    </div>
  )
}
```

### 实例页面 (InstancesPage)

实例页面让用户查看运行中的流程，以及执行历史：

```
┌─────────────────────────────────────────────────────┐
│  流程实例管理                                         │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │ [启动新实例]  选择流程定义: [下拉框]            │   │
│  │ 业务 Key: [________]  变量: [JSON 编辑]       │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  实例列表:                                            │
│  ┌──────────────────────────────────────────────┐   │
│  │ ID    | 定义Key   | 业务Key  | 状态 | 操作    │   │
│  │ a1b2c | order     | ORD-001  | 运行中| 详情   │   │
│  │ d3e4f | leave     | LV-002   | 运行中| 详情   │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  选中实例 → 执行历史 + 变量 + 终止按钮                  │
└─────────────────────────────────────────────────────┘
```

## 七、双模式的完整实现

### Mock 模式（无需 Docker）

`MockFlowableClient` 用内存模拟整个工作流引擎的行为：

```typescript
class MockFlowableClient implements FlowableClient {
  private definitions: ProcessDefinition[] = []
  private instances: ProcessInstance[] = []
  private tasks: UserTask[] = []
  private nextId = 1

  async deploy(xml: string, name: string): Promise<ProcessDefinition> {
    const def: ProcessDefinition = {
      id: `def-${this.nextId++}`,
      key: name.replace(/\s+/g, '_').toLowerCase(),
      name,
      version: 1,
      // 从 XML 中简单提取用户任务节点名
      tasks: this.parseTasksFromXml(xml),
    }
    this.definitions.push(def)
    return def
  }

  async startInstance(
    definitionKey: string,
    businessKey: string,
    variables: any
  ): Promise<ProcessInstance> {
    const def = this.definitions.find(d => d.key === definitionKey)
    if (!def) throw new Error(`Definition not found: ${definitionKey}`)

    const inst: ProcessInstance = {
      id: `inst-${this.nextId++}`,
      definitionKey,
      businessKey,
      status: 'running',
      variables: variables || {},
      activities: [],
    }
    this.instances.push(inst)

    // 简单模拟：为每个用户任务创建一个 task
    def.tasks.forEach(taskName => {
      this.tasks.push({
        id: `task-${this.nextId++}`,
        instanceId: inst.id,
        name: taskName,
        assignee: null,
        status: 'pending',
        variables: inst.variables,
      })
    })

    return inst
  }

  async completeTask(id: string, variables: any): Promise<void> {
    const task = this.tasks.find(t => t.id === id)
    if (!task) throw new Error(`Task not found: ${id}`)
    task.status = 'completed'
  }

  async health(): Promise<HealthStatus> {
    return { ok: true, engine: 'mock-flowable' }
  }
}
```

Mock 模式的局限：

- 数据不持久化，重启丢失
- 不能模拟分支、并行、网关等复杂流程
- 不能执行 Service Task 或 Script Task

但对于**学习和演示**来说，完全够用。你不需要 Docker，不需要 MySQL，不需要 Java，只需要 Node.js 就能跑起来理解整个工作流的概念。

### Flowable 模式（生产）

`FlowableRestClient` 通过 HTTP 调用 Flowable REST API：

```typescript
class FlowableRestClient implements FlowableClient {
  constructor(private config: Config) {}

  private get auth(): string {
    return Buffer.from(`${this.config.flowableUser}:${this.config.flowablePassword}`).toString('base64')
  }

  async deploy(xml: string, name: string): Promise<ProcessDefinition> {
    // 1. 先部署（Flowable 7.x 需要两步）
    const deployment = await this.request('POST', '/repository/deployments', {
      name,
      skipVersionCheck: true,
    })
    // 2. 添加资源
    await this.request('POST', `/repository/deployments/${deployment.id}/add`, {
      xml,
    })

    // 3. 获取流程定义
    const defs = await this.request('GET', '/repository/process-definitions?latest=true')
    const def = defs.find((d: any) => d.name === name)
    return def
  }

  async completeTask(id: string, variables: any): Promise<void> {
    await this.request('PUT', `/task/${id}/complete`, { variables })
  }
}
```

Flowable 7.x 的部署 API 和 6.x 不同——6.x 是一个请求搞定，7.x 需要两步（先创建 deployment，再添加资源）。

## 八、示例流程

项目包含两个示例流程：

### 订单审批流程 (order-approval.bpmn)

```
[开始] → [创建订单] → <审批网关>
                            ↓ (金额 < 1000)    ↓ (金额 >= 1000)
                       [自动通过]           [经理审批]
                            ↓                    ↓
                        [确认订单] ←──── [财务审批]
                            ↓
                          [结束]
```

这个流程演示了：

- **开始事件 → 用户任务**：创建订单
- **排他网关**：根据金额走不同分支
- **用户任务**：经理审批、财务审批
- **结束事件**：确认订单

### 请假申请流程 (leave-request.bpmn)

```
[开始] → [提交请假] → [主管审批] → <结果>
                                    ↓ (同意)    ↓ (拒绝)
                              [HR 备案]    [通知申请人]
                                    ↓          ↓
                                  [结束]     [结束]
```

## 九、成本估算

| 项目 | 月费 | 说明 |
|------|------|------|
| 阿里云 ECS (2核2G) | 50 元 | Flowable + MySQL + Node.js + Nginx |
| 域名 | 1 元 | 已购 |
| 数据库 | 0 元 | MySQL 跑在同一台服务器 |
| SSL 证书 | 0 元 | Let's Encrypt |
| 镜像存储 (Docker Hub) | 0 元 | 自建仓库或 registry |
| **合计** | **51 元/月** | 足够跑 50 个并发流程实例 |

Flowable 引擎的内存消耗大约 300-500MB，MySQL 大约 200-400MB，Node.js 中间层 50-100MB。一台 2 核 2G 的服务器绰绰有余。

如果并发量大了（比如几百个流程实例同时运行），可以：

- 加一台只读 MySQL 副本
- Flowable 引擎加 Redis 缓存
- 中间层上 PM2 cluster 模式

但对于 MVP 阶段，一台 2 核 2G 服务器完全够用。

## 十、项目目录结构

```
bpmn/
├── docker-compose.yml          # 4 个服务编排
├── nginx.conf                  # 反向代理配置
├── README.md
│
├── frontend/                   # React + TS + Vite + bpmn-js
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── styles.css
│       ├── components/
│       │   ├── BpmnEditor.tsx      # BPMN 建模器封装
│       │   ├── Header.tsx          # 导航 + 健康状态
│       │   └── Toast.tsx           # 通知组件
│       ├── pages/
│       │   ├── ModelerPage.tsx     # 流程建模
│       │   ├── TaskPage.tsx        # 任务处理
│       │   └── InstancesPage.tsx   # 实例监控
│       ├── services/
│       │   └── api.ts              # API 客户端
│       └── types/
│           └── bpmn.ts             # 类型定义
│
├── backend/                    # Node.js + Express + TS
│   ├── package.json
│   ├── tsconfig.json
│   ├── .env                    # MODE=flowable, FLOWABLE_URL=...
│   ├── Dockerfile              # 多阶段构建
│   └── src/
│       ├── index.ts            # 入口
│       ├── app.ts              # Express 应用
│       ├── config.ts           # 配置
│       ├── types.ts            # 类型定义
│       ├── routes/
│       │   ├── process.ts      # 流程定义 API
│       │   ├── instance.ts     # 流程实例 API
│       │   └── task.ts         # 任务 API
│       └── services/
│           ├── flowable.ts     # 接口定义
│           ├── mockFlowable.ts # Mock 实现
│           └── flowableRest.ts # REST 实现
│
├── infra/
│   └── flowable-app/           # Flowable Spring Boot 应用
│       ├── pom.xml
│       ├── Dockerfile          # 多阶段构建
│       └── src/
│           ├── main/java/com/bpmn/demo/
│           │   ├── FlowableApplication.java
│           │   └── RestApiConfiguration.java
│           └── main/resources/
│               └── application.yml
│
├── processes/                  # 示例流程
│   ├── order-approval.bpmn     # 订单审批
│   └── leave-request.bpmn      # 请假申请
│
└── docs/
    └── architecture.md         # 架构文档
```

## 十一、快速启动

### 本地学习（无需 Docker）

```bash
# 后端（Mock 模式）
cd backend
npm install
npm run dev
# → http://localhost:3000

# 前端
cd frontend
npm install
npm run dev
# → http://localhost:5174
```

打开 `http://localhost:5174`，直接进入 BPMN 建模界面。可以画图、部署、启动实例、处理任务。

### Docker Compose 完整部署

```bash
# 构建并启动所有服务
docker compose up -d --build

# 验证
curl http://localhost:8082/api/health
# → {"ok":true,"engine":"flowable","port":3002}

# 访问前端
# → http://localhost:8082
```

### 端口说明

| 服务 | 端口 | 说明 |
|------|------|------|
| nginx (前端) | 8082 | 用户访问入口 |
| backend (Node.js) | 3002 | API 中间层 |
| flowable (Java) | 8081 | 工作流引擎 |
| mysql | 3306 | 数据库 |

## 十二、这个项目的局限性

诚实说，这个项目有几个明显的不足：

1. **没有用户认证**：任何人都可以操作。生产环境必须加 JWT 认证
2. **没有表单设计**：UserTask 只支持变量，没有可视化表单
3. **流程实例不能分页**：`listInstances()` 返回所有实例，实例多时会很慢
4. **没有权限控制**：任务指派用字符串，没有用户管理系统
5. **没有监控告警**：流程卡在某个节点超时了，你不知道

如果要生产用，至少要加：

```
优先级 1 (必须):
- [ ] JWT 认证
- [ ] 用户和角色管理
- [ ] 任务超时提醒

优先级 2 (建议):
- [ ] 表单设计器 (bpmn-js + form-js)
- [ ] 流程实例分页查询
- [ ] 操作日志

优先级 3 (增强):
- [ ] 定时任务 (Timer Event)
- [ ] 外部 Worker (HTTP 长轮询)
- [ ] 监控 (Prometheus + Grafana)
```

## 十三、总结

这个 BPMN 工作流平台的核心收获：

**技术层面**：

- Flowable 6.x 到 7.x 的迁移有 breaking changes（依赖名、API 格式、Servlet 命名空间）
- Spring Boot 3 的 `@AutoConfiguration` 只创建配置 Bean，不包含 `@ComponentScan`
- Docker 多阶段构建可以把构建镜像和运行镜像分离，节省 80% 的空间

**架构层面**：

- 中间层（BFF）模式值得推广：前端不直接依赖第三方 API
- 双模式设计（Mock / Real）让学习和生产分离，不需要每一步都装 Docker
- 接口隔离原则：`FlowableClient` 接口让 Mock 和 REST 实现可以无缝切换

**实际建议**：

如果你只是需要"审批流"这种简单功能，用钉钉/飞书就够了，没必要自己搭。

如果你需要深度定制（比如流程逻辑要嵌入业务系统、数据不能放在第三方平台），那自己搭一个轻量级的工作流引擎是值得的。

如果你只是想学习工作流引擎的原理，这个项目是最快的方式——一个周末就能跑起来，从建模到部署到执行，整个链路都走通。

---

项目地址：[GitHub - yoy-aww/bpmn](https://github.com/yoy-aww/bpmn)（MIT License）
