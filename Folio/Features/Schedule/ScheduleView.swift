import SwiftData
import SwiftUI

/// Schedule (09, Schedule.dc.html): cadence, delivery rows, edition length, the rules and "Your day".
struct ScheduleView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: "Schedule", subtitle: "When Briefs arrive, what kind, and how long they are.")
                ScheduleEditor()
                LengthSection()
                RulesSection()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            YourDay()
                .frame(width: 260)
        }
        .padding(.top, 64)
        .padding(.leading, 64)
        .padding(.trailing, 56)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Cadence tabs and the delivery rows (reused by onboarding step 2).
struct ScheduleEditor: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 26) {
            SegmentedTabs(options: Cadence.allCases, selection: Binding(get: { app.prefs.cadence }, set: setCadence)) { $0.title }
            VStack(spacing: 0) {
                ForEach($app.prefs.slots) { $slot in
                    SlotRow(slot: $slot, canRemove: app.prefs.cadence == .custom && app.prefs.slots.count > 1) {
                        app.prefs.slots.removeAll { $0.id == slot.id }
                    }
                }
                if app.prefs.cadence == .custom, app.prefs.slots.count < 5 {
                    // Not in the designs: a quiet way to add a delivery in Custom.
                    Button {
                        let last = app.prefs.slots.last?.hour ?? 12
                        app.prefs.slots.append(ScheduleSlot(id: "custom-\(UUID().uuidString.prefix(6))", hour: min(23, last + 2), minute: 0,
                                                            content: .mix, weekdays: ScheduleSlot.everyDay))
                    } label: {
                        Text("+ Add a delivery").uiText(13).foregroundStyle(theme.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
        }
    }

    private func setCadence(_ cadence: Cadence) {
        guard cadence != app.prefs.cadence else { return }
        app.prefs.cadence = cadence
        app.prefs.slots = ScheduleSlot.defaults(for: cadence)
    }
}

private struct SlotRow: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Query(sort: \NewsFeed.createdAt) private var feeds: [NewsFeed]
    @Query(sort: \FavoriteQuote.createdAt) private var quotes: [FavoriteQuote]
    @Binding var slot: ScheduleSlot
    var canRemove: Bool
    var remove: () -> Void
    @State private var editingTime = false

    var body: some View {
        HStack(spacing: 16) {
            Button { editingTime = true } label: {
                Text(slot.time).displayText(19).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.control, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delivery time \(slot.time)")
            .popover(isPresented: $editingTime, arrowEdge: .bottom) {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .padding(16)
            }
            .frame(width: 120, alignment: .leading)

            Menu {
                ForEach(SlotContent.allCases, id: \.self) { content in
                    Button(content.title) { slot.content = content }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.content.title).uiText(14, weight: 500).foregroundStyle(theme.ink)
                    Text(detail).uiText(13).foregroundStyle(theme.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Menu {
                Button("Every day") { slot.weekdays = ScheduleSlot.everyDay }
                Button("Weekdays") { slot.weekdays = ScheduleSlot.weekdaysOnly }
                Button("Weekends") { slot.weekdays = ScheduleSlot.weekends }
                Divider()
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(
                        get: { slot.weekdays.contains(day) },
                        set: { on in
                            if on { slot.weekdays.insert(day) } else if slot.weekdays.count > 1 { slot.weekdays.remove(day) }
                        }))
                }
                if canRemove {
                    Divider()
                    Button("Remove This Delivery", role: .destructive, action: remove)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(slot.daysLabel).uiText(13)
                    IconView(icon: .chevronDown, size: 14, strokeWidth: 1.8)
                }
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 160, alignment: .trailing)
        }
        .frame(minHeight: 62)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.rule).frame(height: 1) }
    }

    private var detail: String {
        switch slot.content {
        case .mix: "A story, a quote, the news or a topic — a different one each day"
        case .story: "A real person or moment, from Wikipedia"
        case .quote:
            quotes.contains { $0.explainedAt == nil } ? "The next of your favourite quotes, explained" : "A well-known quote, explained"
        case .news: "The day’s most significant stories from \(feeds.count) feed\(feeds.count == 1 ? "" : "s"), linked"
        case .topic: "A topic from your list, with sources"
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: .now) ?? .now },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                slot.hour = c.hour ?? slot.hour
                slot.minute = c.minute ?? slot.minute
            })
    }
}

private struct LengthSection: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @State private var draft: Double?

    var body: some View {
        let value = draft ?? Double(app.prefs.editionLimit)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Edition length").uiText(14, weight: 500).foregroundStyle(theme.ink)
                Spacer()
                Text(ReadingTime.lengthLabel(Int(value))).uiText(13).foregroundStyle(theme.ink2)
            }
            FolioSlider(value: Binding(get: { value }, set: { draft = $0 }),
                        range: Double(Chunker.limitRange.lowerBound)...Double(Chunker.limitRange.upperBound), step: 100) { editing in
                if !editing, let draft {
                    let limit = Int(draft)
                    self.draft = nil
                    guard limit != app.prefs.editionLimit else { return }
                    app.prefs.editionLimit = limit
                }
            }
            .accessibilityLabel("Edition length")
            HStack {
                Text("Half a page")
                Spacer()
                Text("Two pages")
            }
            .uiText(12)
            .foregroundStyle(theme.ink3)
        }
    }
}

private struct RulesSection: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            SettingRow(title: "Editions never pile up", meta: "Miss one and the next simply takes its place — no backlog") {
                FolioCheckbox(label: "Editions never pile up", isOn: $app.prefs.neverPileUp)
            }
            SettingRow(title: "Quiet arrival", meta: "Show in the menu bar only; no banner or sound") {
                FolioCheckbox(label: "Quiet arrival", isOn: Binding(get: { app.prefs.quietArrival }, set: { quiet in
                    app.prefs.quietArrival = quiet
                    if !quiet { app.scheduler.requestNotificationPermission() }
                }))
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
    }
}

/// "Your day": a 24-hour line with a watercolour mark at each delivery.
private struct YourDay: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "Your day", tracking: 0.08)
            ZStack(alignment: .topLeading) {
                theme.wash
                GrainLayer(opacity: 1)
                Rectangle().fill(RGBA(0xCFC4AE).color).frame(width: 1, height: 512).offset(x: 56, y: 24)
                Group {
                    Text("00:00").offset(x: 16, y: 16)
                    Text("12:00").offset(x: 16, y: 268)
                    Text("24:00").offset(x: 16, y: 560 - 16 - 13)
                }
                .uiText(11)
                .foregroundStyle(theme.ink2)
                ForEach(app.prefs.slots) { slot in
                    let h = Double(slot.hour) + Double(slot.minute) / 60
                    HStack(spacing: 12) {
                        Image(wash(for: slot.content))
                            .resizable()
                            .frame(width: 84, height: 60)
                            .opacity(0.95)
                            .blendMode(.multiply)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.time).displayText(17).foregroundStyle(theme.ink)
                            Text(slot.content.title).uiText(12).foregroundStyle(theme.inkOnWash)
                        }
                    }
                    .offset(x: 36, y: 24 + h / 24 * 512 - 20)
                }
            }
            .frame(height: 560)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(theme.rule, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
        .padding(.top, 8)
    }

    private func wash(for content: SlotContent) -> String {
        switch content {
        case .mix: "wc-lapis"
        case .story: "wc-rose"
        case .quote: "wc-plum"
        case .news: "wc-sage"
        case .topic: "wc-ochre"
        }
    }
}
