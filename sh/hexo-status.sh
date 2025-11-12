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

# 检查端口 4000 占用情况
echo -e "${BLUE}=== 端口 4000 状态检查 ===${NC}"
port=4000

# 检查端口监听状态（Linux 环境）
# 使用 Linux netstat 或 ss 命令检查端口
if command -v ss > /dev/null 2>&1; then
    # 优先使用 ss 命令（现代 Linux 系统）
    LISTENING_CHECK=$(ss -tlnp 2>/dev/null | grep ":$port ")
    if [ ! -z "$LISTENING_CHECK" ]; then
        echo -e "${GREEN}✓ 端口 $port 正在监听${NC}"
        
        # 从 ss 输出获取进程信息
        PROCESS_INFO=$(echo "$LISTENING_CHECK" | grep -o 'users:(([^)]*))' | sed 's/users:((\([^)]*\)))/\1/')
        if [ ! -z "$PROCESS_INFO" ]; then
            PROCESS_NAME=$(echo "$PROCESS_INFO" | cut -d',' -f1 | tr -d '"')
            PROCESS_PID=$(echo "$PROCESS_INFO" | cut -d',' -f2)
            echo -e "  ${YELLOW}进程名称: $PROCESS_NAME${NC}"
            echo -e "  ${YELLOW}进程 PID: $PROCESS_PID${NC}"
            
            # 获取完整命令行
            if [ ! -z "$PROCESS_PID" ] && [ -f "/proc/$PROCESS_PID/cmdline" ]; then
                CMDLINE=$(cat /proc/$PROCESS_PID/cmdline 2>/dev/null | tr '\0' ' ')
                if [ ! -z "$CMDLINE" ]; then
                    echo -e "  ${YELLOW}命令行: $CMDLINE${NC}"
                fi
            fi
        fi
    else
        echo -e "${GREEN}✓ 端口 $port 完全空闲${NC}"
    fi
elif command -v netstat > /dev/null 2>&1; then
    # 使用传统的 netstat 命令
    LISTENING_CHECK=$(netstat -tlnp 2>/dev/null | grep ":$port ")
    if [ ! -z "$LISTENING_CHECK" ]; then
        echo -e "${GREEN}✓ 端口 $port 正在监听${NC}"
        
        # 从 netstat 输出获取 PID 和进程名
        PROCESS_INFO=$(echo "$LISTENING_CHECK" | awk '{print $7}' | head -1)
        if [ ! -z "$PROCESS_INFO" ] && [ "$PROCESS_INFO" != "-" ]; then
            PROCESS_PID=$(echo "$PROCESS_INFO" | cut -d'/' -f1)
            PROCESS_NAME=$(echo "$PROCESS_INFO" | cut -d'/' -f2)
            echo -e "  ${YELLOW}进程 PID: $PROCESS_PID${NC}"
            echo -e "  ${YELLOW}进程名称: $PROCESS_NAME${NC}"
            
            # 获取完整命令行
            if [ ! -z "$PROCESS_PID" ] && [ -f "/proc/$PROCESS_PID/cmdline" ]; then
                CMDLINE=$(cat /proc/$PROCESS_PID/cmdline 2>/dev/null | tr '\0' ' ')
                if [ ! -z "$CMDLINE" ]; then
                    echo -e "  ${YELLOW}命令行: $CMDLINE${NC}"
                fi
            fi
        fi
    else
        echo -e "${GREEN}✓ 端口 $port 完全空闲${NC}"
    fi
else
    # 如果没有 ss 和 netstat，使用 lsof 作为备选
    if command -v lsof > /dev/null 2>&1; then
        LISTENING_CHECK=$(lsof -i :$port 2>/dev/null)
        if [ ! -z "$LISTENING_CHECK" ]; then
            echo -e "${GREEN}✓ 端口 $port 正在监听${NC}"
            echo -e "${YELLOW}进程信息:${NC}"
            echo "$LISTENING_CHECK" | tail -n +2 | while read line; do
                PROCESS_NAME=$(echo $line | awk '{print $1}')
                PROCESS_PID=$(echo $line | awk '{print $2}')
                echo -e "  ${YELLOW}进程名称: $PROCESS_NAME, PID: $PROCESS_PID${NC}"
            done
        else
            echo -e "${GREEN}✓ 端口 $port 完全空闲${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ 无法检查端口状态（缺少 ss/netstat/lsof 命令）${NC}"
    fi
fi

echo

# 检查网络连接
echo -e "${BLUE}=== 网络连接测试 ===${NC}"
port=4000
if curl -s --connect-timeout 2 http://localhost:$port > /dev/null 2>&1; then
    echo -e "${GREEN}✓ http://localhost:$port 可访问${NC}"
    # 尝试获取页面标题
    TITLE=$(curl -s --connect-timeout 2 http://localhost:$port | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' 2>/dev/null)
    if [ ! -z "$TITLE" ]; then
        echo -e "  ${YELLOW}页面标题: $TITLE${NC}"
    fi
else
    echo -e "${RED}✗ http://localhost:$port 无法访问${NC}"
fi

echo
echo -e "${BLUE}=== 快速操作 ===${NC}"
echo -e "${YELLOW}启动服务器: bash sh/hexo-start.sh${NC}"
echo -e "${YELLOW}静默启动: bash sh/hexo-silent.sh${NC}"
echo -e "${YELLOW}停止服务器: bash sh/hexo-stop.sh${NC}"
echo -e "${YELLOW}查看状态: bash sh/hexo-status.sh${NC}"
echo -e "${YELLOW}快速检查: bash sh/hexo-ps.sh${NC}"