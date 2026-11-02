// MediaKeyTap.swift
// Catches the volume up / down / mute media keys with a CGEvent tap.
// Needs the Accessibility permission.

import AppKit
import ApplicationServices

enum MediaKey { case up, down, mute }

final class MediaKeyTap {
    /// Return true from `shouldIntercept` to take the key away from the system.
    var shouldIntercept: () -> Bool = { false }
    var handler: (MediaKey, NSEvent.ModifierFlags, Bool) -> Void = { _, _, _ in }

    fileprivate var tap: CFMachPort?

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let systemDefined: UInt64 = 14   // NX_SYSDEFINED
        let mask = CGEventMask(1 << systemDefined)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: mediaKeyCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return .passUnretained(event) }
    let owner = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = owner.tap { CGEvent.tapEnable(tap: port, enable: true) }
        return .passUnretained(event)
    }

    guard type.rawValue == 14,
          let nsEvent = NSEvent(cgEvent: event),
          nsEvent.subtype.rawValue == 8   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    else { return .passUnretained(event) }

    let code = (nsEvent.data1 & 0xFFFF_0000) >> 16
    let flags = nsEvent.data1 & 0x0000_FFFF
    let isDown = ((flags & 0xFF00) >> 8) == 0xA
    let isRepeat = (flags & 0x1) == 0x1

    let key: MediaKey
    switch code {
    case 0: key = .up      // NX_KEYTYPE_SOUND_UP
    case 1: key = .down    // NX_KEYTYPE_SOUND_DOWN
    case 7: key = .mute    // NX_KEYTYPE_MUTE
    default: return .passUnretained(event)
    }

    guard owner.shouldIntercept() else { return .passUnretained(event) }
    if isDown { owner.handler(key, nsEvent.modifierFlags, isRepeat) }
    return nil   // swallow both key down and key up so the grey system HUD never shows
}
