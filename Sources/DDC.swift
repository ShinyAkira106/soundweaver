// DDC.swift
// DDC/CI over the private IOAVService API on Apple silicon (the approach used by
// MonitorControl and m1ddc). Intel Macs are not supported by this file.

import Foundation
import IOKit

private typealias AVCreateFn = @convention(c) (CFAllocator?, io_service_t) -> OpaquePointer?
private typealias AVI2CFn = @convention(c) (OpaquePointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

private enum IOAV {
    static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    static let create = symbol("IOAVServiceCreateWithService", as: AVCreateFn.self)
    static let read = symbol("IOAVServiceReadI2C", as: AVI2CFn.self)
    static let write = symbol("IOAVServiceWriteI2C", as: AVI2CFn.self)
}

enum VCP {
    static let volume: UInt8 = 0x62
    static let mute: UInt8 = 0x8D
}

final class DDCDisplay {
    private let service: OpaquePointer
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    private init(service: OpaquePointer) { self.service = service }

    /// Finds external displays reachable over DDC; prefers one that answers a volume read.
    static func connect() -> DDCDisplay? {
        guard let create = IOAV.create else { return nil }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceNameMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var candidates: [DDCDisplay] = []
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "Location" as CFString,
                                                           kCFAllocatorDefault,
                                                           IOOptionBits(kIORegistryIterateRecursively)) as? String
            guard location == "External", let av = create(kCFAllocatorDefault, entry) else { continue }
            candidates.append(DDCDisplay(service: av))
        }
        return candidates.first { $0.read(VCP.volume) != nil } ?? candidates.first
    }

    @discardableResult
    func write(_ code: UInt8, _ value: UInt16) -> Bool {
        guard let writeI2C = IOAV.write else { return false }
        var packet: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        var ok = false
        for _ in 0..<2 {   // sending twice is what MonitorControl does for reliability
            usleep(10_000)
            if writeI2C(service, Self.chipAddress, Self.dataAddress, &packet, UInt32(packet.count)) == KERN_SUCCESS {
                ok = true
            }
        }
        return ok
    }

    func read(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C = IOAV.write, let readI2C = IOAV.read else { return nil }
        for _ in 0..<4 {
            var request: [UInt8] = [0x82, 0x01, code, 0]
            request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2]
            var reply = [UInt8](repeating: 0, count: 12)
            usleep(10_000)
            guard writeI2C(service, Self.chipAddress, Self.dataAddress, &request, UInt32(request.count)) == KERN_SUCCESS
            else { continue }
            usleep(50_000)
            guard readI2C(service, Self.chipAddress, Self.dataAddress, &reply, UInt32(reply.count)) == KERN_SUCCESS
            else { continue }
            // reply: [src, len, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, checksum]
            guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { continue }
            let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return (current, maxValue)
        }
        return nil
    }
}

/// Serialises DDC writes on a background queue and drops stale values, so dragging a
/// slider or holding a key never queues up dozens of slow I2C transactions.
final class DDCVolumeWriter {
    private let queue = DispatchQueue(label: "soundweaver.ddc", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: UInt16?
    private var draining = false
    private var display: DDCDisplay?
    /// Called on the main queue after each write with whether the monitor accepted it.
    var onResult: ((Bool) -> Void)?

    func attach(_ display: DDCDisplay) {
        lock.lock(); self.display = display; lock.unlock()
    }

    func set(_ value: UInt16) {
        lock.lock()
        pending = value
        let start = !draining
        if start { draining = true }
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let value = pending else { draining = false; lock.unlock(); return }
            pending = nil
            let target = display
            lock.unlock()
            let ok = target?.write(VCP.volume, value) ?? false
            if let callback = onResult {
                DispatchQueue.main.async { callback(ok) }
            }
        }
    }
}
