// TapEngine.swift
// Software mix engine (macOS 14.2 and later).
//
// Why: an HDMI / DisplayPort / USB-C audio output has no volume macOS can change, and many
// monitors do not let DDC change the level on their headphone jack either. So instead of
// asking the monitor to turn itself down, Soundweaver turns the audio down before it gets there.
//
// How: a global Core Audio process tap captures everything the system plays (except
// Soundweaver itself) and mutes the original output. A private aggregate device combines that
// tap with the MacBook speakers and the monitor. One IOProc copies the captured audio into
// each output with its own gain. The system output stays on the MacBook speakers, so the
// volume keys and the native system HUD work exactly as normal; the monitor's gain follows
// the MacBook's volume in decibels.

import AudioToolbox
import CoreAudio
import Foundation

/// Two gains shared with the audio thread without locks (aligned Float writes are atomic
/// on Apple silicon and Intel).
final class EngineGains {
    let storage: UnsafeMutablePointer<Float>

    init() {
        storage = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        storage.initialize(repeating: 0, count: 2)
    }

    deinit { storage.deallocate() }

    var mac: Float {
        get { storage[0] }
        set { storage[0] = newValue }
    }

    var monitor: Float {
        get { storage[1] }
        set { storage[1] = newValue }
    }
}

struct EngineError: Error, CustomStringConvertible {
    let step: String
    let status: OSStatus
    var description: String { "\(step)（错误码 \(status)）" }
}

@available(macOS 14.2, *)
final class TapEngine {
    let gains = EngineGains()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.shinyakira.soundweaver.engine", qos: .userInteractive)

    private(set) var isRunning = false

    deinit { stop() }

    func start(macUID: String, monitorUID: String, macOutputStreams: Int,
               macExtraLatency: UInt32, monitorExtraLatency: UInt32,
               clockIsMac: Bool, driftCorrection: Bool) throws {
        stop()
        do {
            try build(macUID: macUID, monitorUID: monitorUID, macOutputStreams: macOutputStreams,
                      macExtraLatency: macExtraLatency, monitorExtraLatency: monitorExtraLatency,
                      clockIsMac: clockIsMac, driftCorrection: driftCorrection)
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            // Destroying the tap un-mutes every app immediately.
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        isRunning = false
    }

    private func build(macUID: String, monitorUID: String, macOutputStreams: Int,
                       macExtraLatency: UInt32, monitorExtraLatency: UInt32,
                       clockIsMac: Bool, driftCorrection: Bool) throws {
        // 1. Global tap of everything except ourselves, muting the original output.
        var excluded: [AudioObjectID] = []
        if let me = AudioSystem.processObject(pid: getpid()) { excluded.append(me) }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Soundweaver"
        description.isPrivate = true
        description.muteBehavior = .muted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw EngineError(step: "无法创建系统音频捕获", status: status)
        }
        tapID = tap

        // 2. Private aggregate: MacBook speakers first, then the monitor, plus the tap as input.
        let macSub: [String: Any] = [
            kAudioSubDeviceUIDKey: macUID,
            kAudioSubDeviceDriftCompensationKey: (!clockIsMac && driftCorrection) ? 1 : 0,
            kAudioSubDeviceExtraOutputLatencyKey: Int(macExtraLatency),
        ]
        let monitorSub: [String: Any] = [
            kAudioSubDeviceUIDKey: monitorUID,
            kAudioSubDeviceDriftCompensationKey: (clockIsMac && driftCorrection) ? 1 : 0,
            kAudioSubDeviceExtraOutputLatencyKey: Int(monitorExtraLatency),
        ]
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Soundweaver Engine",
            kAudioAggregateDeviceUIDKey: "com.shinyakira.soundweaver.engine.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: clockIsMac ? macUID : monitorUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [macSub, monitorSub],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: 1],
            ],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw EngineError(step: "无法创建混音设备", status: status)
        }
        aggregateID = device

        // 3. The render callback.
        let gainPointer = gains.storage
        let macBuffers = max(1, macOutputStreams)
        var newProc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProc, device, queue) { _, input, _, output, _ in
            TapEngine.render(input, output, macBuffers: macBuffers, gains: gainPointer)
        }
        guard status == noErr, let newProc else {
            throw EngineError(step: "无法创建音频回调", status: status)
        }
        procID = newProc

        status = AudioDeviceStart(device, newProc)
        guard status == noErr else {
            throw EngineError(step: "无法启动混音", status: status)
        }
    }

    /// Real time: no allocation, no locks, no Objective C.
    /// Output buffers come in sub device order, so the first `macBuffers` belong to the MacBook.
    private static func render(_ input: UnsafePointer<AudioBufferList>,
                               _ output: UnsafeMutablePointer<AudioBufferList>,
                               macBuffers: Int,
                               gains: UnsafeMutablePointer<Float>) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let floatSize = MemoryLayout<Float>.size

        let inCount = inList.count
        var inChannelsPerBuffer = 1
        var inFrames = 0
        var interleavedIn: UnsafeMutablePointer<Float>? = nil
        if inCount > 0 {
            let first = inList[0]
            inChannelsPerBuffer = Int(max(1, first.mNumberChannels))
            inFrames = Int(first.mDataByteSize) / (floatSize * inChannelsPerBuffer)
            interleavedIn = first.mData?.assumingMemoryBound(to: Float.self)
        }
        let totalInChannels = inCount == 1 ? inChannelsPerBuffer : inCount

        for index in 0..<outList.count {
            let out = outList[index]
            guard let raw = out.mData else { continue }
            let byteCount = Int(out.mDataByteSize)
            let gain = index < macBuffers ? gains[0] : gains[1]
            if gain <= 0 || inCount == 0 || totalInChannels == 0 {
                memset(raw, 0, byteCount)
                continue
            }
            let outData = raw.assumingMemoryBound(to: Float.self)
            let outChannels = Int(max(1, out.mNumberChannels))
            let frames = byteCount / (floatSize * outChannels)

            for frame in 0..<frames {
                for channel in 0..<outChannels {
                    var sample: Float = 0
                    if frame < inFrames && (channel < totalInChannels || totalInChannels == 1) {
                        let source = totalInChannels == 1 ? 0 : channel
                        if inCount == 1 {
                            if let data = interleavedIn { sample = data[frame * inChannelsPerBuffer + source] }
                        } else if let data = inList[source].mData?.assumingMemoryBound(to: Float.self) {
                            sample = data[frame]
                        }
                    }
                    outData[frame * outChannels + channel] = sample * gain
                }
            }
        }
    }
}

/// The "System Audio Recording" privacy permission a process tap needs.
/// Uses the TCC calls that Apple's own sample and AudioCap use; if they are unavailable
/// the state is reported as unknown and the system asks when the tap starts.
enum AudioCapturePermission {
    enum State { case granted, denied, unknown }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    static var state: State {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: PreflightFn.self)
        switch preflight(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else {
            completion(true)
            return
        }
        let request = unsafeBitCast(symbol, to: RequestFn.self)
        request(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
