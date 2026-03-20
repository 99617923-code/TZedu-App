#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 一键停止所有开发端
# 火鹰科技出品
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/.dev_pids"
LOG_DIR="$PROJECT_DIR/.dev_logs"

echo -e "\n${YELLOW}${BOLD}  停止所有开发端...${NC}\n"

stopped=0

# 停止 watcher 守护进程
if [ -f "$PID_DIR/watcher.pid" ]; then
    pid=$(cat "$PID_DIR/watcher.pid")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo -e "  ${RED}■${NC} 代码自动拉取守护进程已停止 (PID: $pid)"
        stopped=$((stopped + 1))
    fi
    rm -f "$PID_DIR/watcher.pid"
fi

# 停止各端 flutter 进程
for platform in android ios macos; do
    pid_file="$PID_DIR/${platform}_process.pid"
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            # 先发送 'q' 退出信号，再 kill
            kill "$pid" 2>/dev/null
            # 等待进程退出
            for i in {1..5}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # 如果还没退出，强制 kill
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null
            fi
            echo -e "  ${RED}■${NC} $platform 端已停止 (PID: $pid)"
            stopped=$((stopped + 1))
        fi
        rm -f "$pid_file"
    fi

    # 清理 flutter pid 文件
    flutter_pid_file="$PID_DIR/${platform}.pid"
    if [ -f "$flutter_pid_file" ]; then
        fpid=$(cat "$flutter_pid_file")
        kill "$fpid" 2>/dev/null || true
        rm -f "$flutter_pid_file"
    fi
done

# 清理 watcher 运行脚本
rm -f "$PID_DIR/watcher_run.sh"

if [ $stopped -eq 0 ]; then
    echo -e "  ${YELLOW}没有运行中的开发端${NC}"
else
    echo -e "\n${GREEN}${BOLD}  ✓ 已停止 $stopped 个进程${NC}\n"
fi
