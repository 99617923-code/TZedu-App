#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 - 开发启动器 打包脚本
# 将 Python GUI 打包成 macOS .app 应用
# 火鹰科技出品
#
# 用法：在 Mac 上执行 ./build_app.sh
# 生成的 .app 会放在 ~/Desktop/
# ═══════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="途正开发启动器"
APP_DIR="$HOME/Desktop/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 正在打包 ${APP_NAME}.app ..."

# 清理旧的
rm -rf "$APP_DIR"

# 创建 .app 目录结构
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 复制 Python 脚本
cp "$SCRIPT_DIR/tz_dev_launcher.py" "$RESOURCES_DIR/"

# 创建启动脚本
cat > "$MACOS_DIR/launcher" << 'LAUNCHER_EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$DIR/../Resources"

# 使用系统 Python3 运行
exec /usr/bin/python3 "$RESOURCES_DIR/tz_dev_launcher.py"
LAUNCHER_EOF

chmod +x "$MACOS_DIR/launcher"

# 创建 Info.plist
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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 火鹰科技. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

# 创建一个简单的应用图标（使用 sips 从文字生成）
# 如果有 iconutil 可以生成更精美的图标
python3 << 'ICON_EOF' || true
import subprocess, os, tempfile

# 尝试用 Python 生成一个简单的图标
try:
    from PIL import Image, ImageDraw, ImageFont
    
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    iconset_dir = tempfile.mkdtemp(suffix=".iconset")
    
    for size in sizes:
        img = Image.new("RGBA", (size, size), (122, 58, 237, 255))
        draw = ImageDraw.Draw(img)
        
        # 画一个圆角矩形背景
        margin = size // 8
        draw.rounded_rectangle(
            [margin, margin, size - margin, size - margin],
            radius=size // 5,
            fill=(122, 58, 237, 255),
        )
        
        # 写文字
        font_size = size // 3
        try:
            font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", font_size)
        except:
            font = ImageFont.load_default()
        
        text = "途正"
        bbox = draw.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text(((size - tw) / 2, (size - th) / 2 - size // 10), text, fill="white", font=font)
        
        img.save(os.path.join(iconset_dir, f"icon_{size}x{size}.png"))
        if size <= 512:
            img2 = img.resize((size * 2, size * 2), Image.LANCZOS)
            img2.save(os.path.join(iconset_dir, f"icon_{size}x{size}@2x.png"))
    
    # 用 iconutil 打包
    resources_dir = os.path.expanduser(f"~/Desktop/{os.environ.get('APP_NAME', '途正开发启动器')}.app/Contents/Resources")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", os.path.join(resources_dir, "AppIcon.icns")])
    print("✓ 图标生成成功")
except Exception as e:
    print(f"图标生成跳过（不影响使用）: {e}")
ICON_EOF

echo ""
echo "✅ 打包完成！"
echo "📍 位置: $APP_DIR"
echo ""
echo "双击桌面上的「${APP_NAME}」即可使用！"
echo ""
echo "⚠️  首次打开可能需要："
echo "   右键 → 打开 → 确认打开（macOS 安全提示）"
echo ""
