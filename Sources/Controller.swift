// Controller.swift
// App state: routing (Multi Output or monitor only), volume math, key handling, HUD, settings.

import AppKit
import CoreAudio
import ServiceManagement
import SwiftUI

enum RouteMode: String, CaseIterable, Identifiable {
    case combined, monitorOnly
    var id: String { rawValue }
}

enum HUDScreen: String, CaseIterable, Identifiable {
    case mouse, main, external
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mouse: return "鼠标所在的屏幕"
        case .main: return "主显示器"
        case .external: return "外接显示器"
        }
    }
}

final class Controller: ObservableObject {
    static let aggregateUID = "com.shinyakira.soundweaver.multioutput"
    static let aggregateName = "Soundweaver"

    private let defaults = UserDefaults.standard

    // MARK: Main controls (persisted)

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "enabled"); enabled ? activate() : deactivate() }
    }
    @Published var mode: RouteMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode"); if enabled { activate() } }
    }
    @Published var master: Double {
        didSet { defaults.set(master, forKey: "master"); applyVolumes() }
    }
    @Published var monitorLevel: Double {
        didSet { defaults.set(monitorLevel, forKey: "monitorLevel"); applyVolumes() }
    }
    @Published var macLevel: Double {
        didSet { defaults.set(macLevel, forKey: "macLevel"); applyVolumes() }
    }
    @Published var muted = false {
        didSet { applyVolumes() }
    }
    /// Silences only the monitor (and the speakers on its jack) while the MacBook keeps playing.
    @Published var monitorMuted = false {
        didSet { applyVolumes() }
    }
    /// Positive delays the MacBook speakers, negative delays the monitor.
    @Published var syncOffsetMs: Double {
        didSet { defaults.set(syncOffsetMs, forKey: "syncOffsetMs") }
    }

    // MARK: Detailed settings (persisted)

    /// Empty string means automatic.
    @Published var preferredMonitorUID: String {
        didSet { defaults.set(preferredMonitorUID, forKey: "preferredMonitorUID"); devicesChanged(force: true) }
    }
    @Published var preferredMacUID: String {
        didSet { defaults.set(preferredMacUID, forKey: "preferredMacUID"); devicesChanged(force: true) }
    }
    /// Optional display names shown in the panel and HUD; empty means use the device name.
    @Published var monitorCustomName: String {
        didSet { defaults.set(monitorCustomName, forKey: "monitorCustomName") }
    }
    @Published var macCustomName: String {
        didSet { defaults.set(macCustomName, forKey: "macCustomName") }
    }
    @Published var clockIsMac: Bool {
        didSet { defaults.set(clockIsMac, forKey: "clockIsMac"); reapplyRouting() }
    }
    @Published var driftCorrection: Bool {
        didSet { defaults.set(driftCorrection, forKey: "driftCorrection"); reapplyRouting() }
    }
    @Published var stepCount: Int {
        didSet { defaults.set(stepCount, forKey: "stepCount") }
    }
    /// 1 is linear; higher values give finer control at low volume.
    @Published var curve: Double {
        didSet { defaults.set(curve, forKey: "curve"); applyVolumes() }
    }
    /// Upper limit for the monitor's hardware volume, 0...1.
    @Published var monitorCap: Double {
        didSet { defaults.set(monitorCap, forKey: "monitorCap"); applyVolumes() }
    }
    @Published var useNativeHUD: Bool {
        didSet { defaults.set(useNativeHUD, forKey: "useNativeHUD") }
    }
    @Published var hudPosition: HUDPosition {
        didSet { defaults.set(hudPosition.rawValue, forKey: "hudPosition") }
    }
    @Published var hudScreen: HUDScreen {
        didSet { defaults.set(hudScreen.rawValue, forKey: "hudScreen") }
    }
    @Published var hudDuration: Double {
        didSet { defaults.set(hudDuration, forKey: "hudDuration") }
    }
    @Published var interceptKeys: Bool {
        didSet { defaults.set(interceptKeys, forKey: "interceptKeys") }
    }
    @Published var optionOpensSound: Bool {
        didSet { defaults.set(optionOpensSound, forKey: "optionOpensSound") }
    }
    @Published var allowRepeat: Bool {
        didSet { defaults.set(allowRepeat, forKey: "allowRepeat") }
    }
    @Published var restoreOnQuit: Bool {
        didSet { defaults.set(restoreOnQuit, forKey: "restoreOnQuit") }
    }
    @Published var syncFromMonitorOnLaunch: Bool {
        didSet { defaults.set(syncFromMonitorOnLaunch, forKey: "syncFromMonitorOnLaunch") }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginItemStatus = ""
            } catch {
                loginItemStatus = "设置失败：\(error.localizedDescription)（请先把应用放进“应用程序”文件夹）"
            }
        }
    }

    // MARK: Status

    @Published private(set) var availableOutputs: [AudioDevice] = []
    @Published private(set) var monitorDevice: AudioDevice?
    @Published private(set) var macDevice: AudioDevice?
    @Published private(set) var ddcConnected = false
    @Published private(set) var ddcStatus = "正在检测 DDC…"
    @Published private(set) var routeStatus = ""
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var loginItemStatus = ""
    @Published private(set) var lastScan = Date()

    let updater = UpdateChecker()

    private var aggregateID: AudioObjectID?
    private var ddcMax = 100.0
    private var ddcDisplay: DDCDisplay?
    private let ddc = DDCVolumeWriter()
    private let keyTap = MediaKeyTap()
    private var trustTimer: Timer?

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var menuIcon: String {
        if muted || master == 0 { return "speaker.slash.fill" }
        if master < 0.34 { return "speaker.wave.1.fill" }
        if master < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// True when the current system output is ours, so the volume keys belong to us.
    var isRouted: Bool {
        let current = AudioSystem.defaultOutput()
        return (aggregateID != nil && current == aggregateID) || current == monitorDevice?.id
    }

    var monitorTitle: String {
        let name = monitorCustomName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (monitorDevice?.name ?? "显示器") : name
    }

    var macTitle: String {
        let name = macCustomName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (macDevice?.name ?? "MacBook 扬声器") : name
    }

    var isCombinedActive: Bool { mode == .combined && aggregateID != nil }

    // MARK: Lifecycle

    init() {
        defaults.register(defaults: [
            "enabled": true, "mode": RouteMode.combined.rawValue,
            "master": 0.4, "monitorLevel": 1.0, "macLevel": 0.6, "syncOffsetMs": 0.0,
            "preferredMonitorUID": "", "preferredMacUID": "",
            "monitorCustomName": "", "macCustomName": "",
            "clockIsMac": true, "driftCorrection": true,
            "stepCount": 16, "curve": 1.0, "monitorCap": 1.0,
            "useNativeHUD": true, "hudPosition": HUDPosition.topRight.rawValue,
            "hudScreen": HUDScreen.mouse.rawValue, "hudDuration": 1.2,
            "interceptKeys": true, "optionOpensSound": true, "allowRepeat": true,
            "restoreOnQuit": true, "syncFromMonitorOnLaunch": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        mode = RouteMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .combined
        master = defaults.double(forKey: "master")
        monitorLevel = defaults.double(forKey: "monitorLevel")
        macLevel = defaults.double(forKey: "macLevel")
        syncOffsetMs = defaults.double(forKey: "syncOffsetMs")
        preferredMonitorUID = defaults.string(forKey: "preferredMonitorUID") ?? ""
        preferredMacUID = defaults.string(forKey: "preferredMacUID") ?? ""
        monitorCustomName = defaults.string(forKey: "monitorCustomName") ?? ""
        macCustomName = defaults.string(forKey: "macCustomName") ?? ""
        clockIsMac = defaults.bool(forKey: "clockIsMac")
        driftCorrection = defaults.bool(forKey: "driftCorrection")
        stepCount = max(8, defaults.integer(forKey: "stepCount"))
        curve = defaults.double(forKey: "curve")
        monitorCap = defaults.double(forKey: "monitorCap")
        useNativeHUD = defaults.bool(forKey: "useNativeHUD")
        hudPosition = HUDPosition(rawValue: defaults.string(forKey: "hudPosition") ?? "") ?? .topRight
        hudScreen = HUDScreen(rawValue: defaults.string(forKey: "hudScreen") ?? "") ?? .mouse
        hudDuration = defaults.double(forKey: "hudDuration")
        interceptKeys = defaults.bool(forKey: "interceptKeys")
        optionOpensSound = defaults.bool(forKey: "optionOpensSound")
        allowRepeat = defaults.bool(forKey: "allowRepeat")
        restoreOnQuit = defaults.bool(forKey: "restoreOnQuit")
        syncFromMonitorOnLaunch = defaults.bool(forKey: "syncFromMonitorOnLaunch")
        launchAtLogin = SMAppService.mainApp.status == .enabled

        AudioSystem.destroyLeftover(uid: Self.aggregateUID)
        refreshDevices()
        connectDDC(isLaunch: true)
        setupKeys()

        AudioSystem.onSystemChange(kAudioHardwarePropertyDevices) { [weak self] in self?.devicesChanged(force: false) }
        AudioSystem.onSystemChange(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.updateRouteStatus() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.restoreOnQuit { self.deactivate() } else { self.destroyAggregate() }
        }

        if enabled { activate() } else { updateRouteStatus() }
    }

    // MARK: Devices and routing

    private func refreshDevices() {
        let devices = AudioSystem.outputDevices()
        availableOutputs = devices

        let displays = devices.filter(\.isDisplay)
        monitorDevice = devices.first { $0.uid == preferredMonitorUID }
            ?? displays.first { $0.name.localizedCaseInsensitiveContains("L27h") }
            ?? displays.first

        let builtIns = devices.filter(\.isBuiltIn)
        macDevice = devices.first { $0.uid == preferredMacUID && $0.uid != monitorDevice?.uid }
            ?? builtIns.first { $0.name.localizedCaseInsensitiveContains("speaker") || $0.name.contains("扬声器") }
            ?? builtIns.first
    }

    private func devicesChanged(force: Bool) {
        let before = (monitorDevice?.uid, macDevice?.uid)
        refreshDevices()
        let after = (monitorDevice?.uid, macDevice?.uid)
        if enabled && (force || before.0 != after.0 || before.1 != after.1) { activate() }
        updateRouteStatus()
    }

    /// Re-detects audio devices and the DDC connection.
    func rescan() {
        refreshDevices()
        connectDDC(isLaunch: false)
        if enabled { activate() }
        lastScan = Date()
    }

    /// Builds the route for the current mode and makes it the system output.
    func activate() {
        // Remember what the user had selected before we take over (read before tearing down).
        let current = AudioSystem.defaultOutput()
        if current != monitorDevice?.id, let uid = AudioSystem.uid(of: current), uid != Self.aggregateUID {
            defaults.set(uid, forKey: "restoreUID")
        }

        destroyAggregate()
        guard let monitor = monitorDevice else {
            routeStatus = "未找到显示器的音频设备"
            return
        }

        var target = monitor.id
        if mode == .combined, let mac = macDevice {
            let rate = AudioSystem.nominalSampleRate(mac.id) ?? 48_000
            let frames = UInt32((abs(syncOffsetMs) * rate / 1000).rounded())
            let macDelay: UInt32 = syncOffsetMs > 0 ? frames : 0
            let monitorDelay: UInt32 = syncOffsetMs < 0 ? frames : 0
            let id = clockIsMac
                ? AudioSystem.createMultiOutput(name: Self.aggregateName, uid: Self.aggregateUID,
                                                clockUID: mac.uid, otherUID: monitor.uid,
                                                clockExtraLatency: macDelay, otherExtraLatency: monitorDelay,
                                                driftCorrection: driftCorrection)
                : AudioSystem.createMultiOutput(name: Self.aggregateName, uid: Self.aggregateUID,
                                                clockUID: monitor.uid, otherUID: mac.uid,
                                                clockExtraLatency: monitorDelay, otherExtraLatency: macDelay,
                                                driftCorrection: driftCorrection)
            if let id {
                aggregateID = id
                target = id
            } else {
                routeStatus = "无法创建组合输出，已退回仅显示器"
            }
        }

        if !AudioSystem.setDefaultOutput(target) {
            // A freshly created aggregate can take a moment to become selectable.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                AudioSystem.setDefaultOutput(target)
                self?.updateRouteStatus()
            }
        }
        applyVolumes()
        updateRouteStatus()
    }

    /// Hands the output back to whatever was selected before and removes our aggregate.
    func deactivate() {
        let current = AudioSystem.defaultOutput()
        if (aggregateID != nil && current == aggregateID) || current == monitorDevice?.id {
            if let uid = defaults.string(forKey: "restoreUID"), let id = AudioSystem.device(forUID: uid) {
                AudioSystem.setDefaultOutput(id)
            } else if let mac = macDevice {
                AudioSystem.setDefaultOutput(mac.id)
            }
        }
        destroyAggregate()
        updateRouteStatus()
    }

    /// Rebuilds the aggregate, used after changing sync or clock settings.
    func reapplyRouting() {
        if enabled && mode == .combined { activate() }
    }

    private func destroyAggregate() {
        if let id = aggregateID { AudioSystem.destroyAggregate(id) }
        aggregateID = nil
    }

    private func updateRouteStatus() {
        guard enabled else { routeStatus = "已暂停，音量键由系统处理"; return }
        guard monitorDevice != nil else { routeStatus = "未找到显示器的音频设备"; return }
        routeStatus = isRouted
            ? (isCombinedActive ? "正在输出到显示器和 MacBook" : "正在输出到显示器")
            : "当前输出是其他设备，音量键交还系统"
    }

    // MARK: Volume

    private func shaped(_ value: Double) -> Double {
        pow(max(0, min(1, value)), max(0.5, curve))
    }

    func applyVolumes() {
        guard enabled else { return }
        let effective = shaped(muted ? 0 : master)
        if monitorDevice != nil {
            let monitorShare = monitorMuted ? 0 : monitorLevel * monitorCap
            ddc.set(UInt16((effective * monitorShare * ddcMax).rounded()))
        }
        if isCombinedActive, let mac = macDevice {
            let value = effective * macLevel
            AudioSystem.setVolume(mac.id, Float32(value))
            AudioSystem.setMute(mac.id, value == 0)
        }
    }

    private func connectDDC(isLaunch: Bool) {
        ddcStatus = "正在检测 DDC…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let display = DDCDisplay.connect()
            let reading = display?.read(VCP.volume)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let display else {
                    self.ddcConnected = false
                    self.ddcStatus = "未找到可用的 DDC 显示器，需要 Apple 芯片，建议用 USB-C 或 DP 连接"
                    return
                }
                self.ddcDisplay = display
                self.ddcConnected = true
                self.ddc.attach(display)
                if let reading, reading.max > 0 {
                    self.ddcMax = Double(reading.max)
                    self.ddcStatus = "已连接，显示器音量 \(reading.current) / \(reading.max)"
                    let share = self.monitorLevel * self.monitorCap
                    if isLaunch, self.syncFromMonitorOnLaunch, share > 0 {
                        let linear = min(1, Double(reading.current) / self.ddcMax / share)
                        self.master = pow(linear, 1 / max(0.5, self.curve))
                    }
                } else {
                    self.ddcStatus = "已连接，但读不到音量，按 0 到 100 处理"
                }
                self.applyVolumes()
            }
        }
    }

    /// Reads the monitor's current hardware volume for the DDC page.
    func readMonitorVolume() {
        guard let display = ddcDisplay else { return }
        ddcStatus = "正在读取…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let reading = display.read(VCP.volume)
            DispatchQueue.main.async {
                guard let self else { return }
                if let reading {
                    self.ddcStatus = "已连接，显示器音量 \(reading.current) / \(reading.max)"
                } else {
                    self.ddcStatus = "读取失败，显示器没有回应"
                }
            }
        }
    }

    // MARK: Keys and HUD

    private func setupKeys() {
        keyTap.shouldIntercept = { [weak self] in
            guard let self else { return false }
            return self.enabled && self.interceptKeys && self.isRouted
        }
        keyTap.handler = { [weak self] key, flags, isRepeat in
            self?.handle(key, flags: flags, isRepeat: isRepeat)
        }
        accessibilityGranted = MediaKeyTap.isTrusted(prompt: true) && keyTap.start()
        if !accessibilityGranted {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if MediaKeyTap.isTrusted(prompt: false), self.keyTap.start() {
                    self.accessibilityGranted = true
                    timer.invalidate()
                }
            }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handle(_ key: MediaKey, flags: NSEvent.ModifierFlags, isRepeat: Bool) {
        if isRepeat && !allowRepeat { return }
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)

        // Same as macOS: Option plus a volume key opens Sound settings.
        if option && !shift && optionOpensSound {
            if !isRepeat, let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let base = 1.0 / Double(max(1, stepCount))
        let step = (option && shift) ? base / 4 : base
        switch key {
        case .up:
            muted = false
            master = min(1, ((master + step) / step).rounded() * step)
        case .down:
            master = max(0, ((master - step) / step).rounded() * step)
        case .mute:
            if !isRepeat { muted.toggle() }
        }
        showHUD()
    }

    private func hudTargetScreen() -> NSScreen? {
        switch hudScreen {
        case .mouse:
            return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        case .main:
            return NSScreen.screens.first
        case .external:
            return NSScreen.screens.first { screen in
                guard let id = Self.displayID(of: screen) else { return false }
                return CGDisplayIsBuiltin(id) == 0
            } ?? NSScreen.screens.first
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func showHUD() {
        let level = muted ? 0 : master
        let screen = hudTargetScreen()
        let displayID = screen.flatMap(Self.displayID(of:)) ?? CGMainDisplayID()
        let silent = muted || level == 0

        if useNativeHUD,
           SystemOSD.show(level: level, muted: silent, displayID: displayID, duration: hudDuration) {
            return
        }
        let title = isCombinedActive ? "\(monitorTitle) + \(macTitle)" : monitorTitle
        CustomHUD.shared.show(title: title, level: level, muted: silent, on: screen,
                              position: hudPosition, duration: hudDuration)
    }
}
