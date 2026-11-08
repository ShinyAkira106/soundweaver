// SettingsWindow.swift
// Two pane settings window: a hero panel on the left, a grid of topics on the right,
// each opening a detail page with the fine grained options.

import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case devices, volume, ddc, sync, hud, keys, startup, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "输出设备"
        case .volume: return "音量调节"
        case .ddc: return "显示器 DDC"
        case .sync: return "同步与校正"
        case .hud: return "提示框"
        case .keys: return "键盘"
        case .startup: return "启动与退出"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .devices: return "选择设备并自定义显示名称"
        case .volume: return "步进、音量曲线与上限"
        case .ddc: return "连接状态、读取与检测"
        case .sync: return "时间差与时钟漂移"
        case .hud: return "样式、位置与停留时间"
        case .keys: return "音量键与修饰键行为"
        case .startup: return "开机启动与退出恢复"
        case .about: return "版本、作者与开源信息"
        }
    }

    var icon: String {
        switch self {
        case .devices: return "hifispeaker.2"
        case .volume: return "slider.horizontal.3"
        case .ddc: return "display"
        case .sync: return "waveform.path"
        case .hud: return "rectangle.inset.topright.filled"
        case .keys: return "keyboard"
        case .startup: return "power"
        case .about: return "info.circle"
        }
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let router = SettingsRouter()

    func show(controller: Controller, page: SettingsPage? = nil) {
        router.page = page
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRoot(router: router).environmentObject(controller))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Soundweaver"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(NSSize(width: 920, height: 580))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsRouter: ObservableObject {
    @Published var page: SettingsPage?
}

// MARK: Root

struct SettingsRoot: View {
    @ObservedObject var router: SettingsRouter
    @EnvironmentObject var c: Controller

    var body: some View {
        HStack(spacing: 0) {
            HeroPane()
                .frame(width: 360)
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 1)
            ZStack {
                if let page = router.page {
                    DetailPage(page: page) { withAnimation(.easeInOut(duration: 0.2)) { router.page = nil } }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    TopicGrid { page in withAnimation(.easeInOut(duration: 0.2)) { router.page = page } }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 580, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

// MARK: Hero

struct HeroPane: View {
    @EnvironmentObject var c: Controller
    @StateObject private var flags = ViewFlags()   // a: scanned

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.primary.opacity(0.035), Color.primary.opacity(0.01)],
                           startPoint: .top, endPoint: .bottom)
            WovenBackdrop()
                .frame(width: 300, height: 300)
                .offset(y: -105)

            VStack(spacing: 0) {
                Spacer().frame(height: 82)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 168, height: 168)
                    .shadow(color: Brand.violet.opacity(0.25), radius: 20, x: 0, y: 10)
                Spacer().frame(height: 70)
                Text("Soundweaver")
                    .font(.system(size: 34, weight: .medium))
                Text("把显示器和 MacBook 的声音织在一起")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer()
                GlassCallToAction(title: "重新检测设备") {
                    c.rescan()
                    flags.a = true
                }
                Text(flags.a ? "已检测：\(c.monitorDevice == nil ? "未找到显示器" : c.monitorTitle)" : " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Spacer().frame(height: 28)
                CopyrightLine()
                Spacer().frame(height: 14)
            }
            .padding(.horizontal, 24)
        }
    }
}

/// Faint concentric waves behind the icon, echoing the woven threads.
struct WovenBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<4 {
                let r = 70 + CGFloat(i) * 34
                var path = Path()
                path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.stroke(path, with: .color(Brand.violet.opacity(0.10 - Double(i) * 0.02)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Grid

struct TopicGrid: View {
    let open: (SettingsPage) -> Void

    let columns = [GridItem(.flexible(), spacing: 36, alignment: .topLeading),
                           GridItem(.flexible(), spacing: 36, alignment: .topLeading)]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 34) {
                ForEach(SettingsPage.allCases) { page in
                    TopicTile(page: page) { open(page) }
                }
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            HStack {
                Spacer()
                Link(destination: URL(string: "https://github.com/ShinyAkira106")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("在 GitHub 上反馈建议").underline()
                    }
                    .font(.system(size: 13))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }
}

struct TopicTile: View {
    let page: SettingsPage
    let action: () -> Void
    @StateObject var hover = ViewFlags()   // a: hovering

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: page.icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(hover.a ? AnyShapeStyle(Brand.violet) : AnyShapeStyle(.secondary))
                    .frame(width: 44, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(page.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                    Text(page.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hover.a ? 0.04 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.a = $0 }
    }
}

// MARK: Detail pages

struct DetailPage: View {
    let page: SettingsPage
    let back: () -> Void
    @EnvironmentObject var c: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: back) {
                Label("返回", systemImage: "chevron.left")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Image(systemName: page.icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(.system(size: 22, weight: .regular))
                    Text(page.subtitle.replacingOccurrences(of: "\n", with: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                SettingsGroup { content }
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .devices: DevicesPage()
        case .volume: VolumePage()
        case .ddc: DDCPage()
        case .sync: SyncPage()
        case .hud: HUDPage()
        case .keys: KeysPage()
        case .startup: StartupPage()
        case .about: AboutPage()
        }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if divider { Divider().padding(.leading, 16) }
        }
    }
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

struct DevicesPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "显示器音频设备", detail: "声音经 USB-C、DP 或 HDMI 送到显示器，再由耳机口输出到音箱") {
            Picker("", selection: $c.preferredMonitorUID) {
                Text("自动（\(c.monitorDevice?.name ?? "未找到")）").tag("")
                ForEach(c.availableOutputs) { Text($0.name).tag($0.uid) }
            }
            .labelsHidden()
            .frame(width: 240)
        }
        SettingRow(title: "MacBook 音频设备", detail: "组合输出时与显示器一起播放的设备") {
            Picker("", selection: $c.preferredMacUID) {
                Text("自动（\(c.macDevice?.name ?? "未找到")）").tag("")
                ForEach(c.availableOutputs) { Text($0.name).tag($0.uid) }
            }
            .labelsHidden()
            .frame(width: 240)
        }
        SettingRow(title: "显示器名称", detail: "在菜单栏面板和提示框中显示，留空则使用设备名") {
            TextField("", text: $c.monitorCustomName, prompt: Text(c.monitorDevice?.name ?? "显示器"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        }
        SettingRow(title: "MacBook 名称", detail: "留空则使用设备名") {
            TextField("", text: $c.macCustomName, prompt: Text(c.macDevice?.name ?? "MacBook 扬声器"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        }
        SettingRow(title: "输出模式", detail: "仅显示器模式下 MacBook 扬声器保持静默", divider: false) {
            Picker("", selection: $c.mode) {
                Text("显示器 + MacBook").tag(RouteMode.combined)
                Text("仅显示器").tag(RouteMode.monitorOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
    }
}

struct VolumePage: View {
    @EnvironmentObject var c: Controller

    var engineDetail: String {
        if !VolumeEngine.softwareAvailable { return "软件混音需要 macOS 14.2 或更新版本" }
        return c.engineMode == .software
            ? "Soundweaver 直接调整送往显示器的声音，不依赖 DDC。总音量就是 MacBook 的系统音量，音量键和系统提示框都由 macOS 原生处理"
            : "通过 DDC 调整显示器的硬件音量。只有接在显示器上的音箱会跟随显示器音量时才有效"
    }

    var body: some View {
        SettingRow(title: "音量控制方式", detail: engineDetail) {
            Picker("", selection: $c.engineMode) {
                Text("软件混音（推荐）").tag(VolumeEngine.software)
                Text("显示器硬件音量（DDC）").tag(VolumeEngine.ddc)
            }
            .labelsHidden()
            .frame(width: 200)
            .disabled(!VolumeEngine.softwareAvailable)
        }
        if c.usesSoftware {
            SettingRow(title: "系统录音权限",
                       detail: c.captureGranted
                           ? "已授权"
                           : "软件混音需要在“隐私与安全性 > 屏幕与系统录音”中允许 Soundweaver 录制系统音频") {
                Button("打开设置") { c.openAudioCaptureSettings() }
            }
            SettingRow(title: "混音状态", detail: c.routeStatus) {
                Image(systemName: c.engineRunning ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(c.engineRunning ? .green : .orange)
            }
        }
        SettingRow(title: "每次按键的步进", detail: "按住 Option 和 Shift 时步进再细分为四分之一") {
            Picker("", selection: $c.stepCount) {
                Text("16 格（系统默认）").tag(16)
                Text("32 格").tag(32)
                Text("64 格").tag(64)
            }
            .labelsHidden()
            .frame(width: 200)
        }
        SettingRow(title: "音量曲线", detail: "数值越大，低音量区间越细腻；1.0 为线性") {
            HStack {
                Slider(value: $c.curve, in: 1...2.5, step: 0.1).frame(width: 150)
                Text(String(format: "%.1f", c.curve)).monospacedDigit().frame(width: 30)
            }
        }
        SettingRow(title: "显示器音量上限", detail: "限制写入显示器的最大硬件音量，防止音箱突然过响") {
            HStack {
                Slider(value: $c.monitorCap, in: 0.1...1, step: 0.05).frame(width: 150)
                Text(percent(c.monitorCap)).monospacedDigit().frame(width: 40)
            }
        }
        SettingRow(title: "显示器比例") {
            HStack {
                Slider(value: $c.monitorLevel, in: 0...1).frame(width: 150)
                Text(percent(c.monitorLevel)).monospacedDigit().frame(width: 40)
            }
        }
        SettingRow(title: "MacBook 比例", divider: false) {
            HStack {
                Slider(value: $c.macLevel, in: 0...1).frame(width: 150)
                Text(percent(c.macLevel)).monospacedDigit().frame(width: 40)
            }
        }
    }
}

struct DDCPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "连接状态", detail: c.ddcStatus) {
            Image(systemName: c.ddcConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(c.ddcConnected ? .green : .orange)
        }
        SettingRow(title: "测试 DDC 音量", detail: "显示器音量降到 10% 两秒再恢复，用来确认音箱是否跟随") {
            Button("测试") { c.testDDC() }.disabled(!c.ddcConnected)
        }
        SettingRow(title: "把显示器音量调到上限", detail: "使用软件混音时建议执行一次，让 Soundweaver 有完整的调节范围") {
            Button("调到上限") { c.setMonitorHardwareToCap() }.disabled(!c.ddcConnected)
        }
        SettingRow(title: "读取显示器当前音量") {
            Button("读取") { c.readMonitorVolume() }.disabled(!c.ddcConnected)
        }
        SettingRow(title: "重新检测", detail: "插拔显示器或切换接口之后使用") {
            Button("检测") { c.rescan() }
        }
        SettingRow(title: "启动时同步显示器音量", detail: "以显示器当前的硬件音量反推总音量，避免启动时音量跳变",
                   divider: false) {
            Toggle("", isOn: $c.syncFromMonitorOnLaunch).toggleStyle(.switch).labelsHidden()
        }
    }
}

struct SyncPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "同步补偿", detail: "正值让 MacBook 晚一点出声，负值让显示器晚一点出声；松开后生效") {
            HStack {
                Slider(value: $c.syncOffsetMs, in: -200...200, step: 5) { editing in
                    if !editing { c.reapplyRouting() }
                }
                .frame(width: 150)
                Text("\(Int(c.syncOffsetMs)) ms").monospacedDigit().frame(width: 56)
            }
        }
        SettingRow(title: "时钟源", detail: "另一台设备会跟随它的时钟") {
            Picker("", selection: $c.clockIsMac) {
                Text("MacBook").tag(true)
                Text("显示器").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
        SettingRow(title: "漂移校正", detail: "长时间播放时自动修正两台设备的时钟偏差，建议保持开启", divider: false) {
            Toggle("", isOn: $c.driftCorrection).toggleStyle(.switch).labelsHidden()
        }
    }
}

struct HUDPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "使用系统提示框", detail: "由 macOS 自己绘制音量提示（在 macOS 26 及以后为经典样式）；关闭则使用 Soundweaver 的玻璃提示框，可显示自定义名称") {
            Toggle("", isOn: $c.useNativeHUD).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "自绘提示框位置") {
            Picker("", selection: $c.hudPosition) {
                ForEach(HUDPosition.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .disabled(c.useNativeHUD)
        }
        SettingRow(title: "显示在") {
            Picker("", selection: $c.hudScreen) {
                ForEach(HUDScreen.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 180)
        }
        SettingRow(title: "停留时间") {
            HStack {
                Slider(value: $c.hudDuration, in: 0.6...3, step: 0.1).frame(width: 150)
                Text(String(format: "%.1f s", c.hudDuration)).monospacedDigit().frame(width: 44)
            }
        }
        SettingRow(title: "预览", divider: false) {
            Button("显示一次") { c.showHUD() }
        }
    }
}

struct KeysPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "接管键盘音量键", detail: "只在系统输出为 Soundweaver 或显示器时接管，其他设备交还系统") {
            Toggle("", isOn: $c.interceptKeys).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "按住时连续调节") {
            Toggle("", isOn: $c.allowRepeat).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "Option + 音量键打开声音设置", detail: "与 macOS 默认行为一致") {
            Toggle("", isOn: $c.optionOpensSound).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "辅助功能权限", detail: c.accessibilityGranted ? "已授权" : "未授权，音量键无法接管",
                   divider: false) {
            Button("打开设置") { c.openAccessibilitySettings() }
        }
    }
}

struct StartupPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "登录时自动启动", detail: c.loginItemStatus.isEmpty ? nil : c.loginItemStatus) {
            Toggle("", isOn: $c.launchAtLogin).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "启用 Soundweaver", detail: "关闭后不再创建组合输出，音量键交还系统") {
            Toggle("", isOn: $c.enabled).toggleStyle(.switch).labelsHidden()
        }
        SettingRow(title: "退出时恢复原来的输出设备", detail: "恢复到 Soundweaver 接管之前选择的设备", divider: false) {
            Toggle("", isOn: $c.restoreOnQuit).toggleStyle(.switch).labelsHidden()
        }
    }
}

struct AboutPage: View {
    @EnvironmentObject var c: Controller
    var body: some View {
        SettingRow(title: "版本") { Text("v\(c.appVersion)").foregroundStyle(.secondary) }
        UpdateRows(updater: c.updater)
        SettingRow(title: "作者") { Text("ShinyAkira").foregroundStyle(.secondary) }
        SettingRow(title: "开源许可") { Text("MIT License").foregroundStyle(.secondary) }
        SettingRow(title: "源代码") {
            Link("github.com/ShinyAkira106/Soundweaver",
                 destination: URL(string: "https://github.com/ShinyAkira106/Soundweaver")!)
        }
        SettingRow(title: "致谢", detail: "DDC 与原生提示框的实现思路参考了 MonitorControl 和 m1ddc", divider: false) {
            EmptyView()
        }
    }
}

struct UpdateRows: View {
    @ObservedObject var updater: UpdateChecker

    var statusText: String {
        switch updater.status {
        case .idle:
            if let last = updater.lastChecked {
                return "上次检查：\(last.formatted(date: .abbreviated, time: .shortened))"
            }
            return "从 GitHub Releases 获取最新版本"
        case .checking: return "正在检查…"
        case .upToDate: return "已是最新版本"
        case let .available(version, _, _): return "发现新版本 v\(version)"
        case let .failed(message): return message
        }
    }

    var body: some View {
        SettingRow(title: "检查更新", detail: statusText) {
            HStack(spacing: 8) {
                if updater.status == .checking {
                    ProgressView().controlSize(.small)
                }
                if updater.availableVersion != nil {
                    Button("前往下载") { updater.openReleasePage() }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.violet)
                }
                Button("立即检查") { updater.check() }
                    .disabled(updater.status == .checking)
            }
        }
        SettingRow(title: "自动检查更新", detail: "每天最多检查一次，有新版本时在菜单栏面板中提示") {
            Toggle("", isOn: $updater.autoCheck).toggleStyle(.switch).labelsHidden()
        }
    }
}
