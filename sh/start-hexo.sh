#!/bin/bash

# Hexo Server 启动脚本
# 作者: 自动生成
# 用途: 启动 Hexo 开发服务器

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# 检查是否在正确的目录
if [ ! -f "_config.yml" ]; then
    echo -e "${RED}错误: 未找到 _config.yml 文件${NC}"
    echo -e "${YELLOW}当前目录: $(pwd)${NC}"
    echo -e "${YELLOW}请确保脚本在 Hexo 项目的 sh 子目录中${NC}"
    exit 1
fi

echo -e "${GREEN}工作目录: $(pwd)${NC}"

# 检查 node_modules 是否存在
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}未找到 node_modules 目录，正在安装依赖...${NC}"
    if command -v pnpm &> /dev/null; then
        pnpm install
    elif command -v npm &> /dev/null; then
        npm install
    else
        echo -e "${RED}错误: 未找到 npm 或 pnpm${NC}"
        exit 1
    fi
fi

# 清理并生成静态文件
echo -e "${GREEN}正在清理并生成静态文件...${NC}"
npx hexo clean
npx hexo generate

# 启动服务器
echo -e "${GREEN}启动 Hexo 服务器...${NC}"
echo -e "${YELLOW}服务器将在 http://localhost:4000 启动${NC}"
echo -e "${YELLOW}按 Ctrl+C 停止服务器${NC}"

npx hexo server