#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 - 开发启动器 一键安装
# 火鹰科技出品
#
# 在 Mac 终端执行以下命令即可安装：
#   cd ~/TZedu-App/tools/TZDevLauncher && ./install.sh
#
# 安装后桌面会出现「途正开发启动器」应用，双击即可使用
# ═══════════════════════════════════════════════════════════════

set -e

PURPLE='\033[0;35m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="途正开发启动器"
APP_DIR="$HOME/Desktop/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo -e "\n${PURPLE}${BOLD}  ╔═══════════════════════════════════════╗${NC}"
echo -e "${PURPLE}${BOLD}  ║   途正英语 - 开发启动器 安装程序     ║${NC}"
echo -e "${PURPLE}${BOLD}  ║   火鹰科技出品                       ║${NC}"
echo -e "${PURPLE}${BOLD}  ╚═══════════════════════════════════════╝${NC}\n"

# 清理旧的
if [ -d "$APP_DIR" ]; then
    echo -e "${YELLOW}  检测到旧版本，正在更新...${NC}"
    rm -rf "$APP_DIR"
fi

# 创建 .app 目录结构
echo -e "${CYAN}  [1/3] 创建应用结构...${NC}"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制 Python 脚本
cp "$SCRIPT_DIR/tz_dev_launcher.py" "$RESOURCES_DIR/"

# 创建启动脚本
cat > "$MACOS_DIR/launcher" << 'LAUNCHER_EOF'
#!/bin/bash
# 途正开发启动器 - 启动入口
DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$DIR/../Resources"

# 确保 PATH 包含常用工具路径
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 确保 Flutter 在 PATH 中
if [ -d "$HOME/development/flutter/bin" ]; then
    export PATH="$HOME/development/flutter/bin:$PATH"
fi
if [ -d "$HOME/.flutter/bin" ]; then
    export PATH="$HOME/.flutter/bin:$PATH"
fi
if [ -d "/opt/flutter/bin" ]; then
    export PATH="/opt/flutter/bin:$PATH"
fi
# fvm 支持
if [ -d "$HOME/fvm/default/bin" ]; then
    export PATH="$HOME/fvm/default/bin:$PATH"
fi
if [ -d "$HOME/.pub-cache/bin" ]; then
    export PATH="$HOME/.pub-cache/bin:$PATH"
fi

# 尝试从 .zshrc / .bash_profile 加载用户环境
for rc in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
    if [ -f "$rc" ]; then
        source "$rc" 2>/dev/null || true
        break
    fi
done

# 使用系统 Python3 运行
exec /usr/bin/python3 "$RESOURCES_DIR/tz_dev_launcher.py"
LAUNCHER_EOF

chmod +x "$MACOS_DIR/launcher"

# 创建 Info.plist
echo -e "${CYAN}  [2/3] 配置应用信息...${NC}"
cat > "$CONTENTS_DIR/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.tuzheng.devlauncher</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2025 火鹰科技. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

# 生成应用图标
echo -e "${CYAN}  [3/3] 生成应用图标...${NC}"
python3 - "$RESOURCES_DIR" << 'ICON_PYTHON_EOF' 2>/dev/null || echo -e "${YELLOW}  图标生成跳过（不影响使用）${NC}"
import sys, os, subprocess, tempfile, struct, zlib

resources_dir = sys.argv[1]

# 生成一个简单的 PNG 图标（紫色背景 + 白色 TZ 文字）
def create_simple_png(size):
    """创建一个简单的紫色方块 PNG"""
    width = height = size
    
    # 紫色 RGBA
    r, g, b, a = 122, 58, 237, 255
    
    # 构建像素数据
    raw_data = b""
    for y in range(height):
        raw_data += b"\x00"  # filter byte
        for x in range(width):
            # 简单的圆角效果
            margin = size // 6
            corner_r = size // 4
            
            # 检查是否在圆角范围内
            in_rect = margin <= x < width - margin and margin <= y < height - margin
            
            if in_rect:
                # 简单的圆角检测
                dx = min(x - margin, width - margin - 1 - x)
                dy = min(y - margin, height - margin - 1 - y)
                
                if dx < corner_r and dy < corner_r:
                    dist = ((corner_r - dx) ** 2 + (corner_r - dy) ** 2) ** 0.5
                    if dist > corner_r:
                        raw_data += struct.pack("BBBB", 0, 0, 0, 0)
                        continue
                
                raw_data += struct.pack("BBBB", r, g, b, a)
            else:
                raw_data += struct.pack("BBBB", 0, 0, 0, 0)
    
    # PNG 文件构建
    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack(">I", len(data)) + chunk + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
    
    png = b"\x89PNG\r\n\x1a\n"
    png += make_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += make_chunk(b"IDAT", zlib.compress(raw_data))
    png += make_chunk(b"IEND", b"")
    
    return png

# 创建 iconset 目录
iconset_dir = tempfile.mkdtemp(suffix=".iconset")

sizes_map = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for filename, size in sizes_map.items():
    png_data = create_simple_png(size)
    with open(os.path.join(iconset_dir, filename), "wb") as f:
        f.write(png_data)

# 用 iconutil 打包成 .icns
result = subprocess.run(
    ["iconutil", "-c", "icns", iconset_dir, "-o", os.path.join(resources_dir, "AppIcon.icns")],
    capture_output=True,
)

if result.returncode == 0:
    print("  图标生成成功")
else:
    print(f"  iconutil 失败: {result.stderr.decode()}")

# 清理
import shutil
shutil.rmtree(iconset_dir, ignore_errors=True)
ICON_PYTHON_EOF

echo -e "\n${GREEN}${BOLD}  ✅ 安装完成！${NC}\n"
echo -e "  📍 应用位置: ${CYAN}桌面 → 途正开发启动器${NC}"
echo -e ""
echo -e "  ${BOLD}使用方法:${NC}"
echo -e "  ${GREEN}双击桌面上的「途正开发启动器」即可打开${NC}"
echo -e ""
echo -e "  ${YELLOW}⚠️  首次打开提示:${NC}"
echo -e "  如果 macOS 提示「无法打开」，请："
echo -e "  ${CYAN}右键点击 → 打开 → 确认打开${NC}"
echo -e "  或者在终端执行："
echo -e "  ${CYAN}xattr -cr ~/Desktop/途正开发启动器.app${NC}"
echo -e ""
