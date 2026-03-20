#!/bin/bash
# ═══════════════════════════════════════════════════════════
# 途正英语 - 开发环境一键配置脚本
# 火鹰科技出品
#
# 用法：
#   chmod +x setup.sh && ./setup.sh
#
# 功能：
#   1. 检测并安装 Python requests 模块（nim_core_v2 依赖）
#   2. 执行 flutter pub get
#   3. 安装 iOS/macOS CocoaPods 依赖
#   4. 验证环境就绪
# ═══════════════════════════════════════════════════════════

set -e

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   途正英语 - 开发环境一键配置                  ║"
echo "║   火鹰科技出品                                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 步骤计数
STEP=0
total_steps() { echo "[$((++STEP))/$TOTAL_STEPS]"; }
TOTAL_STEPS=5

# ─────────────────────────────────────────────────
# Step 1: 检查 Flutter
# ─────────────────────────────────────────────────
echo -e "$(total_steps) ${YELLOW}检查 Flutter SDK...${NC}"
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version 2>&1 | head -1)
    echo -e "  ${GREEN}✓${NC} $FLUTTER_VERSION"
else
    echo -e "  ${RED}✗ Flutter SDK 未安装${NC}"
    echo "  请先安装 Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi

# ─────────────────────────────────────────────────
# Step 2: 安装 Python requests（nim_core_v2 依赖）
# ─────────────────────────────────────────────────
echo ""
echo -e "$(total_steps) ${YELLOW}检查 Python requests 模块（网易云信 SDK 依赖）...${NC}"
if python3 -c "import requests" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Python requests 已安装"
else
    echo -e "  ${YELLOW}→${NC} 正在安装 Python requests..."
    if pip3 install requests --quiet 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Python requests 安装成功"
    elif python3 -m pip install requests --quiet 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Python requests 安装成功"
    else
        echo -e "  ${RED}✗ 安装失败，请手动执行: pip3 install requests${NC}"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────
# Step 3: Flutter pub get
# ─────────────────────────────────────────────────
echo ""
echo -e "$(total_steps) ${YELLOW}安装 Flutter 依赖...${NC}"
flutter pub get
echo -e "  ${GREEN}✓${NC} Flutter 依赖安装完成"

# ─────────────────────────────────────────────────
# Step 4: iOS CocoaPods（如果在 macOS 上）
# ─────────────────────────────────────────────────
echo ""
echo -e "$(total_steps) ${YELLOW}安装 iOS/macOS CocoaPods 依赖...${NC}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    if command -v pod &> /dev/null; then
        # iOS
        if [ -d "ios" ]; then
            echo "  → 安装 iOS Pods..."
            cd ios
            pod install --repo-update
            cd ..
            echo -e "  ${GREEN}✓${NC} iOS Pods 安装完成"
        fi
        # macOS
        if [ -d "macos" ]; then
            echo "  → 安装 macOS Pods..."
            cd macos
            pod install --repo-update
            cd ..
            echo -e "  ${GREEN}✓${NC} macOS Pods 安装完成"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} CocoaPods 未安装，跳过（仅影响 iOS/macOS 编译）"
        echo "  安装方法: sudo gem install cocoapods"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} 非 macOS 系统，跳过 CocoaPods 安装"
fi

# ─────────────────────────────────────────────────
# Step 5: 验证环境
# ─────────────────────────────────────────────────
echo ""
echo -e "$(total_steps) ${YELLOW}验证环境...${NC}"
flutter doctor --android-licenses 2>/dev/null || true
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║   ${GREEN}✓ 环境配置完成！${NC}                            ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║   运行方式：                                  ║"
echo "║   flutter run -d iPhone    # iOS 模拟器       ║"
echo "║   flutter run -d macos     # macOS 桌面       ║"
echo "║   flutter run -d chrome    # Web 浏览器       ║"
echo "║   flutter run -d emulator  # Android 模拟器   ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
