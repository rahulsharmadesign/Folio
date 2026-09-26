import SwiftData
import SwiftUI

/// Welcome (01, Onboarding.dc.html), three steps: what editions hold, when they arrive, and Brief topics.
/// Steps 2 and 3 reuse the Schedule and Library components.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Topic.createdAt) private var topics: [Topic]

    @State private var step = 0
    @State private var newTopic = ""
    @FocusState private var topicFocused: Bool

    /// Option-card border and unchecked box, stated in the source.
    private static let optionBorder = RGBA(0xE0D6C3).color
    private static let boxBorder = RGBA(0xB9AE9A).color

    var body: some View {
        HStack(spacing: 0) {
            welcomePanel.frame(width: 560)
            VStack(alignment: .leading, spacing: 28) {
                switch step {
                case 0: contentStep
                case 1: scheduleStep
                default: topicsStep
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, 96)
            .padding(.horizontal, 88)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(theme.background)
        .ignoresSafeArea()
    }

    private var welcomePanel: some View {
        ZStack(alignment: .topLeading) {
            theme.wash
            WashStack(layers: [
                .left("wc-lapis", -140, top: 60, 720, 512, opacity: 0.75),
                .left("wc-sage", 150, top: 300, 560, 398, opacity: 0.6),
                .left("wc-ochre", -60, top: 470, 460, 327, opacity: 0.5),
            ])
            GrainLayer(opacity: 1)
            VStack(alignment: .leading, spacing: 18) {
                Text("Folio").textStyle(Tokens.wordmarkHero.with(lineHeight: 1)).foregroundStyle(theme.ink)
                CSSText("A page or two of something worth your attention. Twice a day. Nothing to scroll.",
                        style: TypeStyle(role: .display, size: 26, lineHeight: 1.25, tracking: -0.01))
            }
            .frame(width: 420, alignment: .leading)
            .offset(x: 64, y: 96)
        }
        .clipped()
        .overlay(alignment: .trailing) { Rectangle().fill(theme.rule).frame(width: 1) }
    }

    private func heading(_ step: Int, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: "Step \(step) of 3", tracking: 0.08)
            Text(title).textStyle(TypeStyle(role: .display, size: 38, lineHeight: 1.1, tracking: -0.015)).foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).uiText(15, lineHeight: 1.5).foregroundStyle(theme.ink2)
        }
    }

    // MARK: Step 1

    private var contentStep: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 28) {
            heading(1, "What should your editions hold?", "Pick any. You can change the mix at any time.")
            VStack(spacing: 12) {
                option("Great books, one piece at a time",
                       "Classics serialised into short parts that end at natural breaks, with a one-line recap each time.",
                       isOn: $app.prefs.wantsBooks)
                option("Essays & publications",
                       "Your EPUBs, newsletters and RSS feeds, trimmed to the part worth reading.",
                       isOn: $app.prefs.wantsPublications)
                option("The Brief",
                       "An AI-written summary of a topic you care about, with its sources listed underneath.",
                       isOn: $app.prefs.wantsBrief)
            }
        }
    }

    private func option(_ title: String, _ body: String, isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        let shape = RoundedRectangle(cornerRadius: 14)
        return Button { isOn.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(on ? theme.primaryBackground : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? theme.primaryBackground : Self.boxBorder, lineWidth: 1.5))
                    .overlay { if on { IconView(icon: .check, size: 12, strokeWidth: 3).foregroundStyle(theme.primaryForeground) } }
                    .frame(width: 20, height: 20)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).displayText(21, lineHeight: 1.2).foregroundStyle(theme.ink)
                    Text(body).uiText(14, lineHeight: 1.45).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(on ? theme.surface : .clear, in: shape)
            .overlay(shape.strokeBorder(on ? theme.ink : Self.optionBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Step 2

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading(2, "When should editions arrive?", "Choose a rhythm. You can fine-tune it later in Schedule.")
            ScheduleEditor()
        }
    }

    // MARK: Step 3

    private var topicsStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading(3, "What should the Brief cover?", "Describe a few topics in your own words. The Brief picks one per edition, with sources.")
            FlowLayout(spacing: 8) {
                ForEach(topics) { topic in
                    Chip(title: topic.label, isSelected: topic.isActive) {
                        topic.isActive.toggle()
                        try? context.save()
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $newTopic, prompt: Text("e.g. why old maps got the world wrong").foregroundStyle(theme.ink3))
                    .textFieldStyle(.plain)
                    .uiText(14)
                    .focused($topicFocused)
                    .onSubmit(addTopic)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(theme.background, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(theme.controlSoft, lineWidth: 1))
                Button("Add", action: addTopic).buttonStyle(SecondaryButtonStyle(height: 42, horizontalPadding: 16, fontSize: 13))
            }
            if !app.ai.isEnabled(.brief) {
                Text("The Brief is written by AI. Turn it on in Folio › Settings › AI — Apple’s on-device model and Ollama keep everything on this Mac.")
                    .uiText(13, lineHeight: 1.5).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addTopic() {
        let label = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        context.insert(Topic(label: label))
        try? context.save()
        newTopic = ""
        topicFocused = true
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule(style: .circular).fill(i == step ? theme.ink : theme.control).frame(width: i == step ? 22 : 8, height: 4)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.quiet)
            }
            Button {
                if step < 2 { step += 1 } else { finish() }
            } label: {
                ButtonLabel(title: step < 2 ? "Continue" : "Start reading", trailingIcon: .arrowRight)
            }
            .buttonStyle(PrimaryButtonStyle(horizontalPadding: 22))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func finish() {
        app.prefs.onboarded = true
        if !app.prefs.quietArrival { app.scheduler.requestNotificationPermission() }
        app.scheduler.refresh(prefs: app.prefs, now: app.now)
        app.route = .today
    }
}
