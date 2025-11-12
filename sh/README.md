# Hexo 管理脚本

这个目录包含了用于管理 Hexo 开发服务器的脚本集合。

## 脚本列表

### 🚀 启动相关
- **`hexo-start.sh`** - 主启动脚本，支持正常和静默模式
- **`hexo-silent.sh`** - 专用静默启动脚本，后台运行
- **`hexo-dev.sh`** - 开发模式启动脚本

### 🛑 停止相关
- **`hexo-stop.sh`** - 智能停止 Hexo 服务器（推荐）
- **`hexo-kill.sh`** - 强制停止端口占用进程（谨慎使用）

### 📊 状态检查
- **`hexo-status.sh`** - 详细状态检查
- **`hexo-ps.sh`** - 快速进程检查

## 使用方法

### 启动服务器

```bash
# 正常启动（前台运行，显示日志）
bash blog/sh/hexo-start.sh

# 静默启动（后台运行）
bash blog/sh/hexo-start.sh --silent
# 或者
bash blog/sh/hexo-silent.sh
```

### 停止服务器

```bash
# 智能停止（推荐）
bash blog/sh/hexo-stop.sh

# 强制停止所有端口占用进程（谨慎使用）
bash blog/sh/hexo-kill.sh
```

### 查看状态

```bash
# 详细状态检查
bash blog/sh/hexo-status.sh

# 快速检查
bash blog/sh/hexo-ps.sh
```

## 功能特性

### 自动化功能
- ✅ 自动检测并切换到正确的项目目录
- ✅ 自动安装缺失的依赖 (npm/pnpm)
- ✅ 自动查找可用端口 (4000, 4001, 4002...)
- ✅ 自动清理和生成静态文件

### 进程管理
- ✅ 支持优雅停止和强制停止
- ✅ PID 跟踪和日志记录
- ✅ 多种进程查找方式

### 状态监控
- ✅ 进程状态检查
- ✅ 端口占用检查
- ✅ 网络连接测试
- ✅ 彩色输出和友好提示

## 文件说明

### 日志文件
- `hexo-server.log` - 静默启动时的服务器信息日志

### 配置要求
- 脚本需要在 `blog/sh/` 目录中
- Hexo 项目根目录需要包含 `_config.yml`
- 需要安装 Node.js 和 npm/pnpm

### 脚本功能对比

| 脚本 | 用途 | 特点 |
|------|------|------|
| `hexo-start.sh` | 主启动脚本 | 支持正常/静默模式，显示详细日志 |
| `hexo-silent.sh` | 后台启动 | 显示启动过程，服务器后台运行 |
| `hexo-stop.sh` | 智能停止 | 多种停止方式，Windows/Linux 兼容 |
| `hexo-kill.sh` | 强制停止 | 强制停止端口占用，谨慎使用 |
| `hexo-status.sh` | 详细状态 | 完整的服务器状态检查 |
| `hexo-ps.sh` | 快速检查 | 简单的进程状态查看 |

## 故障排除

### 常见问题

1. **端口被占用**
   - 脚本会自动尝试下一个可用端口
   - 使用 `hexo-status.sh` 查看端口占用情况

2. **进程无法停止**
   - `hexo-stop.sh` 会尝试多种停止方式
   - 包括优雅停止、强制停止、pkill 等

3. **权限问题**
   - 确保脚本有执行权限：`chmod +x blog/sh/*.sh`

4. **路径问题**
   - 脚本会自动处理路径，可以从任何目录运行

### 调试模式

如果遇到问题，可以查看详细状态：

```bash
bash blog/sh/hexo-status.sh
```

这会显示完整的服务器状态、进程信息和网络连接情况。