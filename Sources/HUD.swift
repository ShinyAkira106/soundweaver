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

final class HUDModel: ObservableObject {
    @Published var title = ""
    @Published var level = 0.0
    @Published var muted = false
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            HStack(spacing: 10) {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.fill")
                    .foregroundColor(.white)
                    .frame(width: 16)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white)
                            .frame(width: max(0, geo.size.width * (model.muted ? 0 : model.level)))
                    }
                }
                .frame(height: 6)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300, height: 72)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.82)))
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
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 300 - 14, y: frame.maxY - 72 - 10))
        case .bottomCenter:
            panel.setFrameOrigin(NSPoint(x: frame.midX - 150, y: frame.minY + 110))
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }
}
