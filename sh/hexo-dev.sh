#!/bin/bash

# Hexo 开发环境脚本
# 支持多种操作模式

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
PORT=4000
DRAFT=false
WATCH=true

# 显示帮助信息
show_help() {
    echo -e "${BLUE}Hexo 开发服务器脚本${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -p, --port PORT     指定端口 (默认: 4000)"
    echo "  -d, --draft         包含草稿文章"
    echo "  -s, --static        仅生成静态文件，不启动服务器"
    echo "  -c, --clean         清理缓存后重新生成"
    echo "  -w, --no-watch      禁用文件监听"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                  # 启动默认服务器"
    echo "  $0 -p 3000          # 在端口 3000 启动"
    echo "  $0 -d -p 3000       # 包含草稿，端口 3000"
    echo "  $0 -s               # 仅生成静态文件"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--draft)
            DRAFT=true
            shift
            ;;
        -s|--static)
            STATIC_ONLY=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -w|--no-watch)
            WATCH=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# 检查环境
check_environment() {
    if [ ! -f "_config.yml" ]; then
        echo -e "${RED}错误: 未找到 _config.yml 文件${NC}"
        echo -e "${YELLOW}请在 Hexo 项目根目录下运行此脚本${NC}"
        exit 1
    fi

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
    fi
}

# 清理和生成
build_site() {
    if [ "$CLEAN" = true ]; then
        echo -e "${GREEN}清理缓存...${NC}"
        npx hexo clean
    fi

    echo -e "${GREEN}生成静态文件...${NC}"
    if [ "$DRAFT" = true ]; then
        npx hexo generate --draft
    else
        npx hexo generate
    fi
}

# 启动服务器
start_server() {
    echo -e "${GREEN}启动 Hexo 服务器...${NC}"
    echo -e "${BLUE}服务器地址: http://localhost:$PORT${NC}"
    echo -e "${YELLOW}按 Ctrl+C 停止服务器${NC}"
    echo ""

    SERVER_ARGS="--port $PORT"
    
    if [ "$DRAFT" = true ]; then
        SERVER_ARGS="$SERVER_ARGS --draft"
    fi
    
    if [ "$WATCH" = false ]; then
        SERVER_ARGS="$SERVER_ARGS --static"
    fi

    npx hexo server $SERVER_ARGS
}

# 主执行流程
main() {
    echo -e "${BLUE}=== Hexo 开发环境 ===${NC}"
    
    check_environment
    build_site
    
    if [ "$STATIC_ONLY" = true ]; then
        echo -e "${GREEN}静态文件生成完成！${NC}"
        exit 0
    fi
    
    start_server
}

# 捕获中断信号
trap 'echo -e "\n${YELLOW}服务器已停止${NC}"; exit 0' INT

# 运行主函数
main