import SwiftUI

// MARK: - App Entry
@main
struct TZDevLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = LauncherViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 680, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 600)
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - ViewModel
class LauncherViewModel: ObservableObject {
    @Published var androidEnabled = true
    @Published var iosEnabled = true
    @Published var macosEnabled = true
    @Published var autoSyncEnabled = true
    @Published var syncInterval: Double = 30
    
    @Published var isRunning = false
    @Published var androidStatus: DeviceStatus = .stopped
    @Published var iosStatus: DeviceStatus = .stopped
    @Published var macosStatus: DeviceStatus = .stopped
    @Published var syncStatus: String = "未启动"
    
    @Published var logs: [LogEntry] = []
    
    private var processes: [String: Process] = [:]
    private var syncTimer: Timer?
    private var projectPath: String = ""
    
    enum DeviceStatus: String {
        case stopped = "未启动"
        case starting = "启动中..."
        case running = "运行中"
        case error = "出错"
        
        var color: Color {
            switch self {
            case .stopped: return .gray
            case .starting: return .orange
            case .running: return .green
            case .error: return .red
            }
        }
    }
    
    init() {
        detectProjectPath()
    }
    
    private func detectProjectPath() {
        let candidates = [
            NSHomeDirectory() + "/TZedu-App",
            NSHomeDirectory() + "/Desktop/TZedu-App",
            NSHomeDirectory() + "/Documents/TZedu-App",
            NSHomeDirectory() + "/Projects/TZedu-App",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path + "/pubspec.yaml") {
                projectPath = path
                addLog("检测到项目路径: \(path)", type: .info)
                return
            }
        }
        projectPath = NSHomeDirectory() + "/TZedu-App"
        addLog("使用默认项目路径: \(projectPath)", type: .warning)
    }
    
    func addLog(_ message: String, type: LogEntry.LogType = .info) {
        DispatchQueue.main.async {
            let entry = LogEntry(message: message, type: type)
            self.logs.append(entry)
            // 保留最近 500 条
            if self.logs.count > 500 {
                self.logs.removeFirst(self.logs.count - 500)
            }
        }
    }
    
    // MARK: - 一键启动
    func startAll() {
        guard !isRunning else { return }
        isRunning = true
        addLog("═══ 开始启动开发环境 ═══", type: .header)
        
        // 先拉取代码
        pullCode {
            // 安装依赖
            self.installDeps {
                // 启动各端
                if self.androidEnabled { self.startDevice("android") }
                if self.iosEnabled { self.startDevice("ios") }
                if self.macosEnabled { self.startDevice("macos") }
                
                // 启动自动同步
                if self.autoSyncEnabled {
                    self.startAutoSync()
                }
            }
        }
    }
    
    // MARK: - 全部停止
    func stopAll() {
        addLog("═══ 正在停止所有服务 ═══", type: .header)
        
        stopAutoSync()
        
        for (name, process) in processes {
            if process.isRunning {
                process.terminate()
                addLog("已停止: \(name)", type: .info)
            }
        }
        processes.removeAll()
        
        DispatchQueue.main.async {
            self.androidStatus = .stopped
            self.iosStatus = .stopped
            self.macosStatus = .stopped
            self.isRunning = false
        }
        
        addLog("✅ 所有服务已停止", type: .success)
    }
    
    // MARK: - 拉取代码
    func pullCode(completion: (() -> Void)? = nil) {
        addLog("正在拉取最新代码...", type: .info)
        
        runShell("cd \(projectPath) && git pull origin main 2>&1") { output, success in
            if success {
                if output.contains("Already up to date") {
                    self.addLog("代码已是最新", type: .info)
                } else {
                    self.addLog("代码已更新", type: .success)
                    // 如果有运行中的进程，发送 hot reload
                    self.hotReloadAll()
                }
            } else {
                self.addLog("拉取失败: \(output)", type: .error)
            }
            completion?()
        }
    }
    
    // MARK: - 安装依赖
    func installDeps(completion: (() -> Void)? = nil) {
        addLog("正在安装 Flutter 依赖...", type: .info)
        
        runShell("cd \(projectPath) && flutter pub get 2>&1") { output, success in
            if success {
                self.addLog("Flutter 依赖安装完成", type: .success)
            } else {
                self.addLog("依赖安装失败: \(output.prefix(200))", type: .error)
            }
            completion?()
        }
    }
    
    // MARK: - 启动设备
    private func startDevice(_ platform: String) {
        let statusKey = platform
        
        DispatchQueue.main.async {
            switch platform {
            case "android": self.androidStatus = .starting
            case "ios": self.iosStatus = .starting
            case "macos": self.macosStatus = .starting
            default: break
            }
        }
        
        var deviceFlag: String
        switch platform {
        case "android":
            deviceFlag = "-d android"
            addLog("正在启动 Android 模拟器...", type: .info)
        case "ios":
            deviceFlag = "-d iPhone"
            addLog("正在启动 iOS 模拟器...", type: .info)
        case "macos":
            deviceFlag = "-d macos"
            addLog("正在启动 macOS 桌面...", type: .info)
        default:
            return
        }
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", "cd \(projectPath) && flutter run \(deviceFlag) 2>&1"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment
        
        processes[statusKey] = process
        
        // 读取输出
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            // 检测启动成功
            if trimmed.contains("Flutter run key commands") || trimmed.contains("is taking longer than expected") {
                DispatchQueue.main.async {
                    switch platform {
                    case "android": self.androidStatus = .running
                    case "ios": self.iosStatus = .running
                    case "macos": self.macosStatus = .running
                    default: break
                    }
                }
                self.addLog("[\(platform.uppercased())] ✅ 启动成功", type: .success)
            }
            
            // 过滤掉过长的编译日志
            if trimmed.count < 200 && !trimmed.hasPrefix("In file included") && !trimmed.hasPrefix("/Users") {
                self.addLog("[\(platform.uppercased())] \(trimmed)", type: .device)
            }
        }
        
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                switch platform {
                case "android": self.androidStatus = proc.terminationStatus == 0 ? .stopped : .error
                case "ios": self.iosStatus = proc.terminationStatus == 0 ? .stopped : .error
                case "macos": self.macosStatus = proc.terminationStatus == 0 ? .stopped : .error
                default: break
                }
            }
            self.addLog("[\(platform.uppercased())] 进程已退出 (code: \(proc.terminationStatus))", type: .info)
        }
        
        do {
            try process.run()
        } catch {
            addLog("[\(platform.uppercased())] 启动失败: \(error.localizedDescription)", type: .error)
            DispatchQueue.main.async {
                switch platform {
                case "android": self.androidStatus = .error
                case "ios": self.iosStatus = .error
                case "macos": self.macosStatus = .error
                default: break
                }
            }
        }
    }
    
    // MARK: - Hot Reload
    func hotReloadAll() {
        for (name, process) in processes {
            guard process.isRunning else { continue }
            // 向 flutter run 的 stdin 发送 'r' 触发 hot reload
            if let stdin = process.standardInput as? Pipe {
                let data = "r".data(using: .utf8)!
                stdin.fileHandleForWriting.write(data)
                addLog("[\(name.uppercased())] 已发送 Hot Reload", type: .success)
            }
        }
    }
    
    // MARK: - 自动同步
    private func startAutoSync() {
        DispatchQueue.main.async {
            self.syncStatus = "运行中 (每\(Int(self.syncInterval))秒)"
        }
        addLog("自动同步已启动 (每\(Int(syncInterval))秒检测)", type: .info)
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }
    
    private func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        DispatchQueue.main.async {
            self.syncStatus = "未启动"
        }
    }
    
    private func checkForUpdates() {
        runShell("cd \(projectPath) && git fetch origin main 2>&1 && git log HEAD..origin/main --oneline 2>&1") { output, success in
            if success && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                if lines.count > 0 && !output.contains("Already up to date") {
                    self.addLog("检测到 \(lines.count) 个新提交，正在拉取...", type: .info)
                    self.pullCode()
                }
            }
        }
    }
    
    // MARK: - 清理重建
    func cleanAndRebuild() {
        addLog("═══ 开始清理重建 ═══", type: .header)
        
        // 先停止所有
        stopAll()
        
        runShell("cd \(projectPath) && flutter clean 2>&1") { output, success in
            self.addLog("Flutter clean 完成", type: success ? .success : .error)
            
            self.runShell("cd \(projectPath) && flutter pub get 2>&1") { output, success in
                self.addLog("Flutter pub get 完成", type: success ? .success : .error)
                
                // iOS pod install
                self.runShell("cd \(projectPath)/ios && pod install 2>&1") { _, _ in
                    self.addLog("iOS pod install 完成", type: .success)
                }
                
                // macOS pod install
                self.runShell("cd \(projectPath)/macos && pod install 2>&1") { _, _ in
                    self.addLog("macOS pod install 完成", type: .success)
                    self.addLog("✅ 清理重建完成，可以重新启动", type: .success)
                }
            }
        }
    }
    
    // MARK: - Shell Helper
    private func runShell(_ command: String, completion: @escaping (String, Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-l", "-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessInfo.processInfo.environment
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    completion(output, process.terminationStatus == 0)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error.localizedDescription, false)
                }
            }
        }
    }
}

// MARK: - Log Entry
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
    
    enum LogType {
        case info, success, warning, error, header, device
        
        var color: Color {
            switch self {
            case .info: return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .header: return .purple
            case .device: return Color(.systemTeal)
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .header: return "line.3.horizontal"
            case .device: return "desktopcomputer"
            }
        }
    }
    
    var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var vm: LauncherViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            headerBar
            
            Divider()
            
            HStack(spacing: 0) {
                // 左侧控制面板
                controlPanel
                    .frame(width: 260)
                
                Divider()
                
                // 右侧日志面板
                logPanel
            }
        }
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Header
    var headerBar: some View {
        HStack {
            Image(systemName: "graduationcap.fill")
                .font(.title2)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("途正英语 · 开发启动器")
                    .font(.headline)
                Text("火鹰科技出品")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 状态指示灯
            HStack(spacing: 12) {
                statusDot("Android", vm.androidStatus)
                statusDot("iOS", vm.iosStatus)
                statusDot("macOS", vm.macosStatus)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
    
    func statusDot(_ name: String, _ status: LauncherViewModel.DeviceStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Control Panel
    var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 平台选择
                GroupBox(label: Label("启动平台", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $vm.androidEnabled) {
                            Label("Android 模拟器", systemImage: "phone")
                        }
                        Toggle(isOn: $vm.iosEnabled) {
                            Label("iOS 模拟器", systemImage: "iphone")
                        }
                        Toggle(isOn: $vm.macosEnabled) {
                            Label("macOS 桌面", systemImage: "desktopcomputer")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 自动同步设置
                GroupBox(label: Label("自动同步", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $vm.autoSyncEnabled) {
                            Text("启用自动拉取")
                        }
                        
                        if vm.autoSyncEnabled {
                            HStack {
                                Text("间隔")
                                    .font(.caption)
                                Slider(value: $vm.syncInterval, in: 10...120, step: 10)
                                Text("\(Int(vm.syncInterval))秒")
                                    .font(.caption)
                                    .frame(width: 36)
                            }
                        }
                        
                        HStack {
                            Circle()
                                .fill(vm.syncStatus == "未启动" ? Color.gray : Color.green)
                                .frame(width: 6, height: 6)
                            Text(vm.syncStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 操作按钮
                GroupBox(label: Label("操作", systemImage: "play.circle")) {
                    VStack(spacing: 8) {
                        // 一键启动 / 全部停止
                        if vm.isRunning {
                            Button(action: { vm.stopAll() }) {
                                Label("全部停止", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                        } else {
                            Button(action: { vm.startAll() }) {
                                Label("一键启动", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.large)
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: { vm.pullCode() }) {
                                Label("拉取代码", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            Button(action: { vm.installDeps() }) {
                                Label("安装依赖", systemImage: "shippingbox")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                        
                        Button(action: { vm.cleanAndRebuild() }) {
                            Label("清理重建", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer()
            }
            .padding(12)
        }
    }
    
    // MARK: - Log Panel
    var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日志标题
            HStack {
                Label("运行日志", systemImage: "text.alignleft")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { vm.logs.removeAll() }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // 日志列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timeString)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                
                                Image(systemName: entry.type.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(entry.type.color)
                                    .frame(width: 14)
                                
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.type.color)
                                    .lineLimit(3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: vm.logs.count) { _ in
                    if let last = vm.logs.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(.textBackgroundColor).opacity(0.5))
        }
    }
}
