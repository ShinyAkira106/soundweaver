// Controller.swift
// App state: routing (Multi Output or monitor only), volume math, key handling, HUD, settings.

import AppKit
import AudioToolbox
import CoreAudio
import ServiceManagement
import SwiftUI

enum RouteMode: String, CaseIterable, Identifiable {
    case combined, monitorOnly
    var id: String { rawValue }
}

/// How the monitor's volume is controlled.
enum VolumeEngine: String, CaseIterable, Identifiable {
    /// Soundweaver scales the monitor's audio itself (process tap, macOS 14.2 and later).
    case software
    /// The monitor's hardware volume over DDC/CI.
    case ddc
    var id: String { rawValue }

    static var softwareAvailable: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }
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
    @Published var engineMode: VolumeEngine {
        didSet { defaults.set(engineMode.rawValue, forKey: "volumeEngine"); if enabled { activate() } }
    }
    @Published var mode: RouteMode {
        didSet {
            defaults.set(mode.rawValue, forKey: "mode")
            // In software mode the MacBook switch is just a gain; no need to rebuild anything.
            if usesSoftware { applyVolumes() } else if enabled { activate() }
        }
    }
    @Published var master: Double {
        didSet {
            defaults.set(master, forKey: "master")
            // Software mode: the master volume is the MacBook's own system volume.
            if usesSoftware, !syncingFromDevice, let mac = macDevice {
                AudioSystem.setVolume(mac.id, Float32(master))
            }
            applyVolumes()
        }
    }
    @Published var monitorLevel: Double {
        didSet { defaults.set(monitorLevel, forKey: "monitorLevel"); applyVolumes() }
    }
    @Published var macLevel: Double {
        didSet { defaults.set(macLevel, forKey: "macLevel"); applyVolumes() }
    }
    @Published var muted = false {
        didSet {
            if usesSoftware, !syncingFromDevice, let mac = macDevice { AudioSystem.setMute(mac.id, muted) }
            applyVolumes()
        }
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
    /// After sleep, a replug or an input switch, reconnect DDC and write the volume again.
    @Published var restoreOnReconnect: Bool {
        didSet { defaults.set(restoreOnReconnect, forKey: "restoreOnReconnect") }
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
    @Published private(set) var engineRunning = false
    @Published private(set) var engineStatus = ""

    let updater = UpdateChecker()

    private var aggregateID: AudioObjectID?
    private var ddcMax = 100.0
    private var ddcDisplay: DDCDisplay?
    private let ddc = DDCVolumeWriter()
    private let keyTap = MediaKeyTap()
    private var trustTimer: Timer?
    private var tapEngine: AnyObject?
    private var macListeners: [DeviceListener] = []
    private var syncingFromDevice = false
    private var captureRequested = false
    private var capturePollTimer: Timer?

    var usesSoftware: Bool { engineMode == .software && VolumeEngine.softwareAvailable }

    var captureGranted: Bool { AudioCapturePermission.state == .granted }

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

    var isCombinedActive: Bool {
        mode == .combined && (usesSoftware ? engineRunning : aggregateID != nil)
    }

    /// What is actually audible right now, used by the HUD title and the status line.
    var activeOutputsTitle: String {
        let monitorOn = !monitorMuted && monitorLevel > 0.001
        let macOn = isCombinedActive && macLevel > 0.001
        switch (monitorOn, macOn) {
        case (true, true): return "\(monitorTitle) + \(macTitle)"
        case (true, false): return monitorTitle
        case (false, true): return macTitle
        default: return "全部静音"
        }
    }

    // MARK: Lifecycle

    init() {
        defaults.register(defaults: [
            "enabled": true, "mode": RouteMode.combined.rawValue,
            "volumeEngine": VolumeEngine.softwareAvailable ? VolumeEngine.software.rawValue : VolumeEngine.ddc.rawValue,
            "master": 0.4, "monitorLevel": 1.0, "macLevel": 0.6, "syncOffsetMs": 0.0,
            "preferredMonitorUID": "", "preferredMacUID": "",
            "monitorCustomName": "", "macCustomName": "",
            "clockIsMac": true, "driftCorrection": true,
            "stepCount": 16, "curve": 1.0, "monitorCap": 1.0,
            "useNativeHUD": true, "hudPosition": HUDPosition.topRight.rawValue,
            "hudScreen": HUDScreen.mouse.rawValue, "hudDuration": 1.2,
            "interceptKeys": true, "optionOpensSound": true, "allowRepeat": true,
            "restoreOnQuit": true, "syncFromMonitorOnLaunch": false, "restoreOnReconnect": true,
        ])
        enabled = defaults.bool(forKey: "enabled")
        let storedEngine = VolumeEngine(rawValue: defaults.string(forKey: "volumeEngine") ?? "") ?? .software
        engineMode = VolumeEngine.softwareAvailable ? storedEngine : .ddc
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
        restoreOnReconnect = defaults.bool(forKey: "restoreOnReconnect")
        launchAtLogin = SMAppService.mainApp.status == .enabled

        AudioSystem.destroyLeftover(uid: Self.aggregateUID)
        refreshDevices()
        setupKeys()
        ddc.onResult = { [weak self] ok in self?.ddcWriteFinished(ok) }
        watchDisplaysAndSleep()
        scheduleDDCReconnect(after: 0, reason: "正在检测 DDC…", isLaunch: true)

        AudioSystem.onSystemChange(kAudioHardwarePropertyDevices) { [weak self] in self?.devicesChanged(force: false) }
        AudioSystem.onSystemChange(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.defaultOutputChanged() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.stopEngine()
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
        // The monitor's audio device came back (replug, input switch, wake): its DDC
        // connection is new too, and the monitor needs a moment before it answers.
        if after.0 != nil && before.0 != after.0 {
            scheduleDDCReconnect(after: 2, reason: "显示器已重新连接，正在等待它准备好…")
        }
    }

    /// Re-detects audio devices and the DDC connection.
    func rescan() {
        refreshDevices()
        scheduleDDCReconnect(after: 0, reason: "正在重新检测 DDC…")
        if enabled { activate() }
        lastScan = Date()
    }

    /// Builds the route for the current engine and mode.
    func activate() {
        if usesSoftware {
            activateSoftware()
        } else {
            stopEngine()
            removeMacListeners()
            activateHardware()
        }
    }

    // MARK: Software mix engine

    private func activateSoftware() {
        destroyAggregate()
        guard let monitor = monitorDevice, let mac = macDevice else {
            stopEngine()
            updateRouteStatus()
            return
        }
        let current = AudioSystem.defaultOutput()
        if current != mac.id, current != monitor.id,
           let uid = AudioSystem.uid(of: current), uid != Self.aggregateUID {
            defaults.set(uid, forKey: "restoreUID")
        }
        // The system output stays on the MacBook speakers: real volume, native keys and HUD.
        if current != mac.id { AudioSystem.setDefaultOutput(mac.id) }
        watchMacDevice(mac)
        syncFromMacDevice()
        startEngine()
    }

    private func startEngine() {
        guard enabled, usesSoftware, let mac = macDevice, let monitor = monitorDevice else { return }
        guard AudioSystem.defaultOutput() == mac.id else {
            stopEngine()
            updateRouteStatus()
            return
        }
        guard #available(macOS 14.2, *) else { return }

        switch AudioCapturePermission.state {
        case .denied:
            stopEngine()
            engineStatus = "需要“系统录音”权限才能混音"
            updateRouteStatus()
            waitForCapturePermission()
            return
        case .unknown where !captureRequested:
            captureRequested = true
            AudioCapturePermission.request { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startEngine()
                } else {
                    self.engineStatus = "需要“系统录音”权限才能混音"
                    self.updateRouteStatus()
                    self.waitForCapturePermission()
                }
            }
            return
        default:
            break
        }

        let engine = (tapEngine as? TapEngine) ?? TapEngine()
        tapEngine = engine
        let rate = AudioSystem.nominalSampleRate(mac.id) ?? 48_000
        let frames = UInt32((abs(syncOffsetMs) * rate / 1000).rounded())
        do {
            try engine.start(macUID: mac.uid, monitorUID: monitor.uid,
                             macOutputStreams: AudioSystem.outputStreamCount(mac.id),
                             macExtraLatency: syncOffsetMs > 0 ? frames : 0,
                             monitorExtraLatency: syncOffsetMs < 0 ? frames : 0,
                             clockIsMac: clockIsMac, driftCorrection: driftCorrection)
            engineRunning = true
            engineStatus = ""
        } catch {
            engineRunning = false
            engineStatus = "软件混音启动失败：\(error)"
        }
        applyVolumes()
        updateRouteStatus()
    }

    /// Starts the engine as soon as the permission is switched on in System Settings.
    private func waitForCapturePermission() {
        guard capturePollTimer == nil else { return }
        capturePollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.usesSoftware, self.enabled else {
                timer.invalidate()
                self?.capturePollTimer = nil
                return
            }
            if AudioCapturePermission.state == .granted {
                timer.invalidate()
                self.capturePollTimer = nil
                self.engineStatus = ""
                self.startEngine()
            }
        }
    }

    private func stopEngine() {
        if #available(macOS 14.2, *), let engine = tapEngine as? TapEngine { engine.stop() }
        engineRunning = false
    }

    private func defaultOutputChanged() {
        if enabled && usesSoftware {
            if AudioSystem.defaultOutput() == macDevice?.id {
                if !engineRunning { startEngine() }
            } else {
                // The user picked AirPods or something else: release every app's audio.
                stopEngine()
            }
        }
        updateRouteStatus()
    }

    private func watchMacDevice(_ mac: AudioDevice) {
        removeMacListeners()
        let scope = kAudioDevicePropertyScopeOutput
        let watched: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in watched {
            if let listener = AudioSystem.addListener(mac.id, selector, scope, element, { [weak self] in
                self?.syncFromMacDevice()
            }) {
                macListeners.append(listener)
            }
        }
    }

    private func removeMacListeners() {
        macListeners.forEach(AudioSystem.removeListener)
        macListeners.removeAll()
    }

    /// Pulls the MacBook's system volume and mute into the panel and recomputes the gains.
    private func syncFromMacDevice() {
        guard usesSoftware, let mac = macDevice else { return }
        syncingFromDevice = true
        if let scalar = AudioSystem.volumeScalar(mac.id), abs(Double(scalar) - master) > 0.0005 {
            master = Double(scalar)
        }
        let deviceMuted = AudioSystem.isMuted(mac.id)
        if deviceMuted != muted { muted = deviceMuted }
        syncingFromDevice = false
        applyVolumes()
    }

    func openAudioCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Hardware (DDC) route

    private func activateHardware() {
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
        stopEngine()
        removeMacListeners()
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
        if enabled && (mode == .combined || usesSoftware) { activate() }
    }

    private func destroyAggregate() {
        if let id = aggregateID { AudioSystem.destroyAggregate(id) }
        aggregateID = nil
    }

    private func updateRouteStatus() {
        let text: String
        if !enabled {
            text = "已暂停，音量键由系统处理"
        } else if monitorDevice == nil {
            text = "未找到显示器的音频设备"
        } else if usesSoftware {
            if macDevice == nil {
                text = "未找到 MacBook 扬声器"
            } else if !engineStatus.isEmpty {
                text = engineStatus
            } else if AudioSystem.defaultOutput() != macDevice?.id {
                text = "当前输出是其他设备，混音已暂停"
            } else {
                text = engineRunning ? "正在输出：\(activeOutputsTitle)" : "正在启动软件混音…"
            }
        } else {
            text = isRouted ? "正在输出：\(activeOutputsTitle)" : "当前输出是其他设备，音量键交还系统"
        }
        if text != routeStatus { routeStatus = text }
    }

    // MARK: Volume

    private func shaped(_ value: Double) -> Double {
        pow(max(0, min(1, value)), max(0.5, curve))
    }

    func applyVolumes() {
        defer { updateRouteStatus() }
        guard enabled else { return }
        if usesSoftware {
            updateEngineGains()
            return
        }
        let effective = shaped(muted ? 0 : master)
        if monitorDevice != nil {
            ddc.set(monitorDDCTarget())
        }
        if isCombinedActive, let mac = macDevice {
            let value = effective * macLevel
            AudioSystem.setVolume(mac.id, Float32(value))
            AudioSystem.setMute(mac.id, value == 0)
        }
    }

    /// Perceptual taper for the share sliders: 50% is about 12 dB down.
    private func taper(_ value: Double) -> Double {
        let x = max(0, min(1, value))
        return x * x
    }

    private func updateEngineGains() {
        guard #available(macOS 14.2, *), let engine = tapEngine as? TapEngine else { return }
        // MacBook: the system volume already applies on the device, so only its share here.
        engine.gains.mac = mode == .combined ? Float(taper(macLevel)) : 0
        // Monitor: has no volume of its own, so follow the MacBook's volume in decibels.
        var follow = 0.0
        if let mac = macDevice, !muted, master > 0.0005 {
            if let db = AudioSystem.volumeDecibels(mac.id) {
                follow = pow(10, Double(db) / 20)
            } else {
                follow = master * master
            }
        }
        engine.gains.monitor = monitorMuted ? 0 : Float(taper(monitorLevel) * monitorCap * follow)
    }

    // MARK: DDC connection and recovery
    //
    // A monitor's DDC connection is recreated whenever it sleeps, is replugged or switches
    // input, and the old handle silently stops working. Right after it comes back, the monitor
    // also needs a few seconds before it answers, and it may restore its own old volume once
    // it has finished starting up. So, like MonitorControl, Soundweaver waits, reconnects,
    // retries until the monitor answers, then writes the volume again several times and reads
    // it back until the monitor has kept it.

    private static let ddcConnectAttempts = 6
    private var ddcGeneration = 0
    private var isAsleep = false
    private var ddcReconnecting = false
    private var ddcFailures = 0
    private var lastAutoReconnect = Date.distantPast

    /// What the monitor's hardware volume should be right now: the mixed level in DDC mode,
    /// or simply its cap in software mode (where Soundweaver scales the audio itself).
    private func monitorDDCTarget() -> UInt16 {
        if usesSoftware { return UInt16((ddcMax * monitorCap).rounded()) }
        let effective = shaped(muted ? 0 : master)
        let share = monitorMuted ? 0 : monitorLevel * monitorCap
        return UInt16((effective * share * ddcMax).rounded())
    }

    private func bumpDDCGeneration() -> Int {
        ddcGeneration += 1
        ddc.generation = ddcGeneration
        return ddcGeneration
    }

    private func watchDisplaysAndSleep() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
            let controller = Unmanaged<Controller>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { controller.displaysReconfigured() }
        }, Unmanaged.passUnretained(self).toOpaque())

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isAsleep = true
                _ = self.bumpDDCGeneration()   // stop anything in flight
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isAsleep = false
                // Some displays take a few seconds to recover after waking.
                self.scheduleDDCReconnect(after: 3, reason: "已唤醒，正在等待显示器准备好…")
            }
        }
    }

    func displaysReconfigured() {
        guard !isAsleep else { return }
        scheduleDDCReconnect(after: 2, reason: "显示器配置已改变，正在重新连接…")
    }

    /// Waits for the monitor to settle, then reconnects. Repeated requests collapse into the last one.
    func scheduleDDCReconnect(after delay: TimeInterval, reason: String, isLaunch: Bool = false) {
        let generation = bumpDDCGeneration()
        ddcReconnecting = true
        ddcStatus = reason
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.ddcGeneration, !self.isAsleep else { return }
            self.connectDDC(generation: generation, attempt: 1, isLaunch: isLaunch)
        }
    }

    private func connectDDC(generation: Int, attempt: Int, isLaunch: Bool) {
        ddc.detach()
        ddc.perform { [weak self] in
            let display = DDCDisplay.connect()
            let reading = display?.read(VCP.volume)
            DispatchQueue.main.async {
                guard let self, generation == self.ddcGeneration else { return }

                // Not answering yet: a freshly woken monitor often needs a few more seconds.
                if reading == nil && attempt < Self.ddcConnectAttempts {
                    self.ddcStatus = "正在等待显示器响应（第 \(attempt) 次）…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        guard let self, generation == self.ddcGeneration, !self.isAsleep else { return }
                        self.connectDDC(generation: generation, attempt: attempt + 1, isLaunch: isLaunch)
                    }
                    return
                }

                self.ddcReconnecting = false
                guard let display else {
                    self.ddcDisplay = nil
                    self.ddcConnected = false
                    self.ddcStatus = "未找到可用的 DDC 显示器，需要 Apple 芯片，建议用 USB-C 或 DP 连接"
                    return
                }
                self.ddcDisplay = display
                self.ddcConnected = true
                self.ddcFailures = 0
                self.ddc.attach(display)

                guard let reading, reading.max > 0 else {
                    self.ddcStatus = "已连接，但读不到音量，按 0 到 100 处理"
                    self.restoreMonitorVolume(generation: generation, readable: false)
                    return
                }
                self.ddcMax = Double(reading.max)
                self.ddcStatus = "已连接，显示器音量 \(reading.current) / \(reading.max)"

                let share = self.monitorLevel * self.monitorCap
                if isLaunch, self.syncFromMonitorOnLaunch, !self.usesSoftware, share > 0 {
                    // Take the monitor's volume as the starting point instead of overwriting it.
                    let linear = min(1, Double(reading.current) / self.ddcMax / share)
                    self.master = pow(linear, 1 / max(0.5, self.curve))
                    return
                }
                self.restoreMonitorVolume(generation: generation, readable: true)
            }
        }
    }

    /// Writes the target volume again, once a second, until the monitor has kept it twice in a
    /// row (or, if it cannot be read back, five times), for at most about eight seconds.
    private func restoreMonitorVolume(generation: Int, readable: Bool) {
        guard enabled, let display = ddcDisplay else { return }
        if !usesSoftware {
            applyVolumes()   // the normal write, which also records the latest target
        }
        guard restoreOnReconnect else { return }

        let software = usesSoftware
        let fixedTarget = monitorDDCTarget()
        let writer = ddc
        let needed = readable ? 2 : 5
        ddcStatus = "已连接，正在恢复显示器音量…"

        writer.perform { [weak self] in
            var kept = 0
            var target = fixedTarget
            for round in 0..<8 {
                guard writer.generation == generation else { return }
                if round > 0 { Thread.sleep(forTimeInterval: 1) }
                guard writer.generation == generation else { return }
                target = software ? fixedTarget : (writer.latestTarget ?? fixedTarget)
                let ok = readable ? display.writeVerified(VCP.volume, target)
                                  : display.write(VCP.volume, target)
                kept = ok ? kept + 1 : 0
                if kept >= needed { break }
            }
            let finalTarget = target
            let success = kept >= needed
            DispatchQueue.main.async {
                guard let self, generation == self.ddcGeneration else { return }
                self.ddcStatus = success
                    ? "已连接，显示器音量已恢复为 \(finalTarget)"
                    : "已连接，但显示器没有保持音量；按一下音量键可以再写一次"
            }
        }
    }

    /// Two failed writes in a row usually mean the connection went stale without any
    /// notification (for example a KVM or input switch), so reconnect on our own.
    private func ddcWriteFinished(_ ok: Bool) {
        guard !usesSoftware else { return }
        if ok {
            ddcFailures = 0
            return
        }
        // While reconnecting, writes are expected to fail; the restore will catch up.
        guard !ddcReconnecting, !isAsleep else { return }
        ddcFailures += 1
        ddcStatus = "写入失败：显示器没有接受音量命令"
        guard ddcFailures >= 2,
              Date().timeIntervalSince(lastAutoReconnect) > 10 else { return }
        lastAutoReconnect = Date()
        scheduleDDCReconnect(after: 0.5, reason: "连接似乎已中断，正在重新连接显示器…")
    }

    /// Reads the monitor's current hardware volume for the DDC page.
    func readMonitorVolume() {
        guard let display = ddcDisplay else { return }
        ddcStatus = "正在读取…"
        ddc.perform { [weak self] in
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

    /// Drops the monitor to 10% for two seconds and restores it, so you can hear whether
    /// the speakers on the monitor's jack follow DDC at all.
    func testDDC() {
        guard let display = ddcDisplay else { ddcStatus = "没有可用的 DDC 显示器"; return }
        ddcStatus = "测试中：显示器音量降到 10%，两秒后恢复，请听音箱的变化…"
        ddc.perform { [weak self] in
            let before = display.read(VCP.volume)
            let maxValue = before?.max ?? 100
            let low = UInt16(Double(maxValue) * 0.1)
            let wrote = display.write(VCP.volume, low)
            let during = display.read(VCP.volume)
            Thread.sleep(forTimeInterval: 2)
            display.write(VCP.volume, before?.current ?? maxValue / 2)
            DispatchQueue.main.async {
                guard let self else { return }
                if !wrote {
                    self.ddcStatus = "测试失败：显示器拒绝了写入命令，请改用软件混音"
                } else if let during, during.current == low {
                    self.ddcStatus = "显示器已接受命令（读数变为 \(during.current)）。如果音箱刚才没有变小，说明耳机口不跟随显示器音量，请使用软件混音"
                } else {
                    self.ddcStatus = "命令已发送，但显示器读数没有变化，请改用软件混音"
                }
            }
        }
    }

    /// For software mode: turn the monitor itself all the way up (to the cap) once,
    /// so Soundweaver's software gain has the full range.
    func setMonitorHardwareToCap() {
        guard let display = ddcDisplay else { ddcStatus = "没有可用的 DDC 显示器，请用显示器自己的菜单调高音量"; return }
        let target = UInt16((ddcMax * monitorCap).rounded())
        ddc.perform { [weak self] in
            let ok = display.write(VCP.volume, target)
            DispatchQueue.main.async {
                self?.ddcStatus = ok ? "已把显示器硬件音量设为 \(target)" : "写入失败，请用显示器自己的菜单调高音量"
            }
        }
    }

    // MARK: Keys and HUD

    private func setupKeys() {
        keyTap.shouldIntercept = { [weak self] in
            guard let self else { return false }
            // Software mode leaves the keys to macOS: they change the MacBook volume natively.
            return self.enabled && !self.usesSoftware && self.interceptKeys && self.isRouted
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
        let title = activeOutputsTitle
        CustomHUD.shared.show(title: title, level: level, muted: silent, on: screen,
                              position: hudPosition, duration: hudDuration)
    }
}
