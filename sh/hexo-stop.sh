#!/bin/bash

# Hexo Server 停止脚本
# 作者: 自动生成
# 用途: 停止 Hexo 开发服务器

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

echo -e "${BLUE}=== 停止 Hexo 服务器 ===${NC}"

STOPPED=false

# 方法1: 检查日志文件中的 PID
if [ -f "hexo-server.log" ]; then
    echo -e "${YELLOW}检查日志文件中的 PID...${NC}"
    PID=$(grep "PID:" hexo-server.log 2>/dev/null | tail -1 | cut -d' ' -f2)
    if [ ! -z "$PID" ]; then
        echo -e "${YELLOW}找到 PID: $PID${NC}"
        if ps -p $PID > /dev/null 2>&1; then
            kill $PID 2>/dev/null
            sleep 2
            if ps -p $PID > /dev/null 2>&1; then
                kill -9 $PID 2>/dev/null
                echo -e "${GREEN}✓ 强制停止进程 $PID${NC}"
            else
                echo -e "${GREEN}✓ 优雅停止进程 $PID${NC}"
            fi
            STOPPED=true
        else
            echo -e "${YELLOW}进程 $PID 已不存在${NC}"
        fi
    fi
    rm -f hexo-server.log
fi

# 方法2: 检查 4000 端口并停止进程
echo -e "${YELLOW}检查端口 4000 占用情况...${NC}"
port=4000
LISTENING_CHECK=$(netstat -tuln 2>/dev/null | grep ":$port " || ss -tuln 2>/dev/null | grep ":$port ")

if [ ! -z "$LISTENING_CHECK" ]; then
    echo -e "${YELLOW}端口 $port 被占用，查找进程...${NC}"
    
    # Linux 优先方法：使用 lsof
    if command -v lsof > /dev/null 2>&1; then
        PID=$(lsof -ti:$port 2>/dev/null)
        if [ ! -z "$PID" ]; then
            echo -e "${YELLOW}找到占用端口 $port 的进程 PID: $PID${NC}"
            # 尝试优雅停止
            kill -TERM $PID 2>/dev/null
            sleep 2
            # 检查是否还在运行
            if ps -p $PID > /dev/null 2>&1; then
                # 强制停止
                kill -KILL $PID 2>/dev/null
                echo -e "${GREEN}✓ 强制停止进程 $PID${NC}"
            else
                echo -e "${GREEN}✓ 优雅停止进程 $PID${NC}"
            fi
            STOPPED=true
        fi
    # 备用方法：使用 fuser
    elif command -v fuser > /dev/null 2>&1; then
        PID=$(fuser $port/tcp 2>/dev/null | awk '{print $1}')
        if [ ! -z "$PID" ]; then
            echo -e "${YELLOW}找到占用端口 $port 的进程 PID: $PID${NC}"
            kill -TERM $PID 2>/dev/null
            sleep 2
            if ps -p $PID > /dev/null 2>&1; then
                kill -KILL $PID 2>/dev/null
                echo -e "${GREEN}✓ 强制停止进程 $PID${NC}"
            else
                echo -e "${GREEN}✓ 优雅停止进程 $PID${NC}"
            fi
            STOPPED=true
        fi
    # Windows 方法（如果在 WSL 中）
    elif command -v netstat > /dev/null 2>&1; then
        PID=$(netstat -tulpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        if [ ! -z "$PID" ] && [ "$PID" != "-" ]; then
            echo -e "${YELLOW}找到占用端口 $port 的进程 PID: $PID${NC}"
            kill -TERM $PID 2>/dev/null
            sleep 2
            if ps -p $PID > /dev/null 2>&1; then
                kill -KILL $PID 2>/dev/null
                echo -e "${GREEN}✓ 强制停止进程 $PID${NC}"
            else
                echo -e "${GREEN}✓ 优雅停止进程 $PID${NC}"
            fi
            STOPPED=true
        fi
    fi
else
    echo -e "${GREEN}✓ 端口 4000 未被占用${NC}"
fi

# 方法3: 查找所有 Node.js 进程中包含 hexo 的
echo -e "${YELLOW}查找所有 Hexo 相关进程...${NC}"
if command -v ps > /dev/null 2>&1; then
    # 查找包含 hexo 和 server 的进程
    HEXO_PIDS=$(ps aux 2>/dev/null | grep -E "(hexo.*server|node.*hexo)" | grep -v grep | awk '{print $2}')
    if [ ! -z "$HEXO_PIDS" ]; then
        echo "$HEXO_PIDS" | while read pid; do
            if [ ! -z "$pid" ] && ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null
                echo -e "${GREEN}✓ 停止 Hexo 进程 $pid${NC}"
                STOPPED=true
            fi
        done
    fi
fi

# 方法4: Windows 特定方法 - 通过任务名称
if command -v tasklist > /dev/null 2>&1; then
    echo -e "${YELLOW}使用 Windows tasklist 查找 Node.js 进程...${NC}"
    # 查找所有 node.exe 进程
    NODE_PIDS=$(tasklist /FI "IMAGENAME eq node.exe" /FO CSV 2>/dev/null | grep -v "PID" | cut -d',' -f2 | tr -d '"')
    if [ ! -z "$NODE_PIDS" ]; then
        echo "$NODE_PIDS" | while read pid; do
            if [ ! -z "$pid" ]; then
                # 检查这个 Node.js 进程是否是 Hexo
                CMDLINE=$(wmic process where "ProcessId=$pid" get CommandLine /format:list 2>/dev/null | grep "CommandLine=" | cut -d'=' -f2-)
                if echo "$CMDLINE" | grep -q "hexo"; then
                    taskkill /PID $pid /F > /dev/null 2>&1
                    echo -e "${GREEN}✓ 停止 Hexo Node.js 进程 $pid${NC}"
                    STOPPED=true
                fi
            fi
        done
    fi
fi

# 方法5: 使用 pkill (如果可用)
if command -v pkill > /dev/null 2>&1; then
    if pkill -f "hexo.*server" 2>/dev/null; then
        echo -e "${GREEN}✓ 使用 pkill 停止了 Hexo 进程${NC}"
        STOPPED=true
    fi
fi

echo
if [ "$STOPPED" = true ]; then
    echo -e "${GREEN}✓ Hexo 服务器已停止${NC}"
    # 验证端口 4000 是否已释放
    sleep 1
    echo -e "${YELLOW}验证端口 4000 状态...${NC}"
    if ! netstat -an 2>/dev/null | grep -q ":4000 "; then
        echo -e "${GREEN}✓ 端口 4000 已释放${NC}"
    else
        echo -e "${RED}✗ 端口 4000 仍被占用${NC}"
    fi
else
    echo -e "${RED}✗ 未找到运行中的 Hexo 服务器${NC}"
    echo -e "${YELLOW}如果服务器仍在运行，请尝试手动停止：${NC}"
    echo -e "${YELLOW}  Windows: 在任务管理器中结束 node.exe 进程${NC}"
    echo -e "${YELLOW}  或使用: taskkill /F /IM node.exe${NC}"
fi