import SwiftUI

/// Uppercase label: 12/500, tracking 0.06em, ink2 (tokens: kicker).
/// Section headings in Library and Schedule use tracking 0.08; the sidebar card uses 11 pt.
struct Kicker: View {
    let text: String
    var size: CGFloat = Tokens.kicker.size
    var tracking: CGFloat = Tokens.kicker.tracking
    var color: InkRole = .ink2

    var body: some View {
        Text(text)
            .textStyle(Tokens.kicker.with(size: size, tracking: tracking, color: color))
            .lineLimit(1)
    }
}

/// Pill toggle (Library topics): 38 pt, 13 pt; selected = ink fill.
struct Chip: View {
    @Environment(Theme.self) private var theme
    let title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .uiText(13)
                .foregroundStyle(isSelected ? theme.primaryForeground : theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(isSelected ? theme.primaryBackground : .clear, in: Capsule(style: .circular))
                .overlay { if !isSelected { Capsule(style: .circular).strokeBorder(theme.control, lineWidth: 1) } }
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The dashed "+ Add a topic" pill (Library.dc.html: 1 px dashed #B9AE9A).
struct AddChip: View {
    @Environment(Theme.self) private var theme
    let title: String
    var action: () -> Void

    /// Stated only in Library.dc.html; not a token.
    private static let dash = RGBA(0xB9AE9A).color

    var body: some View {
        Button(action: action) {
            Text(title)
                .uiText(13)
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(Capsule(style: .circular).strokeBorder(Self.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
    }
}

/// Sunken track with a raised selected tab (Schedule cadence: 36 pt / 14 pt; Notebook filters: 32 pt / 13 pt).
struct SegmentedTabs<ID: Hashable>: View {
    @Environment(Theme.self) private var theme
    let options: [ID]
    @Binding var selection: ID
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 16
    var fontSize: CGFloat = 14
    let title: (ID) -> String

    /// `0 1px 2px rgba(60,48,30,0.12)` from the source.
    private static var raisedShadow: Color { RGBA(0x3C301E, 0.12).color }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .uiText(fontSize, weight: 500)
                        .foregroundStyle(selected ? theme.ink : theme.ink2)
                        .padding(.horizontal, horizontalPadding)
                        .frame(height: height)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(theme.surface)
                                    .shadow(color: Self.raisedShadow, radius: 1, y: 1)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(theme.sidebar, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
    }
}

/// 54 pt row: title (14/500) and meta (13, ink2) with a trailing control, hairline below.
struct SettingRow<Trailing: View>: View {
    @Environment(Theme.self) private var theme
    let title: String
    var meta: String?
    /// Which edge carries the hairline (Library's "Surprise me" row has it on top).
    var hairline: VerticalEdge = .bottom
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).uiText(14, weight: 500).foregroundStyle(theme.ink)
                if let meta { Text(meta).uiText(13).foregroundStyle(theme.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: Tokens.Spacing.rowMinHeight)
        .overlay(alignment: hairline == .bottom ? .bottom : .top) { Rectangle().fill(theme.rule).frame(height: 1) }
    }
}

/// The 18 pt accent checkbox the source uses for on/off rows (`accent-color` on a native checkbox):
/// filled accent with a white tick when on, a hairline box when off.
struct FolioCheckbox: View {
    @Environment(Theme.self) private var theme
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(isOn ? theme.accentColor : theme.surface)
                .overlay {
                    if isOn {
                        IconView(icon: .check, size: 14, strokeWidth: 3).foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 3.5).strokeBorder(theme.ink3, lineWidth: 1)
                    }
                }
                .frame(width: 18, height: 18)
                // A 44 pt hit target that lays out at 18 pt, like the source.
                .padding(13)
                .contentShape(Rectangle())
                .padding(-13)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 2 pt hairline progress: 140 wide in the reader (ink2 on rule), full width in Library (accent on rule).
struct ProgressHairline: View {
    @Environment(Theme.self) private var theme
    var progress: Double
    var width: CGFloat? = 140
    var fill: Color?

    var body: some View {
        Capsule(style: .circular)
            .fill(theme.rule)
            .frame(width: width, height: 2)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(fill ?? theme.ink2)
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 2)
                }
            }
            .clipShape(Capsule(style: .circular))
            .accessibilityElement()
            .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

/// Range input in the style of the source's `accent-color` slider: a filled accent track and a round knob.
struct FolioSlider: View {
    @Environment(Theme.self) private var theme
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false

    private let knob: CGFloat = 16
    private let track: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let span = max(1, geo.size.width - knob)
            let fraction = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
            let x = CGFloat(fraction) * span
            ZStack(alignment: .leading) {
                Capsule(style: .circular).fill(theme.controlSoft).frame(height: track)
                Capsule(style: .circular).fill(theme.accentColor).frame(width: x + knob / 2, height: track)
                Circle().fill(theme.accentColor)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    set(from: g.location.x - knob / 2, span: span)
                }
                .onEnded { _ in
                    dragging = false
                    onEditingChanged(false)
                })
        }
        .frame(height: 24)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { editing in onEditingChanged(editing) }
        }
    }

    private func set(from x: CGFloat, span: CGFloat) {
        let raw = range.lowerBound + Double(min(max(0, x / span), 1)) * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        if stepped != value { value = min(max(stepped, range.lowerBound), range.upperBound) }
    }
}
