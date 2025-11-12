#!/bin/bash

# Hexo Server 后台启动脚本
# 作者: 自动生成
# 用途: 启动 Hexo 开发服务器并在后台运行

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}=== Hexo 后台启动 ===${NC}"
echo -e "${YELLOW}项目目录: $PROJECT_ROOT${NC}"

cd "$PROJECT_ROOT" || {
    echo -e "${RED}错误: 无法切换到项目根目录${NC}"
    exit 1
}

# 检查配置文件
if [ ! -f "_config.yml" ]; then
    echo -e "${RED}错误: 未找到 _config.yml 文件${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 找到 Hexo 配置文件${NC}"

# 检查并安装依赖
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}正在安装依赖...${NC}"
    if command -v pnpm &> /dev/null; then
        pnpm install
    elif command -v npm &> /dev/null; then
        npm install
    else
        echo -e "${RED}错误: 未找到 npm 或 pnpm${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
else
    echo -e "${GREEN}✓ 依赖已存在${NC}"
fi

# 清理并生成静态文件
echo -e "${YELLOW}正在清理并生成静态文件...${NC}"
npx hexo clean
npx hexo generate
echo -e "${GREEN}✓ 静态文件生成完成${NC}"

# 查找可用端口
PORT=4000
echo -e "${YELLOW}正在查找可用端口...${NC}"
while netstat -an 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; do
    echo -e "${YELLOW}端口 $PORT 已被占用，尝试 $((PORT+1))...${NC}"
    PORT=$((PORT+1))
done

echo -e "${GREEN}✓ 使用端口: $PORT${NC}"

# 启动服务器（后台运行）
echo -e "${YELLOW}正在启动 Hexo 服务器...${NC}"
npx hexo server --port $PORT > hexo-server.log 2>&1 &
SERVER_PID=$!

# 等待一下确保服务器启动
sleep 2

# 检查服务器是否成功启动
if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Hexo 服务器已启动${NC}"
    echo -e "${BLUE}服务器信息:${NC}"
    echo -e "  ${YELLOW}URL: http://localhost:$PORT${NC}"
    echo -e "  ${YELLOW}PID: $SERVER_PID${NC}"
    echo -e "  ${YELLOW}日志文件: hexo-server.log${NC}"
    echo -e "  ${YELLOW}启动时间: $(date)${NC}"
    
    # 保存服务器信息到文件
    cat > hexo-server.log << EOF
Hexo server started at http://localhost:$PORT
PID: $SERVER_PID
Started at: $(date)
Status: Running in background

=== Server Output ===
EOF
    
    # 将服务器输出追加到日志文件
    npx hexo server --port $PORT >> hexo-server.log 2>&1 &
    
    echo -e "${GREEN}✓ 服务器正在后台运行${NC}"
    echo -e "${BLUE}使用以下命令管理服务器:${NC}"
    echo -e "  ${YELLOW}查看状态: bash sh/hexo-status.sh${NC}"
    echo -e "  ${YELLOW}停止服务器: bash sh/hexo-stop.sh${NC}"
    echo -e "  ${YELLOW}查看日志: tail -f hexo-server.log${NC}"
else
    echo -e "${RED}✗ 服务器启动失败${NC}"
    exit 1
fi