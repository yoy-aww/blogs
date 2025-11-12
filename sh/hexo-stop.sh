#!/bin/bash

# Hexo Server 停止脚本
# 作者: 自动生成
# 用途: 停止 Hexo 开发服务器

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

echo -e "${YELLOW}正在停止 Hexo 服务器...${NC}"

# 方法1: 检查日志文件
STOPPED=false
if [ -f "hexo-server.log" ]; then
    PID=$(grep "PID:" hexo-server.log | cut -d' ' -f2)
    if [ ! -z "$PID" ]; then
        if ps -p $PID > /dev/null 2>&1; then
            # 尝试优雅停止
            kill $PID 2>/dev/null
            sleep 2
            # 检查是否还在运行
            if ps -p $PID > /dev/null 2>&1; then
                # 强制停止
                kill -9 $PID 2>/dev/null
                echo -e "${YELLOW}强制停止进程 $PID${NC}"
            else
                echo -e "${GREEN}✓ 优雅停止进程 $PID${NC}"
            fi
            STOPPED=true
        fi
        rm -f hexo-server.log
    fi
fi

# 方法2: 查找所有相关进程
HEXO_PIDS=$(pgrep -f "hexo.*server" 2>/dev/null)
if [ ! -z "$HEXO_PIDS" ]; then
    echo "$HEXO_PIDS" | while read pid; do
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid 2>/dev/null
            sleep 1
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null
                echo -e "${YELLOW}强制停止进程 $pid${NC}"
            else
                echo -e "${GREEN}✓ 停止进程 $pid${NC}"
            fi
            STOPPED=true
        fi
    done
fi

# 方法3: 使用 pkill (备用方法)
if pkill -f "hexo.*server" 2>/dev/null; then
    echo -e "${GREEN}✓ 使用 pkill 停止了 Hexo 进程${NC}"
    STOPPED=true
fi

# 方法4: Windows 特定方法 (如果在 Windows 环境)
if command -v taskkill > /dev/null 2>&1; then
    # 尝试通过端口找到进程
    for port in 4000 4001 4002 4003 4004; do
        if netstat -an 2>/dev/null | grep -q ":$port "; then
            # 在 Windows 上通过端口查找进程比较复杂，这里使用通用方法
            echo -e "${YELLOW}检测到端口 $port 被占用${NC}"
        fi
    done
fi

if [ "$STOPPED" = true ]; then
    echo -e "${GREEN}✓ Hexo 服务器已停止${NC}"
else
    echo -e "${RED}✗ 未找到运行中的 Hexo 服务器${NC}"
fi