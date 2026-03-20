#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 一键重启开发环境
# 火鹰科技出品
#
# 用法：
#   ./scripts/dev_restart.sh          # 重启全部三端
#   ./scripts/dev_restart.sh android  # 只重启 Android
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "\n\033[1;33m  正在重启开发环境...\033[0m\n"

# 先停止
bash "$SCRIPT_DIR/dev_stop.sh"

# 等待进程完全退出
sleep 2

# 再启动
bash "$SCRIPT_DIR/dev_start.sh" "$@"
