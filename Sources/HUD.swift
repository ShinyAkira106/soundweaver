// HUD.swift
// Native system volume HUD via the private OSDManager (as BetterDisplay / MonitorControl do),
// plus a self drawn fallback panel in case a macOS update changes the private API.

import AppKit
import SwiftUI

enum NativeOSD {
    private typealias ShowFn = @convention(c) (AnyObject, Selector, Int64, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void
    private static let showSelector =
        NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChicklets:totalChicklets:locked:")

    private typealias SharedFn = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?

    private static let manager: NSObject? = {
        guard Bundle(path: "/System/Library/PrivateFrameworks/OSD.framework")?.load() == true,
              let cls = NSClassFromString("OSDManager") else { return nil }
        let shared = NSSelectorFromString("sharedManager")
        guard let method = class_getClassMethod(cls, shared) else { return nil }
        let function = unsafeBitCast(method_getImplementation(method), to: SharedFn.self)
        return function(cls, shared)?.takeUnretainedValue() as? NSObject
    }()

    /// Returns false when the private API is unavailable, so the caller can fall back.
    static func show(level: Double, muted: Bool, displayID: CGDirectDisplayID, duration: Double = 1.0) -> Bool {
        guard let manager, manager.responds(to: showSelector) else { return false }
        let function = unsafeBitCast(manager.method(for: showSelector), to: ShowFn.self)
        let total: UInt32 = 160            // 16 segments, 10 sub steps each for smooth fine steps
        let filled = muted ? 0 : UInt32((max(0, min(1, level)) * Double(total)).rounded())
        let image: Int64 = muted ? 4 : 3   // 3 = speaker, 4 = speaker muted
        function(manager, showSelector, image, displayID, 0x1F4, UInt32(max(0.3, duration) * 1000), filled, total, false)
        return true
    }
}

// MARK: System OSD over XPC

/// The interface of Apple's OSDUIHelper service (see MonitorControl's Bridging-Header.h).
@objc(OSDUIHelperProtocol)
protocol OSDUIHelperProtocol {
    @objc(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:)
    func showImage(_ image: Int64, onDisplayID displayID: UInt32, priority: UInt32, msecUntilFade: UInt32,
                   filledChiclets: UInt32, totalChiclets: UInt32, locked: Bool)
}

/// Shows the real system volume OSD. On macOS 26 and 27 it talks to com.apple.OSDUIHelper
/// directly over XPC, which brings up the classic system bezel with the correct level
/// (the same approach MonitorControl 4.4 takes). Earlier systems use OSDManager.
enum SystemOSD {
    private static var connection: NSXPCConnection?

    static var usesXPC: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 26
    }

    @discardableResult
    static func show(level: Double, muted: Bool, displayID: CGDirectDisplayID, duration: Double) -> Bool {
        guard usesXPC else {
            return NativeOSD.show(level: level, muted: muted, displayID: displayID, duration: duration)
        }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(level: level, muted: muted, displayID: displayID, duration: duration) }
            return true
        }
        guard let helper = helper() else { return false }

        let clamped = max(0, min(1, muted ? 0 : level))
        let sixteenths = clamped * 16
        // Whole steps use the 16 classic chiclets; fine steps fall back to a 100 point scale.
        let onGrid = abs(sixteenths - sixteenths.rounded()) < 0.001
        let filled = onGrid ? UInt32(sixteenths.rounded()) : UInt32((clamped * 100).rounded())
        let total: UInt32 = onGrid ? 16 : 100
        helper.showImage(muted || clamped == 0 ? 4 : 3, onDisplayID: displayID, priority: 0x1F4,
                         msecUntilFade: UInt32(max(0.3, duration) * 1000),
                         filledChiclets: filled, totalChiclets: total, locked: false)
        return true
    }

    private static func helper() -> OSDUIHelperProtocol? {
        let connection: NSXPCConnection
        if let existing = self.connection {
            connection = existing
        } else {
            connection = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
            connection.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
            connection.interruptionHandler = { DispatchQueue.main.async { reset() } }
            connection.invalidationHandler = { DispatchQueue.main.async { SystemOSD.connection = nil } }
            self.connection = connection
            connection.resume()
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async { reset() }
        }
        guard let helper = proxy as? OSDUIHelperProtocol else {
            reset()
            return nil
        }
        return helper
    }

    private static func reset() {
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }
}

// MARK: Soundweaver HUD

final class HUDModel: ObservableObject {
    @Published var title = ""
    @Published var level = 0.0
    @Published var muted = false
}

enum HUDMetrics {
    static let width: CGFloat = 292
    static let height: CGFloat = 60
    static let corner: CGFloat = 20
}

/// Volume HUD modelled on the macOS 26 system design: a clear glass card, the output name
/// on top, a thin bar between two speaker glyphs, and a row of tick dots under the bar.
/// The glass is kept very transparent; legibility on bright backgrounds comes from a soft
/// dark halo around the white foreground and an outlined track, as Apple suggests for clear glass.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    let ticks = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 9) {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 13)
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.22))
                            Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.7)
                            Capsule().fill(Color.white)
                                .frame(width: max(0, geo.size.width * (model.muted ? 0 : model.level)))
                        }
                    }
                    .frame(height: 5)
                    HStack(spacing: 0) {
                        ForEach(0...ticks, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: 2, height: 2)
                            if i < ticks { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(.top, 4)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12.5, weight: .semibold))
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0, y: 0.5)
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 0)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: HUDMetrics.width, height: HUDMetrics.height, alignment: .leading)
        .modifier(HUDBackground())
    }
}

struct HUDBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.corner, style: .continuous)
        // A very light dimming layer: enough to separate white text from white pages,
        // while the glass itself stays clear.
        let dim = LinearGradient(colors: [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                                 startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: [Color.white.opacity(0.70), Color.white.opacity(0.15), Color.white.opacity(0.35)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        if #available(macOS 26.0, *) {
            content
                .background(shape.fill(dim))
                .glassEffect(.clear, in: shape)
                .overlay(shape.strokeBorder(rim, lineWidth: 1))
        } else {
            content
                .background(VisualEffectBlur(material: .hudWindow).clipShape(shape))
                .overlay(shape.strokeBorder(rim, lineWidth: 1))
        }
    }
}

enum HUDPosition: String, CaseIterable, Identifiable {
    case topRight, bottomCenter
    var id: String { rawValue }
    var label: String { self == .topRight ? "右上角" : "底部居中" }
}

final class CustomHUD {
    static let shared = CustomHUD()
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(title: String, level: Double, muted: Bool, on screen: NSScreen?,
              position: HUDPosition = .topRight, duration: Double = 1.3) {
        model.title = title
        model.level = level
        model.muted = muted

        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        switch position {
        case .topRight:
            panel.setFrameOrigin(NSPoint(x: frame.maxX - HUDMetrics.width - 12, y: frame.maxY - HUDMetrics.height - 8))
        case .bottomCenter:
            panel.setFrameOrigin(NSPoint(x: frame.midX - HUDMetrics.width / 2, y: frame.minY + 110))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                if panel?.alphaValue == 0 { panel?.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.3, duration), execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: HUDMetrics.width, height: HUDMetrics.height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }
}
