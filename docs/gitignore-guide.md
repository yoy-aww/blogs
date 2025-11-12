# Hexo博客项目 .gitignore 配置指南

本文档详细说明了Hexo博客项目中`.gitignore`文件的配置规则和原因。

## 核心忽略项

### 依赖包管理
```gitignore
# Dependencies
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
```
**说明：**
- `node_modules/` - npm/yarn/pnpm安装的依赖包，体积庞大且可通过package.json重新安装
- `*-debug.log*` - 包管理器的调试日志文件，包含错误信息但不需要版本控制

### Hexo生成文件
```gitignore
# Generated files
public/
.deploy*/
db.json
```
**说明：**
- `public/` - Hexo生成的静态网站文件，每次`hexo generate`都会重新创建
- `.deploy*/` - 部署相关的临时文件夹
- `db.json` - Hexo的数据库缓存文件，存储文章和页面的元数据

## 开发环境相关

### 运行时数据
```gitignore
# Runtime data
pids
*.pid
*.seed
*.pid.lock
```
**说明：**
- 进程ID文件和种子文件，运行时产生的临时数据

### 测试覆盖率
```gitignore
# Coverage directory used by tools like istanbul
coverage/
*.lcov

# nyc test coverage
.nyc_output
```
**说明：**
- `coverage/` - 代码覆盖率报告目录
- `*.lcov` - LCOV格式的覆盖率数据文件
- `.nyc_output` - NYC测试工具的输出目录

### 构建工具
```gitignore
# Grunt intermediate storage
.grunt

# Bower dependency directory
bower_components

# node-waf configuration
.lock-wscript

# Compiled binary addons
build/Release

# Dependency directories
jspm_packages/
```
**说明：**
- 各种前端构建工具的临时文件和依赖目录

## 缓存和临时文件

### TypeScript和编译缓存
```gitignore
# TypeScript cache
*.tsbuildinfo

# Optional npm cache directory
.npm

# Optional eslint cache
.eslintcache

# Microbundle cache
.rpt2_cache/
.rts2_cache_cjs/
.rts2_cache_es/
.rts2_cache_umd/
```
**说明：**
- 编译器和工具的缓存文件，用于提高构建速度但不需要版本控制

### 通用缓存
```gitignore
# parcel-bundler cache
.cache
.parcel-cache

# Temporary folders
tmp/
temp/

# Logs
logs
*.log
```
**说明：**
- 各种工具的缓存目录和临时文件夹
- 日志文件通常包含运行时信息，不需要版本控制

## 环境配置

### 环境变量
```gitignore
# dotenv environment variables file
.env
.env.test
.env.production
```
**说明：**
- 环境变量文件可能包含敏感信息（API密钥、数据库密码等）
- 不同环境的配置文件应该分别管理

### 历史记录
```gitignore
# Optional REPL history
.node_repl_history

# Yarn Integrity file
.yarn-integrity
```
**说明：**
- REPL（交互式解释器）的历史记录
- Yarn的完整性检查文件

## 框架特定文件

### Next.js / Nuxt.js
```gitignore
# Next.js build output
.next

# Nuxt.js build / generate output
.nuxt
dist

# Gatsby files
.cache/
public
```
**说明：**
- 虽然是Hexo项目，但如果将来迁移到其他框架，这些规则会很有用

### Storybook
```gitignore
# Storybook build outputs
.out
.storybook-out
```
**说明：**
- 如果使用Storybook进行组件开发，其构建输出不需要版本控制

## 编辑器和系统文件

### 编辑器配置
```gitignore
# Editor directories and files
.vscode/
.idea/
*.swp
*.swo
*~
```
**说明：**
- `.vscode/` - Visual Studio Code的工作区配置
- `.idea/` - JetBrains IDE的项目配置
- `*.swp`, `*.swo`, `*~` - Vim编辑器的临时文件

### 操作系统文件
```gitignore
# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
```
**说明：**
- `.DS_Store` - macOS系统的目录服务存储文件
- `Thumbs.db` - Windows的缩略图缓存
- `._*` - macOS的资源分支文件
- `.Spotlight-V100`, `.Trashes` - macOS系统文件

## Hexo特定配置

### 部署和主题
```gitignore
# Hexo specific
.deploy_git/
themes/*/node_modules/
```
**说明：**
- `.deploy_git/` - Git部署插件的临时目录
- `themes/*/node_modules/` - 主题目录下的依赖包

## 包文件
```gitignore
# Output of 'npm pack'
*.tgz
```
**说明：**
- npm打包生成的压缩文件

## 最佳实践建议

### 1. 定期更新
随着项目发展和工具更新，定期检查和更新`.gitignore`文件。

### 2. 项目特定配置
根据具体项目需求，可能需要添加或删除某些规则。

### 3. 团队协作
确保团队成员都了解忽略规则的含义，避免意外提交不应该版本控制的文件。

### 4. 敏感信息
特别注意包含敏感信息的文件（如`.env`文件），确保它们被正确忽略。

### 5. 构建产物
所有可以通过构建过程重新生成的文件都应该被忽略。

## 验证配置

使用以下命令检查`.gitignore`是否正确工作：

```bash
# 查看当前被忽略的文件
git status --ignored

# 检查特定文件是否被忽略
git check-ignore 文件名

# 强制添加被忽略的文件（谨慎使用）
git add -f 文件名
```

## 常见问题

### Q: 如果已经提交了应该被忽略的文件怎么办？
A: 使用以下命令从版本控制中移除：
```bash
git rm --cached 文件名
git commit -m "Remove file from version control"
```

### Q: 为什么有些文件夹有斜杠，有些没有？
A: 以斜杠结尾表示只匹配目录，不以斜杠结尾可以匹配文件或目录。

### Q: 可以忽略除了某些文件之外的所有文件吗？
A: 可以，使用`!`符号：
```gitignore
# 忽略所有 .log 文件
*.log
# 但不忽略 important.log
!important.log
```

---

*最后更新：2025年11月12日*