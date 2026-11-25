import SwiftUI

/// DESIGN.md §6 switch: 63×28 track, 40×24 thumb that stretches to 46 while pressed,
/// springy travel. Intentionally not NSSwitch.
struct ClippySwitch: View {
    @Binding var isOn: Bool
    let label: String

    @ViewState private var pressed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = SettingsTheme(scheme)
        let thumbWidth: CGFloat = pressed ? 46 : 40
        let thumbX: CGFloat = isOn ? (pressed ? 15 : 21) : 2
        let travel: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.3, 1.3, 0.5, 1, duration: 0.32)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? theme.swOn : theme.swOff)
                .animation(.easeInOut(duration: 0.25), value: isOn)
            Capsule()
                .fill(Color.white)
                .shadow(color: .black(0.18), radius: 2.5, y: 2)
                .frame(width: thumbWidth, height: 24)
                .offset(x: thumbX)
                .animation(travel, value: isOn)
                .animation(travel, value: pressed)
        }
        .frame(width: 63, height: 28)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in
                    pressed = false
                    isOn.toggle()
                }
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOn.toggle() }
    }
}

/// DESIGN.md §6 segmented control.
struct SegmentedControl<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    let accessibilityLabel: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = SettingsTheme(scheme)
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? theme.segOn : Color.clear)
                                .shadow(color: selected ? .black(0.12) : .clear, radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.seg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// −/value/+ stepper with 22×22 buttons and a 64pt tabular value label.
struct StepperControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let label: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = SettingsTheme(scheme)
        HStack(spacing: 8) {
            stepButton("minus", "Decrease \(label.lowercased())", theme) {
                value = max(range.lowerBound, value - step)
            }
            .disabled(value <= range.lowerBound)
            Text("\(value) \(unit)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(theme.text)
                .frame(width: 64)
            stepButton("plus", "Increase \(label.lowercased())", theme) {
                value = min(range.upperBound, value + step)
            }
            .disabled(value >= range.upperBound)
        }
    }

    private func stepButton(_ symbol: String, _ a11y: String, _ theme: SettingsTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.btn))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.btnBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }
}

/// Default / primary / danger push buttons (DESIGN.md §6).
struct ClippyButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        ClippyButtonBody(configuration: configuration, kind: kind)
    }
}

private struct ClippyButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: ClippyButtonStyle.Kind
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let t = SettingsTheme(scheme)
            let fill: Color = kind == .primary ? t.accent : (configuration.isPressed ? t.btnActive : t.btn)
            let fg: Color = kind == .primary ? .white : (kind == .danger ? t.danger : t.text)
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(fg)
                .padding(.vertical, 3)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(kind == .primary ? t.accent : t.btnBorder, lineWidth: 1))
                .shadow(color: .black(0.06), radius: 0.5, y: 1)
                .opacity(kind == .primary && configuration.isPressed ? 0.85 : 1)
        }
}

/// Link-style action with a trailing chevron ("Open System Settings ›").
struct LinkButton: View {
    let title: String
    let action: () -> Void
    @ViewState private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title).underline(hovering)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme(scheme).link)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
