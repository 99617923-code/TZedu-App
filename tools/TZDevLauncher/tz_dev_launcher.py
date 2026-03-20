#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
途正英语 App - 开发启动器
火鹰科技出品

一个 macOS 桌面 GUI 小工具，双击即可：
- 一键启动 Android / iOS / macOS 三端
- 自动拉取最新代码
- 每30秒自动检测更新并热重载
- 实时查看各端运行状态和日志
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import subprocess
import threading
import os
import signal
import time
import json
from pathlib import Path
from datetime import datetime

# ═══════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════

# 自动检测项目路径
def find_project_dir():
    """按优先级查找项目目录"""
    candidates = [
        os.path.expanduser("~/TZedu-App"),
        os.path.expanduser("~/Desktop/TZedu-App"),
        os.path.expanduser("~/Documents/TZedu-App"),
        os.path.expanduser("~/Projects/TZedu-App"),
    ]
    for p in candidates:
        if os.path.isdir(p) and os.path.isfile(os.path.join(p, "pubspec.yaml")):
            return p
    return candidates[0]  # 默认

PROJECT_DIR = find_project_dir()
AUTO_PULL_INTERVAL = 30  # 秒

# 颜色主题
COLORS = {
    "bg": "#1A1A2E",
    "bg_card": "#16213E",
    "bg_card_hover": "#1C2A4A",
    "accent": "#7C3AED",
    "accent_light": "#A78BFA",
    "success": "#10B981",
    "warning": "#F59E0B",
    "danger": "#EF4444",
    "text": "#F9FAFB",
    "text_dim": "#9CA3AF",
    "text_muted": "#6B7280",
    "border": "#374151",
    "android": "#3DDC84",
    "ios": "#007AFF",
    "macos": "#A855F7",
}


# ═══════════════════════════════════════════════════════════════
# 主应用
# ═══════════════════════════════════════════════════════════════

class TZDevLauncher:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("途正英语 - 开发启动器")
        self.root.geometry("680x780")
        self.root.minsize(600, 700)
        self.root.configure(bg=COLORS["bg"])

        # 进程管理
        self.processes = {}  # platform -> subprocess.Popen
        self.watcher_running = False
        self.watcher_thread = None

        # 状态变量
        self.platform_status = {
            "android": tk.StringVar(value="未启动"),
            "ios": tk.StringVar(value="未启动"),
            "macos": tk.StringVar(value="未启动"),
        }
        self.watcher_status = tk.StringVar(value="未启动")
        self.git_status = tk.StringVar(value="检查中...")
        self.last_pull_time = tk.StringVar(value="--")

        # 勾选框变量
        self.check_android = tk.BooleanVar(value=True)
        self.check_ios = tk.BooleanVar(value=True)
        self.check_macos = tk.BooleanVar(value=True)

        self._build_ui()
        self._update_git_status()

        # 关闭窗口时清理
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    # ═══════════════════════════════════════════════════════════
    # UI 构建
    # ═══════════════════════════════════════════════════════════

    def _build_ui(self):
        # 主容器
        main = tk.Frame(self.root, bg=COLORS["bg"])
        main.pack(fill=tk.BOTH, expand=True, padx=20, pady=16)

        # ─── 标题栏 ───
        self._build_header(main)

        # ─── 项目路径 ───
        self._build_project_path(main)

        # ─── 平台选择 + 状态 ───
        self._build_platform_cards(main)

        # ─── 操作按钮 ───
        self._build_action_buttons(main)

        # ─── 自动拉取状态 ───
        self._build_watcher_status(main)

        # ─── 日志面板 ───
        self._build_log_panel(main)

    def _build_header(self, parent):
        header = tk.Frame(parent, bg=COLORS["bg"])
        header.pack(fill=tk.X, pady=(0, 12))

        tk.Label(
            header,
            text="途正英语",
            font=("SF Pro Display", 22, "bold"),
            fg=COLORS["accent_light"],
            bg=COLORS["bg"],
        ).pack(side=tk.LEFT)

        tk.Label(
            header,
            text="  开发启动器",
            font=("SF Pro Display", 22),
            fg=COLORS["text"],
            bg=COLORS["bg"],
        ).pack(side=tk.LEFT)

        tk.Label(
            header,
            text="火鹰科技出品",
            font=("SF Pro Text", 11),
            fg=COLORS["text_muted"],
            bg=COLORS["bg"],
        ).pack(side=tk.RIGHT, pady=(8, 0))

    def _build_project_path(self, parent):
        frame = tk.Frame(parent, bg=COLORS["bg_card"], highlightbackground=COLORS["border"], highlightthickness=1)
        frame.pack(fill=tk.X, pady=(0, 12))

        inner = tk.Frame(frame, bg=COLORS["bg_card"])
        inner.pack(fill=tk.X, padx=12, pady=8)

        tk.Label(
            inner,
            text="项目路径",
            font=("SF Pro Text", 11),
            fg=COLORS["text_muted"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.LEFT)

        tk.Label(
            inner,
            text=PROJECT_DIR,
            font=("SF Mono", 11),
            fg=COLORS["text"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.LEFT, padx=(8, 0))

        # Git 状态
        tk.Label(
            inner,
            textvariable=self.git_status,
            font=("SF Pro Text", 10),
            fg=COLORS["success"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.RIGHT)

    def _build_platform_cards(self, parent):
        frame = tk.Frame(parent, bg=COLORS["bg"])
        frame.pack(fill=tk.X, pady=(0, 12))

        # 三列布局
        frame.columnconfigure(0, weight=1)
        frame.columnconfigure(1, weight=1)
        frame.columnconfigure(2, weight=1)

        platforms = [
            ("android", "Android", COLORS["android"], self.check_android),
            ("ios", "iOS", COLORS["ios"], self.check_ios),
            ("macos", "macOS", COLORS["macos"], self.check_macos),
        ]

        for col, (key, name, color, var) in enumerate(platforms):
            card = tk.Frame(frame, bg=COLORS["bg_card"], highlightbackground=COLORS["border"], highlightthickness=1)
            card.grid(row=0, column=col, sticky="nsew", padx=(0 if col == 0 else 4, 0 if col == 2 else 4), pady=0)

            inner = tk.Frame(card, bg=COLORS["bg_card"])
            inner.pack(fill=tk.BOTH, expand=True, padx=12, pady=10)

            # 勾选框 + 平台名
            top = tk.Frame(inner, bg=COLORS["bg_card"])
            top.pack(fill=tk.X)

            cb = tk.Checkbutton(
                top,
                variable=var,
                bg=COLORS["bg_card"],
                fg=COLORS["text"],
                selectcolor=COLORS["bg"],
                activebackground=COLORS["bg_card"],
                activeforeground=COLORS["text"],
            )
            cb.pack(side=tk.LEFT)

            tk.Label(
                top,
                text=name,
                font=("SF Pro Display", 14, "bold"),
                fg=color,
                bg=COLORS["bg_card"],
            ).pack(side=tk.LEFT, padx=(2, 0))

            # 状态指示
            status_frame = tk.Frame(inner, bg=COLORS["bg_card"])
            status_frame.pack(fill=tk.X, pady=(6, 0))

            self._status_dot(status_frame, key)

            tk.Label(
                status_frame,
                textvariable=self.platform_status[key],
                font=("SF Pro Text", 11),
                fg=COLORS["text_dim"],
                bg=COLORS["bg_card"],
            ).pack(side=tk.LEFT, padx=(6, 0))

    def _status_dot(self, parent, platform):
        """创建状态指示灯"""
        canvas = tk.Canvas(parent, width=10, height=10, bg=COLORS["bg_card"], highlightthickness=0)
        canvas.pack(side=tk.LEFT)

        def update_dot(*args):
            canvas.delete("all")
            status = self.platform_status[platform].get()
            if "运行中" in status:
                color = COLORS["success"]
            elif "启动中" in status or "编译中" in status:
                color = COLORS["warning"]
            elif "错误" in status or "失败" in status:
                color = COLORS["danger"]
            else:
                color = COLORS["text_muted"]
            canvas.create_oval(1, 1, 9, 9, fill=color, outline="")

        self.platform_status[platform].trace_add("write", update_dot)
        update_dot()

    def _build_action_buttons(self, parent):
        frame = tk.Frame(parent, bg=COLORS["bg"])
        frame.pack(fill=tk.X, pady=(0, 12))

        # 一键启动
        self.btn_start = tk.Button(
            frame,
            text="  一键启动  ",
            font=("SF Pro Display", 15, "bold"),
            fg="white",
            bg=COLORS["accent"],
            activebackground=COLORS["accent_light"],
            activeforeground="white",
            relief=tk.FLAT,
            padx=20,
            pady=10,
            command=self._on_start,
        )
        self.btn_start.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 4))

        # 一键停止
        self.btn_stop = tk.Button(
            frame,
            text="  全部停止  ",
            font=("SF Pro Display", 15, "bold"),
            fg="white",
            bg=COLORS["danger"],
            activebackground="#DC2626",
            activeforeground="white",
            relief=tk.FLAT,
            padx=20,
            pady=10,
            command=self._on_stop,
        )
        self.btn_stop.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(4, 0))

        # 第二行按钮
        frame2 = tk.Frame(parent, bg=COLORS["bg"])
        frame2.pack(fill=tk.X, pady=(0, 12))

        for text, cmd, color in [
            ("拉取代码", self._on_pull, COLORS["success"]),
            ("清理重建", self._on_clean, COLORS["warning"]),
            ("安装依赖", self._on_deps, COLORS["ios"]),
        ]:
            btn = tk.Button(
                frame2,
                text=text,
                font=("SF Pro Text", 12),
                fg="white",
                bg=color,
                activebackground=color,
                activeforeground="white",
                relief=tk.FLAT,
                padx=14,
                pady=6,
                command=cmd,
            )
            btn.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)

    def _build_watcher_status(self, parent):
        frame = tk.Frame(parent, bg=COLORS["bg_card"], highlightbackground=COLORS["border"], highlightthickness=1)
        frame.pack(fill=tk.X, pady=(0, 12))

        inner = tk.Frame(frame, bg=COLORS["bg_card"])
        inner.pack(fill=tk.X, padx=12, pady=8)

        tk.Label(
            inner,
            text="自动拉取",
            font=("SF Pro Text", 11, "bold"),
            fg=COLORS["text"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.LEFT)

        tk.Label(
            inner,
            textvariable=self.watcher_status,
            font=("SF Pro Text", 11),
            fg=COLORS["success"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.LEFT, padx=(8, 0))

        tk.Label(
            inner,
            text="上次拉取:",
            font=("SF Pro Text", 10),
            fg=COLORS["text_muted"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.RIGHT, padx=(0, 4))

        tk.Label(
            inner,
            textvariable=self.last_pull_time,
            font=("SF Mono", 10),
            fg=COLORS["text_dim"],
            bg=COLORS["bg_card"],
        ).pack(side=tk.RIGHT)

    def _build_log_panel(self, parent):
        # 标题
        log_header = tk.Frame(parent, bg=COLORS["bg"])
        log_header.pack(fill=tk.X)

        tk.Label(
            log_header,
            text="运行日志",
            font=("SF Pro Text", 12, "bold"),
            fg=COLORS["text"],
            bg=COLORS["bg"],
        ).pack(side=tk.LEFT)

        tk.Button(
            log_header,
            text="清空",
            font=("SF Pro Text", 10),
            fg=COLORS["text_muted"],
            bg=COLORS["bg"],
            activebackground=COLORS["bg"],
            activeforeground=COLORS["text"],
            relief=tk.FLAT,
            command=lambda: self.log_text.delete("1.0", tk.END),
        ).pack(side=tk.RIGHT)

        # 日志文本框
        self.log_text = scrolledtext.ScrolledText(
            parent,
            font=("SF Mono", 11),
            bg="#0D1117",
            fg=COLORS["text_dim"],
            insertbackground=COLORS["text"],
            selectbackground=COLORS["accent"],
            relief=tk.FLAT,
            height=12,
            wrap=tk.WORD,
            state=tk.NORMAL,
        )
        self.log_text.pack(fill=tk.BOTH, expand=True, pady=(4, 0))

        # 配置日志颜色标签
        self.log_text.tag_configure("info", foreground=COLORS["text_dim"])
        self.log_text.tag_configure("success", foreground=COLORS["success"])
        self.log_text.tag_configure("warning", foreground=COLORS["warning"])
        self.log_text.tag_configure("error", foreground=COLORS["danger"])
        self.log_text.tag_configure("accent", foreground=COLORS["accent_light"])

    # ═══════════════════════════════════════════════════════════
    # 日志
    # ═══════════════════════════════════════════════════════════

    def _log(self, message, tag="info"):
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"[{timestamp}] {message}\n", tag)
        self.log_text.see(tk.END)

    # ═══════════════════════════════════════════════════════════
    # Git 操作
    # ═══════════════════════════════════════════════════════════

    def _update_git_status(self):
        def _check():
            try:
                result = subprocess.run(
                    ["git", "log", "--oneline", "-1"],
                    cwd=PROJECT_DIR,
                    capture_output=True, text=True, timeout=10,
                )
                if result.returncode == 0:
                    short = result.stdout.strip()[:40]
                    self.git_status.set(f"  {short}")
                else:
                    self.git_status.set("  Git 状态未知")
            except Exception:
                self.git_status.set("  项目路径无效")

        threading.Thread(target=_check, daemon=True).start()

    def _run_cmd(self, cmd, cwd=None, label=""):
        """在后台线程运行命令并输出日志"""
        try:
            result = subprocess.run(
                cmd, cwd=cwd or PROJECT_DIR,
                capture_output=True, text=True, timeout=300,
            )
            if result.stdout:
                for line in result.stdout.strip().split("\n")[-5:]:
                    self._log(f"  {line}")
            if result.returncode != 0 and result.stderr:
                for line in result.stderr.strip().split("\n")[-3:]:
                    self._log(f"  {line}", "warning")
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            self._log(f"{label} 执行超时", "error")
            return False
        except Exception as e:
            self._log(f"{label} 异常: {e}", "error")
            return False

    # ═══════════════════════════════════════════════════════════
    # 按钮事件
    # ═══════════════════════════════════════════════════════════

    def _on_start(self):
        """一键启动"""
        targets = []
        if self.check_android.get():
            targets.append("android")
        if self.check_ios.get():
            targets.append("ios")
        if self.check_macos.get():
            targets.append("macos")

        if not targets:
            messagebox.showwarning("提示", "请至少勾选一个平台")
            return

        self._log(f"准备启动: {', '.join(targets)}", "accent")
        self.btn_start.configure(state=tk.DISABLED, text="启动中...")

        def _do_start():
            # 1. 拉取代码
            self._log("正在拉取最新代码...", "info")
            self._run_cmd(["git", "pull", "origin", "main", "--no-edit"], label="git pull")
            self._update_git_status()
            self._log("代码已更新", "success")

            # 2. 安装依赖
            self._log("正在安装 Flutter 依赖...", "info")
            self._run_cmd(["flutter", "pub", "get"], label="flutter pub get")
            self._log("Flutter 依赖安装完成", "success")

            if "ios" in targets:
                self._log("正在安装 iOS Pods...", "info")
                self._run_cmd(["pod", "install"], cwd=os.path.join(PROJECT_DIR, "ios"), label="iOS pod install")

            if "macos" in targets:
                self._log("正在安装 macOS Pods...", "info")
                self._run_cmd(["pod", "install"], cwd=os.path.join(PROJECT_DIR, "macos"), label="macOS pod install")

            # 3. 获取设备列表
            self._log("正在检测可用设备...", "info")
            devices_result = subprocess.run(
                ["flutter", "devices", "--machine"],
                cwd=PROJECT_DIR, capture_output=True, text=True, timeout=30,
            )

            device_map = {}
            try:
                devices = json.loads(devices_result.stdout)
                for d in devices:
                    platform = d.get("targetPlatform", "")
                    device_id = d.get("id", "")
                    name = d.get("name", "")
                    if "android" in platform.lower():
                        device_map["android"] = (device_id, name)
                    elif platform == "ios" and "mac-designed" not in device_id:
                        device_map["ios"] = (device_id, name)
                    elif "macos" in platform.lower() or device_id == "macos":
                        device_map["macos"] = (device_id, name)
            except Exception:
                # fallback
                device_map = {
                    "android": ("emulator-5554", "Android Emulator"),
                    "ios": ("", "iOS Simulator"),
                    "macos": ("macos", "macOS"),
                }

            # 4. 启动各端
            for platform in targets:
                if platform == "macos":
                    device_id = "macos"
                    device_name = "macOS"
                elif platform in device_map:
                    device_id, device_name = device_map[platform]
                else:
                    self._log(f"未检测到 {platform} 设备，跳过", "warning")
                    self.platform_status[platform].set("未检测到设备")
                    continue

                if not device_id:
                    self._log(f"未检测到 {platform} 设备 ID，跳过", "warning")
                    self.platform_status[platform].set("未检测到设备")
                    continue

                self._log(f"启动 {platform} ({device_name})...", "accent")
                self.platform_status[platform].set("启动中...")

                try:
                    proc = subprocess.Popen(
                        ["flutter", "run", "-d", device_id],
                        cwd=PROJECT_DIR,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        stdin=subprocess.PIPE,
                        text=True,
                    )
                    self.processes[platform] = proc
                    self._log(f"{platform} 进程已启动 (PID: {proc.pid})", "success")

                    # 启动日志读取线程
                    threading.Thread(
                        target=self._read_process_output,
                        args=(platform, proc),
                        daemon=True,
                    ).start()
                except Exception as e:
                    self._log(f"启动 {platform} 失败: {e}", "error")
                    self.platform_status[platform].set("启动失败")

                # 间隔启动，避免资源竞争
                time.sleep(3)

            # 5. 启动自动拉取
            self._start_watcher()

            self.root.after(0, lambda: self.btn_start.configure(state=tk.NORMAL, text="  一键启动  "))
            self._log("所有端启动完成！", "success")

        threading.Thread(target=_do_start, daemon=True).start()

    def _on_stop(self):
        """一键停止"""
        self._log("正在停止所有端...", "warning")
        self._stop_watcher()

        for platform, proc in list(self.processes.items()):
            try:
                if proc.poll() is None:
                    # 先发送 'q' 退出
                    try:
                        proc.stdin.write("q\n")
                        proc.stdin.flush()
                    except Exception:
                        pass
                    time.sleep(1)
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=5)
                    self._log(f"{platform} 已停止", "info")
                self.platform_status[platform].set("已停止")
            except Exception as e:
                try:
                    proc.kill()
                except Exception:
                    pass
                self._log(f"强制停止 {platform}: {e}", "warning")
                self.platform_status[platform].set("已停止")

        self.processes.clear()
        self._log("所有端已停止", "success")

    def _on_pull(self):
        """手动拉取代码"""
        self._log("正在拉取最新代码...", "info")

        def _do_pull():
            self._run_cmd(["git", "pull", "origin", "main", "--no-edit"], label="git pull")
            self._update_git_status()
            self.last_pull_time.set(datetime.now().strftime("%H:%M:%S"))
            self._log("代码拉取完成", "success")

            # 触发 hot reload
            self._hot_reload_all()

        threading.Thread(target=_do_pull, daemon=True).start()

    def _on_clean(self):
        """清理重建"""
        if not messagebox.askyesno("确认", "确定要执行 flutter clean 并重新安装所有依赖吗？\n这会停止所有运行中的端。"):
            return

        self._on_stop()
        self._log("开始清理重建...", "accent")

        def _do_clean():
            self._log("执行 flutter clean...", "info")
            self._run_cmd(["flutter", "clean"], label="flutter clean")

            self._log("执行 flutter pub get...", "info")
            self._run_cmd(["flutter", "pub", "get"], label="flutter pub get")

            self._log("执行 iOS pod install...", "info")
            self._run_cmd(["pod", "install"], cwd=os.path.join(PROJECT_DIR, "ios"), label="iOS pod install")

            self._log("执行 macOS pod install...", "info")
            self._run_cmd(["pod", "install"], cwd=os.path.join(PROJECT_DIR, "macos"), label="macOS pod install")

            self._log("清理重建完成！可以点击「一键启动」了", "success")

        threading.Thread(target=_do_clean, daemon=True).start()

    def _on_deps(self):
        """安装依赖"""
        self._log("正在安装依赖...", "info")

        def _do_deps():
            self._run_cmd(["flutter", "pub", "get"], label="flutter pub get")
            self._log("Flutter 依赖安装完成", "success")

        threading.Thread(target=_do_deps, daemon=True).start()

    # ═══════════════════════════════════════════════════════════
    # 进程输出读取
    # ═══════════════════════════════════════════════════════════

    def _read_process_output(self, platform, proc):
        """读取 flutter run 的输出并更新状态"""
        try:
            for line in iter(proc.stdout.readline, ""):
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue

                # 更新状态
                if "Launching" in line or "Running" in line:
                    self.root.after(0, lambda p=platform: self.platform_status[p].set("编译中..."))
                elif "Syncing files" in line or "Hot reload" in line:
                    self.root.after(0, lambda p=platform: self.platform_status[p].set("运行中 (已重载)"))
                elif "is taking longer than expected" in line:
                    self.root.after(0, lambda p=platform: self.platform_status[p].set("编译中 (较慢)"))
                elif "Flutter run key commands" in line or "An Observatory debugger" in line or "Debug service listening" in line:
                    self.root.after(0, lambda p=platform: self.platform_status[p].set("运行中"))
                    self.root.after(0, lambda p=platform: self._log(f"{p} 启动成功，正在运行！", "success"))
                elif "Error" in line or "FAILURE" in line or "error:" in line.lower():
                    self.root.after(0, lambda p=platform, l=line: self._log(f"[{p}] {l}", "error"))

                # 关键日志输出
                if any(kw in line for kw in ["flutter:", "Error", "Warning", "Successfully", "Syncing", "Debug service"]):
                    self.root.after(0, lambda l=line[:120], p=platform: self._log(f"[{p}] {l}"))

        except Exception:
            pass
        finally:
            self.root.after(0, lambda p=platform: self.platform_status[p].set("已停止"))

    # ═══════════════════════════════════════════════════════════
    # 自动拉取守护
    # ═══════════════════════════════════════════════════════════

    def _start_watcher(self):
        if self.watcher_running:
            return
        self.watcher_running = True
        self.watcher_status.set(f"运行中 (每{AUTO_PULL_INTERVAL}秒)")
        self.watcher_thread = threading.Thread(target=self._watcher_loop, daemon=True)
        self.watcher_thread.start()
        self._log(f"代码自动拉取已启动（每{AUTO_PULL_INTERVAL}秒检测一次）", "success")

    def _stop_watcher(self):
        self.watcher_running = False
        self.watcher_status.set("已停止")

    def _watcher_loop(self):
        while self.watcher_running:
            time.sleep(AUTO_PULL_INTERVAL)
            if not self.watcher_running:
                break

            try:
                # fetch 远程
                subprocess.run(
                    ["git", "fetch", "origin", "main", "--quiet"],
                    cwd=PROJECT_DIR, capture_output=True, timeout=15,
                )

                # 比较本地和远程
                local = subprocess.run(
                    ["git", "rev-parse", "HEAD"],
                    cwd=PROJECT_DIR, capture_output=True, text=True, timeout=5,
                ).stdout.strip()

                remote = subprocess.run(
                    ["git", "rev-parse", "origin/main"],
                    cwd=PROJECT_DIR, capture_output=True, text=True, timeout=5,
                ).stdout.strip()

                if local != remote:
                    self.root.after(0, lambda: self._log("检测到代码更新，正在拉取...", "accent"))

                    subprocess.run(
                        ["git", "pull", "origin", "main", "--no-edit"],
                        cwd=PROJECT_DIR, capture_output=True, timeout=30,
                    )

                    now = datetime.now().strftime("%H:%M:%S")
                    self.root.after(0, lambda t=now: self.last_pull_time.set(t))
                    self.root.after(0, lambda: self._update_git_status())
                    self.root.after(0, lambda: self._log("代码已自动更新", "success"))

                    # 触发 hot reload
                    self.root.after(0, self._hot_reload_all)

            except Exception as e:
                self.root.after(0, lambda e=e: self._log(f"自动拉取异常: {e}", "warning"))

    def _hot_reload_all(self):
        """向所有运行中的 flutter 进程发送 hot reload"""
        for platform, proc in self.processes.items():
            if proc.poll() is None:
                try:
                    proc.stdin.write("r")
                    proc.stdin.flush()
                    self._log(f"已向 {platform} 发送 Hot Reload", "success")
                except Exception:
                    pass

    # ═══════════════════════════════════════════════════════════
    # 关闭
    # ═══════════════════════════════════════════════════════════

    def _on_close(self):
        if self.processes:
            if messagebox.askyesno("确认退出", "还有运行中的开发端，确定退出吗？\n退出后所有端将被停止。"):
                self._on_stop()
                self.root.destroy()
        else:
            self.root.destroy()

    def run(self):
        self.root.mainloop()


# ═══════════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    app = TZDevLauncher()
    app.run()
