#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 查看开发环境运行状态
# 火鹰科技出品
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/.dev_pids"
LOG_DIR="$PROJECT_DIR/.dev_logs"

echo -e "\n${PURPLE}${BOLD}  途正英语 App - 开发环境状态${NC}\n"

# 检查各端状态
check_status() {
    local name="$1"
    local pid_file="$PID_DIR/${2}_process.pid"
    local log_file="$LOG_DIR/${2}.log"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} ${BOLD}$name${NC}  运行中 (PID: $pid)"
            # 显示最后一行日志
            if [ -f "$log_file" ]; then
                local last_line=$(tail -1 "$log_file" 2>/dev/null | head -c 80)
                if [ -n "$last_line" ]; then
                    echo -e "    └─ ${CYAN}$last_line${NC}"
                fi
            fi
            return 0
        else
            echo -e "  ${RED}●${NC} ${BOLD}$name${NC}  已停止（进程不存在）"
            return 1
        fi
    else
        echo -e "  ${YELLOW}○${NC} ${BOLD}$name${NC}  未启动"
        return 1
    fi
}

echo -e "  ${BOLD}─── 应用端 ───${NC}"
check_status "Android 模拟器" "android"
check_status "iOS 模拟器    " "ios"
check_status "macOS 桌面端  " "macos"

echo ""
echo -e "  ${BOLD}─── 守护进程 ───${NC}"

# 检查 watcher
if [ -f "$PID_DIR/watcher.pid" ]; then
    wpid=$(cat "$PID_DIR/watcher.pid")
    if kill -0 "$wpid" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} ${BOLD}代码自动拉取${NC}  运行中 (PID: $wpid, 间隔: 30秒)"
        # 显示最后一次拉取记录
        if [ -f "$LOG_DIR/watcher.log" ]; then
            local last_update=$(grep "✓" "$LOG_DIR/watcher.log" 2>/dev/null | tail -1)
            if [ -n "$last_update" ]; then
                echo -e "    └─ ${CYAN}$last_update${NC}"
            fi
        fi
    else
        echo -e "  ${RED}●${NC} ${BOLD}代码自动拉取${NC}  已停止"
    fi
else
    echo -e "  ${YELLOW}○${NC} ${BOLD}代码自动拉取${NC}  未启动"
fi

# Git 状态
echo ""
echo -e "  ${BOLD}─── Git 状态 ───${NC}"
cd "$PROJECT_DIR"
local_hash=$(git rev-parse --short HEAD 2>/dev/null)
branch=$(git branch --show-current 2>/dev/null)
echo -e "  分支: ${CYAN}$branch${NC}  提交: ${CYAN}$local_hash${NC}"
last_msg=$(git log --oneline -1 2>/dev/null)
echo -e "  最新: ${CYAN}$last_msg${NC}"

echo ""
