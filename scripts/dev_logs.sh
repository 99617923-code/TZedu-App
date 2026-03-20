#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 查看开发日志
# 火鹰科技出品
#
# 用法：
#   ./scripts/dev_logs.sh           # 查看所有日志（最后20行）
#   ./scripts/dev_logs.sh android   # 实时跟踪 Android 日志
#   ./scripts/dev_logs.sh ios       # 实时跟踪 iOS 日志
#   ./scripts/dev_logs.sh macos     # 实时跟踪 macOS 日志
#   ./scripts/dev_logs.sh watcher   # 实时跟踪自动拉取日志
#   ./scripts/dev_logs.sh all       # 实时跟踪所有日志
# ═══════════════════════════════════════════════════════════════

PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/.dev_logs"

if [ ! -d "$LOG_DIR" ]; then
    echo -e "${YELLOW}暂无日志文件${NC}"
    exit 0
fi

case "${1:-summary}" in
    android)
        echo -e "${PURPLE}${BOLD}  实时跟踪 Android 日志（Ctrl+C 退出）${NC}\n"
        tail -f "$LOG_DIR/android.log" 2>/dev/null || echo "Android 日志不存在"
        ;;
    ios)
        echo -e "${PURPLE}${BOLD}  实时跟踪 iOS 日志（Ctrl+C 退出）${NC}\n"
        tail -f "$LOG_DIR/ios.log" 2>/dev/null || echo "iOS 日志不存在"
        ;;
    macos)
        echo -e "${PURPLE}${BOLD}  实时跟踪 macOS 日志（Ctrl+C 退出）${NC}\n"
        tail -f "$LOG_DIR/macos.log" 2>/dev/null || echo "macOS 日志不存在"
        ;;
    watcher)
        echo -e "${PURPLE}${BOLD}  实时跟踪代码自动拉取日志（Ctrl+C 退出）${NC}\n"
        tail -f "$LOG_DIR/watcher.log" 2>/dev/null || echo "Watcher 日志不存在"
        ;;
    all)
        echo -e "${PURPLE}${BOLD}  实时跟踪所有日志（Ctrl+C 退出）${NC}\n"
        tail -f "$LOG_DIR"/*.log 2>/dev/null || echo "暂无日志"
        ;;
    summary|*)
        echo -e "\n${PURPLE}${BOLD}  途正英语 App - 开发日志摘要${NC}\n"

        for logfile in android ios macos watcher; do
            if [ -f "$LOG_DIR/${logfile}.log" ]; then
                local size=$(du -h "$LOG_DIR/${logfile}.log" 2>/dev/null | cut -f1)
                echo -e "  ${BOLD}─── $logfile ($size) ───${NC}"
                tail -10 "$LOG_DIR/${logfile}.log" 2>/dev/null | while read line; do
                    echo -e "  ${CYAN}$line${NC}"
                done
                echo ""
            fi
        done

        echo -e "  ${YELLOW}提示: 使用 ./scripts/dev_logs.sh <android|ios|macos|watcher> 实时跟踪日志${NC}\n"
        ;;
esac
