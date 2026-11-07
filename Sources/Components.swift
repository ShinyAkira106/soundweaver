// Components.swift
// Shared visual building blocks: liquid glass helpers, pill slider, cards, round buttons.

import AppKit
import SwiftUI

enum Brand {
    static let violet = Color(red: 0.45, green: 0.33, blue: 0.93)
    static let indigo = Color(red: 0.24, green: 0.20, blue: 0.62)
    static let coral = Color(red: 1.00, green: 0.48, blue: 0.40)
    static let sky = Color(red: 0.38, green: 0.77, blue: 1.00)
    static let gradient = LinearGradient(colors: [violet, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: Liquid glass with a material fallback

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool, clear: Bool) -> Glass {
    var glass: Glass = clear ? .clear : .regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    /// Liquid glass on macOS 26 and later, a frosted material before that.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil,
                                interactive: Bool = false, clear: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive, clear: clear), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.8))
        }
    }
}

/// NSVisualEffectView wrapper, used as the HUD background before macOS 26.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Small local UI state holder. Used instead of @State, which is a compiler macro in
/// newer SDKs and needs a plugin that plain swiftc builds cannot always find.
final class ViewFlags: ObservableObject {
    @Published var a = false
    @Published var b = false
}

// MARK: Pill slider

/// Control Center style slider: a glass capsule with a white fill, icon and value inside.
/// The label is drawn twice and masked, so it stays readable on both the fill and the glass,
/// and nothing ever covers the number.
struct PillSlider: View {
    let icon: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var label: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    var onCommit: (() -> Void)? = nil

    static let height: CGFloat = 26

    @Environment(\.colorScheme) var scheme
    @Environment(\.isEnabled) var isEnabled

    var trackColor: Color { scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.16) }
    var fillColor: Color { Color.white.opacity(scheme == .dark ? 0.90 : 1.0) }
    var onFillText: Color { Color.black.opacity(0.62) }
    var onGlassText: Color { scheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.62) }

    var labelView: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 15)
            Text(label(value))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 10)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let span = range.upperBound - range.lowerBound
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let fraction = CGFloat(span > 0 ? (clamped - range.lowerBound) / span : 0)
            let fillWidth = fraction <= 0 ? 0 : max(Self.height, fraction * width)

            ZStack(alignment: .leading) {
                trackColor
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth)
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 1, y: 0)
                labelView
                    .foregroundColor(onFillText)
                    .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
                labelView
                    .foregroundColor(onGlassText)
                    .mask(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: fillWidth)
                            Rectangle()
                        }
                    }
            }
            .frame(width: width, height: Self.height)
            .clipShape(Capsule())
            .glassSurface(Capsule(), interactive: true)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let f = Double(min(max(0, drag.location.x / width), 1))
                        var v = range.lowerBound + f * span
                        if let step { v = (v / step).rounded() * step }
                        value = min(max(v, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in if isEnabled { onCommit?() } }
            )
        }
        .frame(height: Self.height)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: Cards and buttons

/// Header row of a section card: icon, title, optional badge, trailing switch.
struct CardHeader: View {
    let icon: String
    let title: String
    var badge: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let badge {
                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.orange))
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .glassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ExpandChevron: View {
    @Binding var expanded: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary.opacity(0.7))
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(0.10)))
            .glassSurface(Circle(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

/// Fallback for the big call to action before macOS 26.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 200, height: 44)
            .background(Capsule().fill(Brand.gradient).opacity(configuration.isPressed ? 0.85 : 1))
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Brand.violet.opacity(0.35), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The big Rescan button: native liquid glass on macOS 26 and later.
struct GlassCallToAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 176, height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.violet)
            .controlSize(.extraLarge)
        } else {
            Button(title, action: action).buttonStyle(PrimaryButtonStyle())
        }
    }
}

struct CopyrightLine: View {
    var body: some View {
        Text("Copyright © ShinyAkira 2026")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}
