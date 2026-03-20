#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 清理并全量重建
# 火鹰科技出品
#
# 当遇到编译错误或依赖问题时使用此脚本
# 会执行 flutter clean + pub get + pod install，然后重新启动
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "\n${PURPLE}${BOLD}  途正英语 App - 清理并全量重建${NC}\n"

# 先停止所有运行中的端
echo -e "${YELLOW}[1/6] 停止运行中的开发端...${NC}"
bash "$SCRIPT_DIR/dev_stop.sh" 2>/dev/null

# 拉取最新代码
echo -e "${YELLOW}[2/6] 拉取最新代码...${NC}"
cd "$PROJECT_DIR"
git pull origin main --no-edit 2>&1 | head -5
echo -e "${GREEN}  ✓ 代码已更新${NC}"

# Flutter clean
echo -e "${YELLOW}[3/6] 执行 flutter clean...${NC}"
cd "$PROJECT_DIR"
flutter clean 2>&1 | tail -3
echo -e "${GREEN}  ✓ 清理完成${NC}"

# Flutter pub get
echo -e "${YELLOW}[4/6] 执行 flutter pub get...${NC}"
flutter pub get 2>&1 | tail -5
echo -e "${GREEN}  ✓ 依赖安装完成${NC}"

# iOS pod install
echo -e "${YELLOW}[5/6] 执行 iOS pod install...${NC}"
cd "$PROJECT_DIR/ios"
pod install 2>&1 | tail -5
cd "$PROJECT_DIR"
echo -e "${GREEN}  ✓ iOS Pods 安装完成${NC}"

# macOS pod install
echo -e "${YELLOW}[6/6] 执行 macOS pod install...${NC}"
cd "$PROJECT_DIR/macos"
pod install 2>&1 | tail -5
cd "$PROJECT_DIR"
echo -e "${GREEN}  ✓ macOS Pods 安装完成${NC}"

echo -e "\n${GREEN}${BOLD}  ✓ 全量重建完成！${NC}"
echo -e "  ${BLUE}现在可以执行 ./scripts/dev_start.sh 启动开发环境${NC}\n"

# 询问是否直接启动
read -p "  是否立即启动开发环境？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/dev_start.sh" "$@"
fi
