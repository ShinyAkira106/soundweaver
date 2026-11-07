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
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Template symbol sized to match neighbouring menu bar icons.
enum MenuBarIcon {
    static let image: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Soundweaver")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }()
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
        VStack(alignment: .leading, spacing: 7) {
            // Master
            CardHeader(icon: "waveform", title: "Soundweaver", isOn: $c.enabled)
            PillSlider(icon: c.menuIcon, value: $c.master)
                .padding(.horizontal, 6)
                .disabled(!c.enabled)

            // Monitor
            CardHeader(icon: "display", title: c.monitorTitle,
                       badge: c.ddcConnected ? nil : "!", isOn: monitorOn)
                .padding(.top, 3)
                .disabled(!c.enabled)
            Group {
                PillSlider(icon: "hifispeaker", value: $c.monitorLevel)
                if flags.a {
                    PillSlider(icon: "gauge.with.dots.needle.67percent", value: $c.monitorCap,
                               range: 0.1...1, step: 0.05,
                               label: { "上限 \(Int(($0 * 100).rounded()))%" })
                    Text(c.ddcStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 6)
            .disabled(!c.enabled)
            ExpandChevron(expanded: $flags.a)

            // MacBook
            CardHeader(icon: "laptopcomputer", title: c.macTitle, isOn: macIncluded)
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
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 6)
            .disabled(!c.enabled)
            ExpandChevron(expanded: $flags.b)

            if !c.accessibilityGranted {
                Button {
                    c.openAccessibilitySettings()
                } label: {
                    Label("需要辅助功能权限才能接管音量键", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.link)
                .padding(.horizontal, 6)
            }

            UpdateBanner(updater: c.updater)

            // Footer
            HStack(spacing: 6) {
                Text(c.routeStatus)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button {
                    SettingsWindow.shared.show(controller: c)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(GlassIconButtonStyle())
                .help("设置")

                Menu {
                    Button("重新检测设备") { c.rescan() }
                    Button("预览提示框") { c.showHUD() }
                    Button("检查更新…") {
                        c.updater.check()
                        SettingsWindow.shared.show(controller: c, page: .about)
                    }
                    Divider()
                    Button("关于 Soundweaver") { SettingsWindow.shared.show(controller: c, page: .about) }
                    Button("退出 Soundweaver") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.10)))
                        .glassSurface(Circle(), interactive: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 6)

            CopyrightLine()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 1)
        }
        .padding(8)
        .frame(width: 268)
    }
}

/// Shown in the panel only when GitHub has a newer release.
struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        if let version = updater.availableVersion {
            Button {
                updater.openReleasePage()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(Brand.violet)
                    Text("新版本 v\(version) 可以下载")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Rectangle())
                .glassSurface(Capsule(), tint: Brand.violet.opacity(0.12), interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
    }
}
