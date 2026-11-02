// App.swift
// Menu bar entry and the popover panel.

import AppKit
import SwiftUI

@main
struct SoundweaverApp: App {
    @StateObject private var controller = Controller()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel().environmentObject(controller)
        } label: {
            Image(systemName: controller.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @EnvironmentObject var c: Controller
    @StateObject private var flags = ViewFlags()   // a: monitor expanded, b: MacBook expanded

    /// The MacBook card's switch decides between combined and monitor only.
    private var macIncluded: Binding<Bool> {
        Binding(get: { c.mode == .combined },
                set: { c.mode = $0 ? .combined : .monitorOnly })
    }

    /// The monitor card's switch mutes just the monitor.
    private var monitorOn: Binding<Bool> {
        Binding(get: { !c.monitorMuted }, set: { c.monitorMuted = !$0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Master
            CardHeader(icon: "waveform", title: "Soundweaver", isOn: $c.enabled)
            PillSlider(icon: c.menuIcon, value: $c.master)
                .padding(.horizontal, 8)
                .disabled(!c.enabled)

            // Monitor
            CardHeader(icon: "display", title: c.monitorDevice?.name ?? "显示器",
                       badge: c.ddcConnected ? nil : "!", isOn: monitorOn)
                .padding(.top, 4)
                .disabled(!c.enabled)
            Group {
                PillSlider(icon: "hifispeaker", value: $c.monitorLevel)
                if flags.a {
                    PillSlider(icon: "speaker.badge.exclamationmark", value: $c.monitorCap,
                               range: 0.1...1, step: 0.05,
                               label: { "上限 \(Int(($0 * 100).rounded()))%" })
                    Text(c.ddcStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 8)
            .disabled(!c.enabled)
            ExpandChevron(expanded: $flags.a)

            // MacBook
            CardHeader(icon: "laptopcomputer", title: c.macDevice?.name ?? "MacBook 扬声器", isOn: macIncluded)
                .disabled(!c.enabled)
            Group {
                PillSlider(icon: "speaker.wave.2", value: $c.macLevel)
                    .disabled(c.mode != .combined)
                if flags.b {
                    PillSlider(icon: "timer", value: $c.syncOffsetMs, range: -200...200, step: 5,
                               label: { "同步 \(Int($0)) ms" },
                               onCommit: { c.reapplyRouting() })
                        .disabled(c.mode != .combined)
                    Text("正值让 MacBook 晚一点出声，负值让显示器晚一点出声")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 8)
            .disabled(!c.enabled)
            ExpandChevron(expanded: $flags.b)

            if !c.accessibilityGranted {
                Button {
                    c.openAccessibilitySettings()
                } label: {
                    Label("需要辅助功能权限才能接管音量键", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .padding(.horizontal, 8)
            }

            // Footer
            HStack(spacing: 8) {
                Text(c.routeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button {
                    SettingsWindow.shared.show(controller: c)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(RoundIconButtonStyle())
                .help("设置")

                Menu {
                    Button("重新检测设备") { c.rescan() }
                    Button("预览提示框") { c.showHUD() }
                    Divider()
                    Button("关于 Soundweaver") { SettingsWindow.shared.show(controller: c, page: .about) }
                    Button("退出 Soundweaver") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 320)
    }
}
