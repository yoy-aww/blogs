#!/bin/bash

# Hexo Server 静默启动脚本
# 作者: 自动生成
# 用途: 静默启动 Hexo 开发服务器

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

# 静默检查配置文件
if [ ! -f "_config.yml" ]; then
    exit 1
fi

# 静默安装依赖（如果需要）
if [ ! -d "node_modules" ]; then
    if command -v pnpm &> /dev/null; then
        pnpm install > /dev/null 2>&1
    elif command -v npm &> /dev/null; then
        npm install > /dev/null 2>&1
    else
        exit 1
    fi
fi

# 静默清理并生成
npx hexo clean > /dev/null 2>&1
npx hexo generate > /dev/null 2>&1

# 查找可用端口
PORT=4000
while netstat -an 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; do
    PORT=$((PORT+1))
done

# 静默启动服务器
npx hexo server --port $PORT --silent > /dev/null 2>&1 &

# 输出服务器信息到文件
echo "Hexo server started at http://localhost:$PORT" > hexo-server.log
echo "PID: $!" >> hexo-server.log
echo "Started at: $(date)" >> hexo-server.log

# 输出 PID 以便后续管理
echo $!