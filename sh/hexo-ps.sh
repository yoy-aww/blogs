#!/bin/bash

# Hexo 进程快速查看脚本
# 用途: 快速查看 Hexo 服务器是否在运行

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 查找 Hexo 进程
HEXO_PIDS=$(pgrep -f "hexo.*server" 2>/dev/null)

if [ ! -z "$HEXO_PIDS" ]; then
    echo -e "${GREEN}✓ Hexo 服务器正在运行${NC}"
    echo "$HEXO_PIDS" | while read pid; do
        if ps -p $pid > /dev/null 2>&1; then
            echo -e "${YELLOW}PID: $pid${NC}"
            # 尝试找到端口
            if command -v lsof > /dev/null 2>&1; then
                PORT=$(lsof -Pan -p $pid -i 2>/dev/null | grep LISTEN | awk '{print $9}' | cut -d':' -f2)
                if [ ! -z "$PORT" ]; then
                    echo -e "${YELLOW}端口: $PORT${NC}"
                    echo -e "${YELLOW}访问: http://localhost:$PORT${NC}"
                fi
            fi
        fi
    done
else
    echo -e "${RED}✗ 未找到运行中的 Hexo 服务器${NC}"
    
    # 检查常用端口
    for port in 4000 4001 4002 4003; do
        if netstat -an 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${YELLOW}⚠ 端口 $port 被其他进程占用${NC}"
            break
        fi
    done
fi