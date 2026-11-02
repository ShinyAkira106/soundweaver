// Components.swift
// Shared visual building blocks: pill slider, cards, round buttons, brand colours.

import AppKit
import SwiftUI

enum Brand {
    static let violet = Color(red: 0.45, green: 0.33, blue: 0.93)
    static let indigo = Color(red: 0.24, green: 0.20, blue: 0.62)
    static let coral = Color(red: 1.00, green: 0.48, blue: 0.40)
    static let sky = Color(red: 0.38, green: 0.77, blue: 1.00)
    static let gradient = LinearGradient(colors: [violet, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Fat capsule slider in the style of the macOS Control Center / BetterDisplay:
/// icon and value text sit inside the track, the filled part ends in a round knob.
struct PillSlider: View {
    let icon: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var label: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    var onCommit: (() -> Void)? = nil

    static let height: CGFloat = 34

    @Environment(\.colorScheme) var scheme
    @Environment(\.isEnabled) var isEnabled

    var trackColor: Color { scheme == .dark ? Color(white: 0.22) : Color(white: 0.70) }
    var fillColor: Color { scheme == .dark ? Color(white: 0.42) : .white }
    var knobColor: Color { scheme == .dark ? Color(white: 0.88) : .white }
    var textColor: Color { scheme == .dark ? Color(white: 0.90) : Color(white: 0.38) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob = Self.height - 4
            let usable = max(1, width - knob - 4)
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat(span > 0 ? (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0)
            let knobCenter = 2 + knob / 2 + fraction * usable
            let fillWidth = knobCenter + knob / 2 + 2

            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule().fill(fillColor).frame(width: fillWidth)
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 18)
                    Text(label(value))
                        .font(.system(size: 13))
                        .monospacedDigit()
                }
                .foregroundColor(textColor)
                .padding(.leading, 12)
                .allowsHitTesting(false)
                Circle()
                    .fill(knobColor)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: knobCenter - knob / 2)
            }
            .overlay(Capsule().strokeBorder(Color.black.opacity(scheme == .dark ? 0.35 : 0.10), lineWidth: 1))
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let f = Double(min(max(0, (drag.location.x - 2 - knob / 2) / usable), 1))
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

/// Header row of a section card: icon, title, optional badge, trailing switch.
struct CardHeader: View {
    let icon: String
    let title: String
    var badge: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.secondary))
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

struct ExpandChevron: View {
    @Binding var expanded: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            Image(systemName: expanded ? "chevron.compact.up" : "chevron.compact.down")
                .font(.system(size: 22, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary.opacity(0.75))
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
    }
}

/// Large gradient call to action, used on the settings home screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .regular))
            .foregroundColor(.white)
            .frame(width: 210, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Brand.gradient)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .shadow(color: Brand.violet.opacity(0.35), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Small local UI state holder. Used instead of @State, which is a compiler macro in
/// newer SDKs and needs a plugin that plain swiftc builds cannot always find.
final class ViewFlags: ObservableObject {
    @Published var a = false
    @Published var b = false
}
