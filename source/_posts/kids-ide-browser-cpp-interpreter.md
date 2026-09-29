---
title: 在浏览器里跑 C++：少儿编程 IDE 的完整构建记录
date: 2026-09-26 18:14:00
permalink: /2026/09/26/kids-ide-browser-cpp-interpreter/
tags:
  - C++
  - 解释器
  - Web Worker
  - 少儿编程
  - 浏览器
  - TypeScript
  - 架构设计
categories:
  - 技术分享
---

这篇文章记录了一个完整的项目——从零开始在浏览器里跑 C++ 代码。不是用 WASM 编译，不是调后端 API，是用纯 JavaScript 写一个解释器，让 C++ 代码在 Web Worker 里直接执行。

## 为什么要做这个

起因很简单：少儿编程教育需要 C++ 在线 IDE，但现有的方案要么太重（需要后端编译服务），要么太贵（Cloud9 之类的按小时计费），要么不免费（CodeSandbox 的限制）。

我想做一个**纯前端**的 C++ IDE：代码在浏览器里直接执行，不需要任何后端服务。

这不是一个商业项目，而是一个技术挑战：C++ 是静态强类型语言，浏览器是 JavaScript 运行时，这两者之间的距离需要一座桥。

## 技术路线选择

最初考虑了两个方案：

| 方案 | 优点 | 缺点 |
|------|------|------|
| **WASM (Emscripten)** | 真实编译，性能接近原生 | 编译慢、无法单步调试、对学生不透明 |
| **Web Worker + 自研解释器** | 可调试、可教育、无编译延迟 | 实现复杂、性能不如编译 |

最终选了 Web Worker + 自研解释器。核心原因：教育场景需要**可解释性**——学生需要看到变量怎么变、调用栈怎么走。WASM 是编译后的机器码，对学生来说是个黑箱。

## 架构设计

```
┌─────────────────────────────────────────────────┐
│                   浏览器主线程                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Monaco    │  │ Zustand  │  │ Terminal UI   │  │
│  │ Editor    │  │ Store    │  │               │  │
│  └────┬─────┘  └────┬─────┘  └───────┬───────┘  │
│       │              │                │           │
│  ┌────▼──────────────▼────────────────▼───────┐  │
│  │              IDE Controller                  │  │
│  │   (调度执行、调试、UI 更新)                    │  │
│  └────────────────────┬───────────────────────┘  │
│                       │                           │
│         ┌─────────────▼───────────────┐          │
│         │      Web Worker (隔离执行)    │          │
│         │  ┌─────────┐ ┌───────────┐  │          │
│         │  │ Lexer   │ │ Parser    │  │          │
│         │  │ (词法)   │ │ (语法)     │  │          │
│         │  └────┬────┘ └─────┬─────┘  │          │
│         │       │            │         │          │
│         │  ┌────▼────────────▼─────┐   │          │
│         │  │     Evaluator          │   │          │
│         │  │   (树遍历执行引擎)       │   │          │
│         │  └───────────────────────┘   │          │
│         └──────────────────────────────┘          │
└─────────────────────────────────────────────────┘
```

三层分离：**编辑器 UI**（Monaco）、**执行引擎**（Worker 内）、**调度器**（主线程管理 Worker 生命周期）。

## 为什么不用 JSCPP？

JSCPP 是一个开源的 C++ JS 解释器，Phase 0 用它验证架构。但实际用下来有三个问题：

1. **无法单步调试**——JSCPP 是闭源的，没有暴露 AST 和执行状态
2. **错误信息不友好**——直接抛 JavaScript 错误，学生看不懂
3. **扩展困难**——想加自定义语法（比如 `cout << "你好"` 自动补全）需要 fork

Phase 1-3 用 JSCPP 跑通链路，Phase 4 完全迁移到自研解释器。最终 JSCPP 依赖被移除了，但 package.json 里还留着（懒得清理）。

## 词法分析器：把文本拆成 Token

C++ 的词法分析比 JavaScript 复杂得多。JavaScript 没有类型声明，C++ 有 `int`、`float`、`char` 这些关键字；JavaScript 没有范围运算符 `:`（for 循环里），C++ 有；JavaScript 没有 C 风格强制转换 `(int)x`，C++ 有。

```typescript
// 关键字列表（部分）
const KEYWORDS = new Set([
  'int', 'float', 'double', 'char', 'string', 'bool',
  'if', 'else', 'while', 'for', 'do', 'return',
  'break', 'continue', 'switch', 'case', 'default',
  'void', 'true', 'false', 'cin', 'cout', 'endl',
  'std', 'vector', 'include', 'using', 'namespace',
  'main', 'scanf', 'printf',
])

// Token 类型
export enum TokenType {
  // 字面量
  INT_LITERAL, FLOAT_LITERAL, CHAR_LITERAL, STRING_LITERAL,
  // 标识符和关键字
  IDENTIFIER, KEYWORD,
  // 运算符
  PLUS, MINUS, STAR, SLASH, PERCENT,
  ASSIGN, PLUS_ASSIGN, MINUS_ASSIGN, STAR_ASSIGN, SLASH_ASSIGN,
  // 逻辑和位运算
  LOGICAL_AND, LOGICAL_OR, LOGICAL_NOT,
  BITWISE_AND, BITWISE_OR, BITWISE_NOT, BITWISE_XOR,
  // 比较
  EQ, NEQ, LT, GT, LE, GE,
  // 特殊
  L_PAREN, R_PAREN, L_BRACKET, R_BRACKET, L_BRACE, R_BRACE,
  SEMICOLON, COMMA, DOT, ARROW, // -> for member access
  // 预处理
  HASH, PREPROCESSOR_DIRECTIVE,
  // 特殊标记
  EOF,
}
```

最难的部分是处理**C 风格强制转换** `(int)x`。词法分析器看到 `(` 时不知道这是函数调用还是类型转换——因为 `int` 是关键字，但 `(int)` 是转换表达式。这个歧义在语法分析阶段解决：

```typescript
// 语法分析器 parseUnary() 中
private parseUnary(): ASTNode {
  // ... 先处理一元运算符
  if (this.current.type === TokenType.L_PAREN) {
    const paren = this.current
    this.advance()
    // 如果下一个是关键字，可能是 C 风格转换
    if (KEYWORDS.has(this.current.value)) {
      const typeName = this.current.value
      this.advance()
      if (this.check(TokenType.R_PAREN)) {
        this.advance()  // consume ')'
        const operand = this.parseUnary()
        return { type: 'CStyleCast', line: paren.line, col: paren.col, castType: typeName, operand }
      }
    }
    // ... 否则是括号表达式或函数调用
  }
}
```

这个设计让 `(int)x` 和 `(2 + 3) * 4` 在同一个 `(` 分支里处理，减少了歧义。

## 语法分析器：递归下降 + 运算符优先级

C++ 语法分析的核心挑战是**运算符优先级**。`a + b * c` 应该解析为 `a + (b * c)` 而不是 `(a + b) * c`。

递归下降语法分析器通过**方法调用层级**实现优先级：

```typescript
private parseExpression(): ASTNode {
  return this.parseLogicalOr()
}

private parseLogicalOr(): ASTNode {
  let left = this.parseLogicalAnd()
  while (this.current.type === TokenType.LOGICAL_OR) {
    const op = this.current
    this.advance()
    const right = this.parseLogicalAnd()
    left = { type: 'BinaryExpr', operator: '||', left, right }
  }
  return left
}

private parseLogicalAnd(): ASTNode {
  let left = this.parseBitwiseOr()
  // ... 类似模式
}

private parseEquality(): ASTNode {
  let left = this.parseRelational()
  while (this.current.type === TokenType.EQ || this.current.type === TokenType.NEQ) {
    // ...
  }
  return left
}

// 优先级从低到高：
// LogicalOr < LogicalAnd < BitwiseOr < BitwiseXor < BitwiseAnd < Equality < Relational < Shift < Additive < Multiplicative < Unary < Primary
```

每一层只处理当前优先级的运算符，然后递归调用下一层。这样 `a + b * c` 在 parseAdditive 层处理 `+`，递归到 parseMultiplicative 处理 `*`，优先级自然正确。

## 执行引擎：树遍历 + 作用域链

执行引擎是 AST 的树遍历器。每个 AST 节点类型对应一个执行方法：

```typescript
execute(node: ASTNode): void {
  switch (node.type) {
    case 'IfStmt': return this.executeIf(node)
    case 'WhileStmt': return this.executeWhile(node)
    case 'ForStmt': return this.executeFor(node)
    case 'BlockStmt': return this.executeBlock(node)
    case 'VarDecl': return this.executeVarDecl(node)
    case 'ExprStmt': this.eval(node.expr); return
    // ... 其他节点类型
  }
}
```

**作用域链**是 C++ 执行的关键。C++ 的作用域规则比 JavaScript 更严格：

```typescript
class Scope {
  variables: Map<string, CppValue> = new Map()
  parent: Scope | null = null

  get(name: string): CppValue | undefined {
    // 先查当前作用域
    if (this.variables.has(name)) return this.variables.get(name)
    // 再查父作用域
    if (this.parent) return this.parent.get(name)
    return undefined
  }

  set(name: string, value: CppValue): void {
    // 赋值只在当前作用域
    this.variables.set(name, value)
  }
}
```

函数调用创建新的作用域，传入参数，执行函数体，然后销毁作用域：

```typescript
executeCall(node: CallExprNode): CppValue {
  const fn = this.functions.get(node.callee)
  if (!fn) throw new Error(`未定义的函数: ${node.callee}`)

  // 创建函数作用域
  const funcScope = createScope(this.globalScope)
  this.callStack.push({ scope: funcScope, name: node.callee, line: node.line })

  try {
    // 绑定参数
    for (let i = 0; i < fn.params.length; i++) {
      const args = node.args
      if (i < args.length) {
        const argValue = this.eval(args[i])
        funcScope.variables.set(fn.params[i].name, argValue)
      }
    }

    // 执行函数体
    this.execute(fn.body)

    return returnValue  // 如果函数有 return 语句
  } finally {
    this.callStack.pop()  // 销毁作用域
  }
}
```

## 调试：探针 + 重跑的折中方案

理想情况：解释器在执行到断点时暂停，捕获状态，等用户按"继续"后恢复。

现实情况：解释器是同步的，Worker 里不能暂停——JavaScript 没有真正的协程。

**折中方案：探针（probe）**

第一次执行时，记录每条语句的行号（探针）：

```typescript
private probeLines: number[] = []

probeLine(line: number): void {
  if (this.probeMode) {
    this.probeLines.push(line)
  }
}
```

第二次执行时，设置断点在目标行，解释器到那行时抛出 `PauseSignal`：

```typescript
private checkBreakpoint(line: number): void {
  if (this.breakpoints.has(line)) {
    this.isPaused = true
    this.currentLine = line
    // 抛出暂停信号，Worker 捕获后返回调试状态
    throw new PauseSignal({ line, variables: this.collectVariables(), ... })
  }
}
```

这个方案的问题是：第一次执行（探针模式）会有副作用——比如打印输出、修改全局变量。第二次执行是"重放"，但全局状态已经变了。

这是一个已知的缺陷，在 docs 里标注了。完美方案需要 AST 序列化 + 状态快照，但那个复杂度太高，不适合教学场景。

## 超时控制：主线程管理 Worker 生命周期

解释器是同步的，Worker 里 `setTimeout` 永远不会触发——因为事件循环被解释器阻塞了。

所以超时控制必须在**主线程**：

```typescript
// 主线程
let timeoutId: number

const worker = new Worker(URL.createObjectURL(workerBlob))
timeoutId = window.setTimeout(() => {
  worker.terminate()  // 强制终止
  onTimeout()
}, 5000)

worker.onmessage = (e) => {
  clearTimeout(timeoutId)
  // 处理结果
}
```

Worker 被 terminate 后，主线程收到的是 `worker.error` 事件，没有返回值。所以主线程需要检查 `timeoutId` 是否被清除来判断是正常完成还是超时。

这个设计的缺点是：超时终止后，Worker 的状态丢失了——不能恢复。但对于教育场景，超时意味着死循环，本来就该终止。

## 构建踩坑：CStyleCast 类型缺失

这个 bug 是我今天刚修的。症状是 `npm run build` 失败，报两个 TypeScript 错误：

```
parser.ts(797,20): error TS2352: Conversion of type '{ type: "CStyleCast"; ... }'
  to type 'ASTNode' may be a mistake.

evaluator.ts(840,12): error TS2678: Type '"CStyleCast"' is not comparable to
  type '"Identifier" | "Program" | "FunctionDecl" | ...'
```

根因：`CStyleCastNode` 接口定义了，但没加到 `ASTNode` 联合类型里。`ASTNode` 是一个 18 个变体的联合类型，漏了一个：

```typescript
// 修复前
export type ASTNode =
  | ProgramNode
  | FunctionDeclNode
  // ... 18 个变体，没有 CStyleCastNode

// 修复后
export interface CStyleCastNode extends BaseNode {
  type: 'CStyleCast'
  castType: string
  operand: ASTNode
}

export type ASTNode =
  | ProgramNode
  // ... 19 个变体，加上 CStyleCastNode
```

同时，parser.ts 里用了 `as ASTNode` 强制转换（绕过了类型检查），修复后删掉了这个转换——因为类型系统已经正确了。

这个 bug 之所以存在，是因为 Phase 4 开发时 `CStyleCast` 功能是后加的，加了接口和解析逻辑，但忘了更新联合类型。单元测试没覆盖到（因为 30 个测试里没有 C 风格转换的测试），所以 CI 一直是绿的，但 `tsc -b` 一跑就炸。

**教训**：单元测试和类型检查是互补的，不是替代的。30 个测试通过不代表代码正确，`tsc -b` 通过不代表代码完整。

## 内存不够：VPS 构建 OOM

部署时遇到了第二个问题：Vite 构建在 `rendering chunks` 阶段被 OOM kill 了。

```
exit code: 137 (SIGKILL)
Memory: total 1.9GB, free 792MB, swap 1GB (full)
```

VPS 只有 2GB 内存，swap 用满了。Vite 构建 Monaco Editor 的 chunk 时内存峰值超过 1.5GB。

解决方案：加 swap。

```bash
fallocate -l 2G /www/swap2
mkswap /www/swap2
swapon /www/swap2
```

加完 swap 后构建成功，耗时 28 秒，产物 4.3MB。

但 swap 是临时的——重启后不会自动挂载。要持久化需要加到 `/etc/fstab`：

```
/www/swap2 swap swap defaults 0 0
```

这个教训是：**构建环境 != 运行环境**。生产环境不需要 Node.js 构建，只需要 Nginx 托管静态文件。但如果需要在同一台机器上构建和运行，内存规划很重要。

## 部署：Nginx 静态托管

IDE 是纯前端应用，不需要后端。部署就是：

1. `vite build` 生成 `dist/`
2. 复制到服务器 `/var/www/IDE/`
3. Nginx 配置静态托管

```nginx
server {
    listen 8890;
    root /var/www/IDE;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /assets/ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

`try_files` 处理前端路由——所有请求都返回 `index.html`，让 React Router 处理。`/assets/` 目录设置 30 天缓存，因为 Vite 构建的文件名包含哈希，内容变了文件名就变了，缓存不会过期。

访问地址：`http://43.153.148.187:8890`

## 代码统计

| 模块 | 文件数 | 行数 |
|------|--------|------|
| 解释器 (Lexer/Parser/Evaluator) | 3 | 2,200+ |
| Worker + 沙箱 | 2 | 440 |
| UI (App/Editor/Terminal) | 4 | 1,200+ |
| 状态管理 | 1 | 130 |
| 调度器 | 1 | 275 |
| 测试 | 1 | 471 |
| 文档 | 7 | 1,800+ |
| **总计** | **19** | **~6,500** |

## 总结

这个项目教我的几件事：

1. **教育场景需要可解释性**——黑箱方案（WASM、后端编译）不适合教学。学生需要看到代码怎么执行的。

2. **类型系统是最后一道防线**——30 个测试通过但 `tsc -b` 失败，说明测试覆盖和类型检查是互补的。特别是联合类型，漏一个变体不会让测试失败，但会让构建失败。

3. **Worker 隔离是必要的**——没有 Worker，死循环会卡死浏览器标签页。有 Worker，超时后可以 `terminate()` 终止。这个设计成本很低（一个 `new Worker()` 调用），但收益很高（浏览器不会崩）。

4. **探针方案是折中**——完美调试需要 AST 序列化 + 状态快照，复杂度太高。探针 + 重跑的方案有副作用问题，但对教学场景够用。

5. **构建环境要提前规划**——VPS 内存不够构建是常见问题。要么加 swap，要么在本地构建后上传 dist。不要等到部署时才发现内存不够。

这个项目是一个技术挑战，不是商业项目。它解决了一个真实的问题（少儿 C++ 在线 IDE），但也暴露了很多问题（内存限制、调试不完美、测试覆盖不足）。

这些问题的解决方案不在这篇文章里——那是下一篇文章的事。