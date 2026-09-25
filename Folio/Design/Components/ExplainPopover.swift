import SwiftUI

enum ExplainMode: String, CaseIterable, Identifiable, Sendable {
    case explain, define, context, simpler

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The Explain popover (ReaderTools.dc.html): mode tabs, a short answer, an Ask field and Save note.
/// It only draws; the reader (M3) feeds it text from an `AIProvider`.
struct ExplainPopover: View {
    @Environment(Theme.self) private var theme
    @Binding var mode: ExplainMode
    var answer: String
    var footnote: String?
    @Binding var question: String
    /// Where the arrow sits, from the popover's leading edge (source: 212 + 6).
    var arrowX: CGFloat = 218
    var onAsk: () -> Void = {}
    var onSaveNote: () -> Void = {}

    // Values stated only in ReaderTools.dc.html; not tokens.
    private static let selectedTab = RGBA(0xE9E1D1).color
    private static let divider = RGBA(0xECE4D5).color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.popover)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(ExplainMode.allCases) { m in
                    let selected = m == mode
                    Button { mode = m } label: {
                        Text(m.title)
                            .uiText(13, weight: selected ? 500 : 400)
                            .foregroundStyle(selected ? theme.ink : theme.ink2)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(selected ? Self.selectedTab : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding([.top, .horizontal], 10)

            VStack(alignment: .leading, spacing: 10) {
                Text(answer)
                    .readingText(16, lineHeight: 1.6)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .uiText(13, lineHeight: 1.5)
                        .foregroundStyle(theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                TextField("Ask about this passage…", text: $question)
                    .textFieldStyle(.plain)
                    .uiText(14)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(theme.controlSoft, lineWidth: 1))
                    .accessibilityLabel("Ask about this passage")
                    .onSubmit(onAsk)
                Button(action: onSaveNote) {
                    HStack(spacing: 6) {
                        IconView(icon: .bookmark, size: 15, strokeWidth: 1.6)
                        Text("Save note")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 40, horizontalPadding: 14, fontSize: 13))
            }
            .padding(.vertical, 12)
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .overlay(alignment: .top) { Rectangle().fill(Self.divider).frame(height: 1) }
            .padding(.top, 10)
        }
        .frame(width: 500)
        .background(theme.surface, in: shape)
        .overlay(shape.strokeBorder(theme.controlSoft, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            // The arrow: a 12 pt square rotated 45°, with only its top-left borders drawn.
            ZStack {
                Rectangle().fill(theme.surface)
                Path { p in
                    p.move(to: CGPoint(x: 0.5, y: 12))
                    p.addLine(to: CGPoint(x: 0.5, y: 0.5))
                    p.addLine(to: CGPoint(x: 12, y: 0.5))
                }
                .stroke(theme.controlSoft, lineWidth: 1)
            }
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(45))
            .offset(x: arrowX - 6, y: -7)
        }
        // 0 1px 2px rgba(60,48,30,0.06), 0 18px 48px -12px rgba(60,48,30,0.22)
        .shadow(color: RGBA(0x3C301E, 0.06).color, radius: 1, y: 1)
        .shadow(color: RGBA(0x3C301E, 0.22).color, radius: 18, y: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Explain selection")
    }
}
