#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 - 开发启动器 一键安装
# 火鹰科技出品
#
# 用法：cd ~/TZedu-App/tools/TZDevLauncher && ./install.sh
# ═══════════════════════════════════════════════════════════════

set -e

PURPLE='\033[0;35m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="途正开发启动器"
APP_DIR="$HOME/Desktop/${APP_NAME}.app"

echo -e "\n${PURPLE}${BOLD}  ╔═══════════════════════════════════════╗${NC}"
echo -e "${PURPLE}${BOLD}  ║   途正英语 - 开发启动器 安装程序     ║${NC}"
echo -e "${PURPLE}${BOLD}  ║   火鹰科技出品                       ║${NC}"
echo -e "${PURPLE}${BOLD}  ╚═══════════════════════════════════════╝${NC}\n"

# 检查 Xcode 命令行工具
if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}  ✗ 未找到 swiftc 编译器${NC}"
    echo -e "${YELLOW}  请先安装 Xcode 或 Xcode Command Line Tools:${NC}"
    echo -e "${CYAN}  xcode-select --install${NC}"
    exit 1
fi

echo -e "${CYAN}  [1/4] 清理旧版本...${NC}"
if [ -d "$APP_DIR" ]; then
    rm -rf "$APP_DIR"
    echo -e "  已删除旧版本"
fi

echo -e "${CYAN}  [2/4] 编译 Swift 原生应用...${NC}"

# 使用 xcodebuild 或直接 swiftc 编译
# 方案：直接用 swiftc 编译单文件 SwiftUI 应用
SWIFT_SOURCE="$SCRIPT_DIR/Sources/TZDevLauncherApp.swift"
BUILD_DIR="$SCRIPT_DIR/.build"
mkdir -p "$BUILD_DIR"

# 编译
swiftc \
    -o "$BUILD_DIR/TZDevLauncher" \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path --sdk macosx) \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library \
    "$SWIFT_SOURCE" \
    2>&1 | head -20

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${YELLOW}  ARM64 编译失败，尝试通用编译...${NC}"
    swiftc \
        -o "$BUILD_DIR/TZDevLauncher" \
        -sdk $(xcrun --show-sdk-path --sdk macosx) \
        -framework SwiftUI \
        -framework AppKit \
        -parse-as-library \
        "$SWIFT_SOURCE"
fi

echo -e "  编译成功 ✓"

echo -e "${CYAN}  [3/4] 打包 .app 应用...${NC}"

# 创建 .app 结构
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制可执行文件
cp "$BUILD_DIR/TZDevLauncher" "$MACOS_DIR/"

# 创建 Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>途正开发启动器</string>
    <key>CFBundleDisplayName</key>
    <string>途正开发启动器</string>
    <key>CFBundleIdentifier</key>
    <string>com.tuzheng.devlauncher</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>TZDevLauncher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 火鹰科技. All rights reserved.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST_EOF

echo -e "${CYAN}  [4/4] 生成应用图标...${NC}"

# 用 Python 生成简单图标
python3 - "$RESOURCES_DIR" << 'ICON_EOF' 2>/dev/null || echo -e "${YELLOW}  图标生成跳过（不影响使用）${NC}"
import sys, os, subprocess, tempfile, struct, zlib

resources_dir = sys.argv[1]

def create_png(size):
    w = h = size
    r, g, b, a = 122, 58, 237, 255
    raw = b""
    margin = size // 8
    radius = size // 4
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            inside = margin <= x < w - margin and margin <= y < h - margin
            if inside:
                dx = min(x - margin, w - margin - 1 - x)
                dy = min(y - margin, h - margin - 1 - y)
                if dx < radius and dy < radius:
                    dist = ((radius - dx)**2 + (radius - dy)**2)**0.5
                    if dist > radius:
                        raw += struct.pack("BBBB", 0, 0, 0, 0)
                        continue
                raw += struct.pack("BBBB", r, g, b, a)
            else:
                raw += struct.pack("BBBB", 0, 0, 0, 0)
    
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw))
    png += chunk(b"IEND", b"")
    return png

iconset = tempfile.mkdtemp(suffix=".iconset")
for name, sz in [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]:
    with open(os.path.join(iconset, name), "wb") as f:
        f.write(create_png(sz))

subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(resources_dir, "AppIcon.icns")], capture_output=True)
import shutil; shutil.rmtree(iconset, ignore_errors=True)
print("  图标生成成功 ✓")
ICON_EOF

# 清理构建目录
rm -rf "$BUILD_DIR"

# 移除隔离属性
xattr -cr "$APP_DIR" 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}  ✅ 安装完成！${NC}\n"
echo -e "  📍 应用位置: ${CYAN}桌面 → 途正开发启动器${NC}"
echo -e ""
echo -e "  ${BOLD}使用方法:${NC}"
echo -e "  ${GREEN}双击桌面上的「途正开发启动器」即可打开${NC}"
echo -e ""
echo -e "  ${YELLOW}⚠️  如果 macOS 提示无法打开:${NC}"
echo -e "  ${CYAN}右键点击 → 打开 → 确认打开${NC}"
echo -e ""
