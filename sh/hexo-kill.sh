#!/bin/bash

# Hexo Server 强制停止脚本
# 作者: 自动生成
# 用途: 强制停止所有占用 4000-4010 端口的进程

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== 强制停止端口 4000 占用进程 ===${NC}"
echo -e "${RED}警告: 这将强制停止占用端口 4000 的进程${NC}"

KILLED=false

# 检查并强制停止占用端口 4000 的进程
port=4000
if netstat -an 2>/dev/null | grep -q ":$port "; then
    echo -e "${YELLOW}端口 $port 被占用，正在强制停止...${NC}"
    
    # Windows 方法
    if command -v netstat > /dev/null 2>&1; then
        PID=$(netstat -ano 2>/dev/null | grep ":$port " | grep LISTENING | awk '{print $5}' | head -1)
        if [ ! -z "$PID" ]; then
            echo -e "${YELLOW}找到进程 PID: $PID${NC}"
            if command -v taskkill > /dev/null 2>&1; then
                taskkill /PID $PID /F > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ 强制停止进程 $PID (端口 $port)${NC}"
                    KILLED=true
                else
                    echo -e "${RED}✗ 无法停止进程 $PID${NC}"
                fi
            fi
        fi
    fi
    
    # Linux/Mac 方法
    if command -v lsof > /dev/null 2>&1; then
        PID=$(lsof -ti:$port 2>/dev/null)
        if [ ! -z "$PID" ]; then
            echo -e "${YELLOW}找到进程 PID: $PID${NC}"
            kill -9 $PID 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 强制停止进程 $PID (端口 $port)${NC}"
                KILLED=true
            fi
        fi
    fi
else
    echo -e "${GREEN}✓ 端口 4000 未被占用${NC}"
fi

# 额外方法：停止所有 Node.js 进程（谨慎使用）
read -p "是否要停止所有 Node.js 进程? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}正在停止所有 Node.js 进程...${NC}"
    if command -v taskkill > /dev/null 2>&1; then
        taskkill /F /IM node.exe > /dev/null 2>&1
        echo -e "${GREEN}✓ 已停止所有 Node.js 进程${NC}"
        KILLED=true
    elif command -v pkill > /dev/null 2>&1; then
        pkill -f node
        echo -e "${GREEN}✓ 已停止所有 Node.js 进程${NC}"
        KILLED=true
    fi
fi

echo
if [ "$KILLED" = true ]; then
    echo -e "${GREEN}✓ 进程已强制停止${NC}"
    echo -e "${YELLOW}等待端口释放...${NC}"
    sleep 2
    
    # 验证端口 4000 状态
    echo -e "${YELLOW}验证端口 4000 状态:${NC}"
    if netstat -an 2>/dev/null | grep -q ":4000 "; then
        echo -e "${RED}✗ 端口 4000 仍被占用${NC}"
    else
        echo -e "${GREEN}✓ 端口 4000 已释放${NC}"
    fi
else
    echo -e "${YELLOW}未执行任何停止操作${NC}"
fi

echo
echo -e "${BLUE}提示:${NC}"
echo -e "${YELLOW}  如果端口仍被占用，可能是其他应用程序在使用${NC}"
echo -e "${YELLOW}  请检查任务管理器或使用 netstat -ano 查看详情${NC}"