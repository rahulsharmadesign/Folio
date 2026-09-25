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
                .background(isSelected ? theme.primaryBackground : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? theme.primaryBackground : theme.control, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                .overlay(Capsule().strokeBorder(Self.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Sunken track with a raised selected tab (Schedule cadence: 36 pt / 14 pt; Notebook filters: 32 pt / 13 pt).
struct SegmentedTabs<ID: Hashable>: View {
    @Environment(Theme.self) private var theme
    let options: [ID]
    @Binding var selection: ID
    let title: (ID) -> String
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 16
    var fontSize: CGFloat = 14

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
        .overlay(alignment: .bottom) { Rectangle().fill(theme.rule).frame(height: 1) }
    }
}

/// The 18 pt accent checkbox the source uses for on/off rows.
struct FolioCheckbox: View {
    @Environment(Theme.self) private var theme
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(.large)
            .tint(theme.accentColor)
    }
}

/// 2 pt hairline progress: 140 wide in the reader (ink2 on rule), full width in Library (accent on rule).
struct ProgressHairline: View {
    @Environment(Theme.self) private var theme
    var progress: Double
    var width: CGFloat? = 140
    var fill: Color?

    var body: some View {
        Capsule()
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
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}
