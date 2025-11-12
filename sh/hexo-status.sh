#!/bin/bash

# Hexo Server 状态检查脚本
# 作者: 自动生成
# 用途: 查看 Hexo 开发服务器运行状态

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录并切换到 Hexo 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

echo -e "${BLUE}=== Hexo 服务器状态检查 ===${NC}"
echo

# 检查日志文件
if [ -f "hexo-server.log" ]; then
    echo -e "${GREEN}✓ 找到服务器日志文件${NC}"
    echo -e "${YELLOW}日志内容:${NC}"
    cat hexo-server.log
    echo
    
    # 从日志文件获取 PID
    PID=$(grep "PID:" hexo-server.log 2>/dev/null | cut -d' ' -f2)
    if [ ! -z "$PID" ]; then
        # 检查进程是否还在运行
        if ps -p $PID > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 服务器正在运行 (PID: $PID)${NC}"
        else
            echo -e "${RED}✗ 服务器进程已停止 (PID: $PID 不存在)${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ 未找到服务器日志文件${NC}"
fi

echo

# 查找所有 hexo server 进程
echo -e "${BLUE}=== 所有 Hexo 进程 ===${NC}"
HEXO_PROCESSES=$(ps aux 2>/dev/null | grep -E "hexo.*server|node.*hexo" | grep -v grep)

if [ ! -z "$HEXO_PROCESSES" ]; then
    echo -e "${GREEN}找到以下 Hexo 进程:${NC}"
    echo "$HEXO_PROCESSES" | while read line; do
        PID=$(echo $line | awk '{print $2}')
        echo -e "${YELLOW}PID: $PID${NC} - $line"
    done
else
    echo -e "${RED}✗ 未找到运行中的 Hexo 进程${NC}"
fi

echo

# 检查端口占用情况
echo -e "${BLUE}=== 端口占用检查 ===${NC}"
for port in 4000 4001 4002 4003 4004; do
    if netstat -an 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓ 端口 $port 被占用${NC}"
        # 尝试找到占用端口的进程
        if command -v lsof > /dev/null 2>&1; then
            PROCESS=$(lsof -ti:$port 2>/dev/null)
            if [ ! -z "$PROCESS" ]; then
                echo -e "  ${YELLOW}进程 PID: $PROCESS${NC}"
            fi
        elif command -v netstat > /dev/null 2>&1; then
            PROCESS=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
            if [ ! -z "$PROCESS" ]; then
                echo -e "  ${YELLOW}进程 PID: $PROCESS${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ 端口 $port 空闲${NC}"
    fi
done

echo

# 检查网络连接
echo -e "${BLUE}=== 网络连接测试 ===${NC}"
for port in 4000 4001 4002 4003 4004; do
    if curl -s --connect-timeout 2 http://localhost:$port > /dev/null 2>&1; then
        echo -e "${GREEN}✓ http://localhost:$port 可访问${NC}"
        # 尝试获取页面标题
        TITLE=$(curl -s --connect-timeout 2 http://localhost:$port | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' 2>/dev/null)
        if [ ! -z "$TITLE" ]; then
            echo -e "  ${YELLOW}页面标题: $TITLE${NC}"
        fi
        break
    else
        echo -e "${RED}✗ http://localhost:$port 无法访问${NC}"
    fi
done

echo
echo -e "${BLUE}=== 快速操作 ===${NC}"
echo -e "${YELLOW}启动服务器: bash sh/hexo-start.sh${NC}"
echo -e "${YELLOW}静默启动: bash sh/hexo-silent.sh${NC}"
echo -e "${YELLOW}停止服务器: bash sh/hexo-stop.sh${NC}"
echo -e "${YELLOW}查看状态: bash sh/hexo-status.sh${NC}"
echo -e "${YELLOW}快速检查: bash sh/hexo-ps.sh${NC}"