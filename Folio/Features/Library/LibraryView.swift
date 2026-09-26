import SwiftData
import SwiftUI

/// Library & topics (07, Library.dc.html).
struct LibraryView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Work.addedAt) private var works: [Work]
    @Query(sort: \Topic.createdAt) private var topics: [Topic]

    @State private var addingTopic = false
    @State private var newTopic = ""
    @State private var managingUploads = false
    @State private var feedsNote = false
    @FocusState private var topicFieldFocused: Bool

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                HStack(alignment: .bottom) {
                    ScreenHeader(title: "Library", subtitle: "Everything your editions draw from.")
                    Spacer()
                    Button { OpenPanel.chooseBooks { app.importFiles($0) } } label: {
                        ButtonLabel(title: "Add a book or feed", leadingIcon: .plus, iconStroke: 1.7)
                    }
                    .buttonStyle(PrimaryButtonStyle(horizontalPadding: 18))
                }

                serials

                HStack(alignment: .top, spacing: 40) {
                    publications.frame(maxWidth: .infinity, alignment: .leading)
                    topicsSection.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 64)
            .padding(.horizontal, 64)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $managingUploads) { UploadsSheet() }
        .alert("Feeds are coming soon", isPresented: $feedsNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("For now, Folio reads EPUB and PDF files. Add one with “Add a book or feed”, or drop it on this window.")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Kicker(text: text, tracking: 0.08)
    }

    // MARK: Serials

    private var serials: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Serials in progress")
            if works.isEmpty && !app.library.isImporting {
                Text("No books yet. Add an EPUB or PDF, or drop one on this window.")
                    .uiText(14).foregroundStyle(theme.ink2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 20, alignment: .top), count: 4), alignment: .leading, spacing: 24) {
                ForEach(works) { work in tile(work) }
                if app.library.isImporting { importingTile }
            }
        }
    }

    private func tile(_ work: Work) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.tile)
        return VStack(alignment: .leading, spacing: 10) {
            Button { app.readNext(of: work) } label: {
                ZStack(alignment: .bottomLeading) {
                    theme.wash
                        .overlay { WashStack(layers: [.left(work.coverWash, -60, top: -40, 320, 228, opacity: 0.8)]) }
                        .overlay { GrainLayer(opacity: 1) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.title).displayText(21, lineHeight: 1.1).foregroundStyle(theme.ink).lineLimit(2)
                        Text(work.author).uiText(12).foregroundStyle(theme.inkOnWash).lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .frame(height: 156)
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.rule, lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .disabled(work.nextPart == nil)
            .help(work.nextPart == nil ? "Finished" : "Read the next part now")
            .contextMenu {
                Button("Read the Next Part Now") { app.readNext(of: work) }.disabled(work.nextPart == nil)
                Button("Make This the Current Serial") { app.library.setCurrent(work) }.disabled(work.isCurrent)
                Button(work.status == .paused ? "Resume" : "Pause") {
                    work.status = work.status == .paused ? .active : .paused
                    app.library.save()
                }
                .disabled(work.status == .finished)
                Divider()
                Button("Remove from Library", role: .destructive) { app.library.remove(work) }
            }

            HStack {
                Text(status(work))
                Spacer()
                Text(when(work))
            }
            .uiText(13)
            .foregroundStyle(theme.ink2)
            .lineLimit(1)
            ProgressHairline(progress: work.progress, width: nil, fill: theme.accentColor)
        }
    }

    private var importingTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: Tokens.Radius.tile)
                .fill(theme.wash)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tile).strokeBorder(theme.rule, lineWidth: 1))
                .overlay { ProgressView().controlSize(.small) }
                .frame(height: 156)
            Text("Adding…").uiText(13).foregroundStyle(theme.ink2)
        }
    }

    private func status(_ work: Work) -> String {
        if work.status == .finished || work.nextPart == nil { return "Finished" }
        if work.nextPartIndex == 0 && !work.isCurrent { return "Up next" }
        return "Part \(work.nextPartIndex + 1) of \(work.partCount)"
    }

    private func when(_ work: Work) -> String {
        if work.status == .paused { return "Paused" }
        guard work.isCurrent, work.status == .active else { return "" }
        let passageSlots = app.prefs.slots.filter { $0.content != .brief }
        guard let slot = passageSlots.first else { return "" }
        if passageSlots.count > 1 { return "Daily" }
        let part = slot.hour < 12 ? "Mornings" : slot.hour < 18 ? "Afternoons" : "Evenings"
        return slot.weekdays == ScheduleSlot.everyDay ? part : slot.daysLabel
    }

    // MARK: Publications & feeds

    private var publications: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Publications & feeds").padding(.bottom, 4)
            VStack(spacing: 0) {
                SettingRow(title: "Standard Ebooks", meta: "Public-domain classics, carefully typeset") {
                    FolioCheckbox(label: "Standard Ebooks", isOn: $app.prefs.standardEbooks)
                }
                SettingRow(title: "Project Gutenberg", meta: "Essays, letters and speeches") {
                    FolioCheckbox(label: "Project Gutenberg", isOn: $app.prefs.gutenberg)
                }
                SettingRow(title: "Your uploads", meta: "EPUB and PDF files from your Mac") {
                    linkButton("Manage") { managingUploads = true }
                }
                SettingRow(title: "RSS & newsletters", meta: "Long reads, trimmed to the best 2 pages") {
                    linkButton("Add a feed") { feedsNote = true }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).uiText(13, weight: 500).underline().foregroundStyle(theme.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: Topics

    private var topicsSection: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Topics for the Brief").padding(.bottom, 4)
            FlowLayout(spacing: 8) {
                ForEach(topics) { topic in
                    Chip(title: topic.label, isSelected: topic.isActive) {
                        topic.isActive.toggle()
                        app.scheduler.briefFailed = false
                        try? context.save()
                    }
                    .contextMenu {
                        Button("Remove Topic", role: .destructive) {
                            context.delete(topic)
                            try? context.save()
                        }
                    }
                }
                if addingTopic {
                    TextField("", text: $newTopic, prompt: Text("Your own words").foregroundStyle(theme.ink3))
                        .textFieldStyle(.plain)
                        .uiText(13)
                        .focused($topicFieldFocused)
                        .onSubmit(addTopic)
                        .padding(.horizontal, 14)
                        .frame(width: 220, height: 38)
                        .overlay(Capsule(style: .circular).strokeBorder(theme.ink, lineWidth: 1))
                        .onExitCommand { addingTopic = false; newTopic = "" }
                } else {
                    AddChip(title: "+ Add a topic") {
                        addingTopic = true
                        topicFieldFocused = true
                    }
                }
            }
            Text("Describe it in your own words, e.g. “why old maps got the world wrong”. The Brief picks one topic per edition and never repeats an angle.")
                .uiText(13, lineHeight: 1.5)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            SettingRow(title: "Surprise me once a week", meta: "A topic you didn’t pick, chosen from what you’ve enjoyed", hairline: .top) {
                FolioCheckbox(label: "Surprise me once a week", isOn: $app.prefs.surpriseWeekly)
            }
            .padding(.top, 4)
        }
    }

    private func addTopic() {
        let label = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty {
            context.insert(Topic(label: label))
            try? context.save()
            app.scheduler.briefFailed = false
        }
        newTopic = ""
        addingTopic = false
    }
}

/// "Your uploads › Manage": the imported files, with Remove. Not in the designs; kept minimal.
private struct UploadsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Work.addedAt) private var works: [Work]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your uploads").displayText(27).foregroundStyle(theme.ink)
            let uploads = works.filter { $0.source == .upload || $0.source == .sample }
            if uploads.isEmpty {
                Text("Nothing uploaded yet.").uiText(14).foregroundStyle(theme.ink2)
            }
            VStack(spacing: 0) {
                ForEach(uploads) { work in
                    SettingRow(title: work.title, meta: [work.author, work.source == .sample ? "Sample" : "\(work.partCount) parts"].filter { !$0.isEmpty }.joined(separator: " · ")) {
                        Button("Remove") { app.library.remove(work) }.buttonStyle(.quiet)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(theme.background)
    }
}
