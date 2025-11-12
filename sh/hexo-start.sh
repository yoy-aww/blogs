#!/bin/bash

# Hexo Server 启动脚本
# 作者: 自动生成
# 用途: 启动 Hexo 开发服务器
# 使用方法: 
#   正常模式: ./hexo-start.sh
#   静默模式: ./hexo-start.sh --silent

# 检查是否为静默模式
SILENT=false
if [[ "$1" == "--silent" || "$1" == "-s" ]]; then
    SILENT=true
fi

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$SILENT" = false ]; then
    echo -e "${YELLOW}脚本目录: $SCRIPT_DIR${NC}"
    echo -e "${YELLOW}项目根目录: $PROJECT_ROOT${NC}"
fi

cd "$PROJECT_ROOT" || {
    echo -e "${RED}错误: 无法切换到项目根目录${NC}"
    exit 1
}

# 检查是否在正确的目录
if [ ! -f "_config.yml" ]; then
    echo -e "${RED}错误: 未找到 _config.yml 文件${NC}"
    echo -e "${YELLOW}当前目录: $(pwd)${NC}"
    echo -e "${YELLOW}请确保脚本在 Hexo 项目的 sh 子目录中${NC}"
    exit 1
fi

if [ "$SILENT" = false ]; then
    echo -e "${GREEN}工作目录: $(pwd)${NC}"
fi

# 检查 node_modules 是否存在
if [ ! -d "node_modules" ]; then
    if [ "$SILENT" = false ]; then
        echo -e "${YELLOW}未找到 node_modules 目录，正在安装依赖...${NC}"
    fi
    if command -v pnpm &> /dev/null; then
        if [ "$SILENT" = true ]; then
            pnpm install > /dev/null 2>&1
        else
            pnpm install
        fi
    elif command -v npm &> /dev/null; then
        if [ "$SILENT" = true ]; then
            npm install > /dev/null 2>&1
        else
            npm install
        fi
    else
        if [ "$SILENT" = false ]; then
            echo -e "${RED}错误: 未找到 npm 或 pnpm${NC}"
        fi
        exit 1
    fi
fi

# 清理并生成静态文件
if [ "$SILENT" = false ]; then
    echo -e "${GREEN}正在清理并生成静态文件...${NC}"
    npx hexo clean
    npx hexo generate
else
    npx hexo clean > /dev/null 2>&1
    npx hexo generate > /dev/null 2>&1
fi

# 检查 4000 端口是否可用（Git Bash/Windows 环境）
PORT=4000
LISTENING_CHECK=$(netstat -ano 2>/dev/null | grep ":$PORT " | grep LISTENING)

if [ ! -z "$LISTENING_CHECK" ]; then
    if [ "$SILENT" = false ]; then
        echo -e "${RED}✗ 端口 $PORT 正在被监听${NC}"
        echo -e "${YELLOW}请先停止占用端口 4000 的服务：${NC}"
        echo -e "${YELLOW}  bash sh/hexo-stop.sh${NC}"
        echo -e "${YELLOW}  或 bash sh/hexo-kill.sh${NC}"
    fi
    exit 1
fi

if [ "$SILENT" = false ]; then
    echo -e "${GREEN}✓ 端口 $PORT 可用${NC}"
fi

if [ "$SILENT" = false ]; then
    echo -e "${GREEN}启动 Hexo 服务器...${NC}"
    echo -e "${YELLOW}服务器将在 http://localhost:$PORT 启动${NC}"
    echo -e "${YELLOW}按 Ctrl+C 停止服务器${NC}"
    npx hexo server --port $PORT
else
    # 静默模式：后台运行
    npx hexo server --port $PORT --silent > /dev/null 2>&1 &
    echo "Hexo server started at http://localhost:$PORT (PID: $!)"
fi