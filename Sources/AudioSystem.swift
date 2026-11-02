// AudioSystem.swift
// Thin Core Audio helpers: device enumeration, default output, volume, aggregate devices.

import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isDisplay: Bool {
        transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
    }
}

enum AudioSystem {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: Generic getters

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ref)
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    // MARK: Devices

    static func allDeviceIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func hasOutputStreams(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// Real output devices (aggregates excluded, including our own).
    static func outputDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap { id in
            guard hasOutputStreams(id),
                  let uid = uid(of: id),
                  let transport = uint32(id, kAudioDevicePropertyTransportType),
                  transport != kAudioDeviceTransportTypeAggregate
            else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? uid
            return AudioDevice(id: id, uid: uid, name: name, transport: transport)
        }
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(system, &addr,
                                       UInt32(MemoryLayout<CFString>.size), qualifier,
                                       &size, &device)
        }
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr ? rate : nil
    }

    // MARK: Default output

    static func defaultOutput() -> AudioObjectID {
        uint32(system, kAudioHardwarePropertyDefaultOutputDevice) ?? AudioObjectID(kAudioObjectUnknown)
    }

    @discardableResult
    static func setDefaultOutput(_ device: AudioObjectID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        return AudioObjectSetPropertyData(system, &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    // MARK: Volume (used for the MacBook speakers)

    @discardableResult
    static func setVolume(_ device: AudioObjectID, _ volume: Float32) -> Bool {
        let size = UInt32(MemoryLayout<Float32>.size)
        var value = max(0, min(1, volume))

        var main = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(device, &main),
           AudioObjectSetPropertyData(device, &main, 0, nil, size, &value) == noErr {
            return true
        }

        // Fallback: per channel scalar volume.
        var ok = false
        for channel: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, channel)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &addr),
                  AudioObjectIsPropertySettable(device, &addr, &settable) == noErr,
                  settable.boolValue else { continue }
            if AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value) == noErr { ok = true }
        }
        return ok
    }

    static func setMute(_ device: AudioObjectID, _ muted: Bool) {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Multi Output (stacked aggregate) device

    /// Creates a public Multi Output Device. `clockUID` is the clock source; the other
    /// device gets drift correction. Extra latency (in frames) lets us line the two up.
    static func createMultiOutput(name: String, uid: String,
                                  clockUID: String, otherUID: String,
                                  clockExtraLatency: UInt32, otherExtraLatency: UInt32,
                                  driftCorrection: Bool = true) -> AudioObjectID? {
        let subDevices: [[String: Any]] = [
            [kAudioSubDeviceUIDKey: clockUID,
             kAudioSubDeviceDriftCompensationKey: 0,
             kAudioSubDeviceExtraOutputLatencyKey: Int(clockExtraLatency)],
            [kAudioSubDeviceUIDKey: otherUID,
             kAudioSubDeviceDriftCompensationKey: driftCorrection ? 1 : 0,
             kAudioSubDeviceExtraOutputLatencyKey: Int(otherExtraLatency)],
        ]
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceIsStackedKey: 1,   // stacked = Multi Output
            kAudioAggregateDeviceIsPrivateKey: 0,   // public, so it can be the system output
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func destroyAggregate(_ device: AudioObjectID) {
        AudioHardwareDestroyAggregateDevice(device)
    }

    /// Removes an aggregate left behind by a crash.
    static func destroyLeftover(uid: String) {
        if let id = device(forUID: uid) { destroyAggregate(id) }
    }

    // MARK: Listeners

    static func onSystemChange(_ selector: AudioObjectPropertySelector, _ block: @escaping () -> Void) {
        var addr = address(selector)
        AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { _, _ in block() }
    }
}
