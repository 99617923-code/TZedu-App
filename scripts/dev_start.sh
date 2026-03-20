#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 途正英语 App - 一键开发启动脚本
# 火鹰科技出品
#
# 功能：
#   1. 自动拉取最新代码
#   2. 自动安装依赖（flutter pub get / pod install）
#   3. 同时启动 Android 模拟器、iOS 模拟器、macOS 三个端
#   4. 后台每30秒自动检测代码更新，有更新自动触发 hot reload
#
# 用法：
#   chmod +x scripts/dev_start.sh
#   ./scripts/dev_start.sh          # 启动全部三端
#   ./scripts/dev_start.sh android  # 只启动 Android
#   ./scripts/dev_start.sh ios      # 只启动 iOS
#   ./scripts/dev_start.sh macos    # 只启动 macOS
#   ./scripts/dev_start.sh android ios  # 启动 Android + iOS
# ═══════════════════════════════════════════════════════════════

set -e

# ─── 颜色定义 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─── 项目路径 ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_DIR="$PROJECT_DIR/.dev_pids"
LOG_DIR="$PROJECT_DIR/.dev_logs"

# ─── 初始化目录 ───
mkdir -p "$PID_DIR" "$LOG_DIR"

# ─── 工具函数 ───
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n${PURPLE}━━━ $1 ━━━${NC}"; }

# ─── 检查是否已有运行中的实例 ───
check_running() {
    if [ -f "$PID_DIR/watcher.pid" ]; then
        local pid=$(cat "$PID_DIR/watcher.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "检测到已有运行中的开发环境（PID: $pid）"
            log_warn "请先执行 ./scripts/dev_stop.sh 停止，或使用 ./scripts/dev_restart.sh 重启"
            exit 1
        fi
    fi
}

# ─── 解析启动参数 ───
parse_targets() {
    if [ $# -eq 0 ]; then
        # 无参数：启动全部三端
        START_ANDROID=true
        START_IOS=true
        START_MACOS=true
    else
        START_ANDROID=false
        START_IOS=false
        START_MACOS=false
        for arg in "$@"; do
            case "$arg" in
                android|Android|ANDROID) START_ANDROID=true ;;
                ios|iOS|IOS)             START_IOS=true ;;
                macos|macOS|MACOS)       START_MACOS=true ;;
                all|ALL)
                    START_ANDROID=true
                    START_IOS=true
                    START_MACOS=true
                    ;;
                *)
                    log_error "未知参数: $arg"
                    log_info "可用参数: android, ios, macos, all"
                    exit 1
                    ;;
            esac
        done
    fi
}

# ─── 打印 Banner ───
print_banner() {
    echo -e "${PURPLE}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     途正英语 App - 开发环境启动器        ║"
    echo "  ║     火鹰科技出品                         ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  启动目标："
    $START_ANDROID && echo -e "    ${GREEN}●${NC} Android 模拟器"
    $START_IOS     && echo -e "    ${GREEN}●${NC} iOS 模拟器"
    $START_MACOS   && echo -e "    ${GREEN}●${NC} macOS 桌面端"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# 步骤 1：拉取最新代码
# ═══════════════════════════════════════════════════════════════
pull_latest_code() {
    log_step "步骤 1/5：拉取最新代码"
    cd "$PROJECT_DIR"

    # 检查是否有未提交的修改
    if ! git diff --quiet 2>/dev/null; then
        log_warn "检测到本地有未提交的修改，先暂存..."
        git stash
        log_success "本地修改已暂存（git stash）"
    fi

    git pull origin main --no-edit 2>&1 | head -20
    log_success "代码已更新到最新版本"
}

# ═══════════════════════════════════════════════════════════════
# 步骤 2：安装依赖
# ═══════════════════════════════════════════════════════════════
install_deps() {
    log_step "步骤 2/5：安装依赖"
    cd "$PROJECT_DIR"

    log_info "执行 flutter pub get..."
    flutter pub get 2>&1 | tail -5
    log_success "Flutter 依赖安装完成"

    # iOS pod install
    if $START_IOS; then
        log_info "执行 iOS pod install..."
        cd "$PROJECT_DIR/ios"
        pod install --silent 2>&1 | tail -3
        cd "$PROJECT_DIR"
        log_success "iOS Pods 安装完成"
    fi

    # macOS pod install
    if $START_MACOS; then
        log_info "执行 macOS pod install..."
        cd "$PROJECT_DIR/macos"
        pod install --silent 2>&1 | tail -3
        cd "$PROJECT_DIR"
        log_success "macOS Pods 安装完成"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 步骤 3：启动模拟器
# ═══════════════════════════════════════════════════════════════
start_emulators() {
    log_step "步骤 3/5：启动模拟器"

    # 启动 Android 模拟器
    if $START_ANDROID; then
        # 检查是否已有 Android 模拟器在运行
        if adb devices 2>/dev/null | grep -q "emulator"; then
            log_success "Android 模拟器已在运行"
        else
            log_info "启动 Android 模拟器..."
            # 获取第一个可用的 AVD
            local avd_name=$(flutter emulators 2>/dev/null | grep -oP '(?<=• )\S+' | head -1)
            if [ -n "$avd_name" ]; then
                flutter emulators --launch "$avd_name" &>/dev/null &
                log_info "等待 Android 模拟器启动（约30秒）..."
                sleep 15
                # 等待模拟器完全启动
                for i in {1..30}; do
                    if adb devices 2>/dev/null | grep -q "emulator"; then
                        break
                    fi
                    sleep 2
                done
                log_success "Android 模拟器已启动"
            else
                log_warn "未找到 Android AVD，请先在 Android Studio 中创建模拟器"
                START_ANDROID=false
            fi
        fi
    fi

    # 启动 iOS 模拟器
    if $START_IOS; then
        log_info "启动 iOS 模拟器..."
        open -a Simulator 2>/dev/null || true
        sleep 3

        # 检查是否有可用的 iOS 模拟器
        local ios_device=$(xcrun simctl list devices booted 2>/dev/null | grep -oP '\(([A-F0-9-]+)\)' | head -1 | tr -d '()')
        if [ -z "$ios_device" ]; then
            # 没有已启动的模拟器，尝试启动一个
            local sim_id=$(xcrun simctl list devices available 2>/dev/null | grep "iPhone" | grep -oP '\(([A-F0-9-]+)\)' | head -1 | tr -d '()')
            if [ -n "$sim_id" ]; then
                xcrun simctl boot "$sim_id" 2>/dev/null || true
                sleep 5
                log_success "iOS 模拟器已启动"
            else
                log_warn "未找到可用的 iOS 模拟器"
                START_IOS=false
            fi
        else
            log_success "iOS 模拟器已在运行"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# 步骤 4：启动 Flutter 应用（三端并行）
# ═══════════════════════════════════════════════════════════════
start_flutter_apps() {
    log_step "步骤 4/5：启动 Flutter 应用"
    cd "$PROJECT_DIR"

    # 获取设备列表
    local devices=$(flutter devices 2>/dev/null)

    # ─── 启动 Android ───
    if $START_ANDROID; then
        local android_id=$(echo "$devices" | grep -i "android" | grep -oP '• \K\S+' | head -1)
        if [ -n "$android_id" ]; then
            log_info "启动 Android 端 (设备: $android_id)..."
            flutter run -d "$android_id" \
                --pid-file="$PID_DIR/android.pid" \
                > "$LOG_DIR/android.log" 2>&1 &
            echo $! > "$PID_DIR/android_process.pid"
            log_success "Android 端启动中... (日志: .dev_logs/android.log)"
        else
            log_warn "未检测到 Android 设备"
            START_ANDROID=false
        fi
    fi

    # 等待一下再启动下一个，避免资源竞争
    $START_ANDROID && sleep 5

    # ─── 启动 iOS ───
    if $START_IOS; then
        local ios_id=$(echo "$devices" | grep -i "ios" | grep -v "mac-designed" | grep -oP '• \K\S+' | head -1)
        if [ -n "$ios_id" ]; then
            log_info "启动 iOS 端 (设备: $ios_id)..."
            flutter run -d "$ios_id" \
                --pid-file="$PID_DIR/ios.pid" \
                > "$LOG_DIR/ios.log" 2>&1 &
            echo $! > "$PID_DIR/ios_process.pid"
            log_success "iOS 端启动中... (日志: .dev_logs/ios.log)"
        else
            log_warn "未检测到 iOS 模拟器"
            START_IOS=false
        fi
    fi

    $START_IOS && sleep 5

    # ─── 启动 macOS ───
    if $START_MACOS; then
        log_info "启动 macOS 端..."
        flutter run -d macos \
            --pid-file="$PID_DIR/macos.pid" \
            > "$LOG_DIR/macos.log" 2>&1 &
        echo $! > "$PID_DIR/macos_process.pid"
        log_success "macOS 端启动中... (日志: .dev_logs/macos.log)"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 步骤 5：启动代码自动拉取守护进程
# ═══════════════════════════════════════════════════════════════
start_auto_pull_watcher() {
    log_step "步骤 5/5：启动代码自动拉取守护进程"

    # 写入 watcher 脚本
    cat > "$PID_DIR/watcher_run.sh" << 'WATCHER_EOF'
#!/bin/bash
PROJECT_DIR="$1"
PID_DIR="$2"
LOG_DIR="$3"
INTERVAL="${4:-30}"

cd "$PROJECT_DIR"

echo "[Watcher] 代码自动拉取守护进程已启动（间隔: ${INTERVAL}秒）" >> "$LOG_DIR/watcher.log"

while true; do
    sleep "$INTERVAL"

    # 检查远程是否有更新
    git fetch origin main --quiet 2>/dev/null

    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse origin/main 2>/dev/null)

    if [ "$LOCAL" != "$REMOTE" ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$TIMESTAMP] 检测到代码更新，正在拉取..." >> "$LOG_DIR/watcher.log"

        # 拉取最新代码
        git pull origin main --no-edit >> "$LOG_DIR/watcher.log" 2>&1

        echo "[$TIMESTAMP] 代码已更新，触发 hot reload..." >> "$LOG_DIR/watcher.log"

        # 向所有运行中的 flutter 进程发送 hot reload 信号（按 'r' 键）
        for platform in android ios macos; do
            pid_file="$PID_DIR/${platform}_process.pid"
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file")
                if kill -0 "$pid" 2>/dev/null; then
                    # 通过向 flutter run 的 stdin 发送 'r' 来触发 hot reload
                    kill -USR1 "$pid" 2>/dev/null || true
                    echo "[$TIMESTAMP] 已向 $platform (PID: $pid) 发送 reload 信号" >> "$LOG_DIR/watcher.log"
                fi
            fi
        done

        echo "[$TIMESTAMP] ✓ 自动更新完成" >> "$LOG_DIR/watcher.log"
    fi
done
WATCHER_EOF

    chmod +x "$PID_DIR/watcher_run.sh"

    # 启动 watcher 守护进程
    bash "$PID_DIR/watcher_run.sh" "$PROJECT_DIR" "$PID_DIR" "$LOG_DIR" 30 &
    echo $! > "$PID_DIR/watcher.pid"
    log_success "代码自动拉取守护进程已启动（每30秒检测一次）"
}

# ═══════════════════════════════════════════════════════════════
# 打印最终状态
# ═══════════════════════════════════════════════════════════════
print_status() {
    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✓ 开发环境启动完成！${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}运行中的端：${NC}"
    $START_ANDROID && echo -e "    ${GREEN}●${NC} Android  →  日志: ${CYAN}.dev_logs/android.log${NC}"
    $START_IOS     && echo -e "    ${GREEN}●${NC} iOS      →  日志: ${CYAN}.dev_logs/ios.log${NC}"
    $START_MACOS   && echo -e "    ${GREEN}●${NC} macOS    →  日志: ${CYAN}.dev_logs/macos.log${NC}"
    echo ""
    echo -e "  ${BOLD}自动拉取：${NC}"
    echo -e "    ${GREEN}●${NC} 每30秒检测一次代码更新"
    echo -e "    ${GREEN}●${NC} 有更新自动拉取并触发 hot reload"
    echo -e "    ${GREEN}●${NC} 拉取日志: ${CYAN}.dev_logs/watcher.log${NC}"
    echo ""
    echo -e "  ${BOLD}常用命令：${NC}"
    echo -e "    查看状态:  ${CYAN}./scripts/dev_status.sh${NC}"
    echo -e "    查看日志:  ${CYAN}./scripts/dev_logs.sh${NC}"
    echo -e "    停止所有:  ${CYAN}./scripts/dev_stop.sh${NC}"
    echo -e "    重启所有:  ${CYAN}./scripts/dev_restart.sh${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════
main() {
    parse_targets "$@"
    check_running
    print_banner
    pull_latest_code
    install_deps
    start_emulators
    start_flutter_apps
    start_auto_pull_watcher
    print_status
}

main "$@"
