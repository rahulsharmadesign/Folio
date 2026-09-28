import SwiftData
import SwiftUI

/// Library & topics (07, Library.dc.html).
struct LibraryView: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Work.addedAt) private var works: [Work]
    @Query(sort: \Topic.createdAt) private var topics: [Topic]
    @Query(sort: \NewsFeed.createdAt) private var feeds: [NewsFeed]
    @Query(sort: \FavoriteQuote.createdAt) private var quotes: [FavoriteQuote]

    @State private var addingTopic = false
    @State private var newTopic = ""
    @State private var managingUploads = false
    @State private var managingFeeds = false
    @State private var managingQuotes = false
    @FocusState private var topicFieldFocused: Bool

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                HStack(alignment: .bottom) {
                    ScreenHeader(title: "Library", subtitle: "Your books, and everything your Briefs draw from.")
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
        .sheet(isPresented: $managingFeeds) { FeedsSheet() }
        .sheet(isPresented: $managingQuotes) { QuotesSheet() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Kicker(text: text, tracking: 0.08)
    }

    // MARK: Serials

    private var serials: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Your books")
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
            Button { work.isFinished ? app.startOver(work) : app.readBook(work) } label: {
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
            .help(work.isFinished ? "Read it again from the beginning" : work.nextPartIndex == 0 ? "Start reading" : "Continue where you stopped")
            .contextMenu {
                Button(work.nextPartIndex == 0 ? "Start Reading" : "Continue Reading") { app.readBook(work) }.disabled(work.isFinished)
                Button("Start Over") { app.startOver(work) }.disabled(work.nextPartIndex == 0)
                Divider()
                Button("Remove from Library", role: .destructive) { app.library.remove(work) }
            }

            HStack {
                Text(work.progressLabel)
                Spacer()
                Text(chapter(work))
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

    /// Where the reader is: the chapter they stopped in.
    private func chapter(_ work: Work) -> String {
        guard !work.isFinished, work.nextPartIndex > 0, let title = work.nextPart?.chapterTitle else { return "" }
        return title
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
                SettingRow(title: "Tech news feeds", meta: feeds.isEmpty ? "RSS or Atom; the Tech news Brief reads them" : "\(feeds.count) feed\(feeds.count == 1 ? "" : "s") for the Tech news Brief") {
                    linkButton("Manage") { managingFeeds = true }
                }
                SettingRow(title: "Favourite quotes", meta: quotesMeta) {
                    linkButton("Manage") { managingQuotes = true }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
        }
    }

    private var quotesMeta: String {
        let waiting = quotes.filter { $0.explainedAt == nil }.count
        return quotes.isEmpty ? "Your own, explained one at a time" : "\(waiting) waiting to be explained"
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
                        app.scheduler.retryBriefs()
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
            app.scheduler.retryBriefs()
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

/// "Tech news feeds › Manage": the feeds the Tech news Brief reads. Not in the designs; kept minimal like Uploads.
private struct FeedsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \NewsFeed.createdAt) private var feeds: [NewsFeed]
    @State private var url = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tech news feeds").displayText(27).foregroundStyle(theme.ink)
            Text("The Tech news Brief picks the most significant recent stories from these, and links each one.")
                .uiText(13, lineHeight: 1.5).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(feeds) { feed in
                        SettingRow(title: feed.title, meta: URL(string: feed.url)?.host() ?? feed.url) {
                            Button("Remove") {
                                context.delete(feed)
                                try? context.save()
                            }
                            .buttonStyle(.quiet)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            HStack(spacing: 8) {
                TextField("", text: $url, prompt: Text("Feed address, e.g. https://example.com/feed").foregroundStyle(theme.ink3))
                    .textFieldStyle(.plain)
                    .uiText(13)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.control, lineWidth: 1))
                    .onSubmit(add)
                Button(checking ? "Checking…" : "Add", action: add)
                    .buttonStyle(SecondaryButtonStyle(height: 40, horizontalPadding: 14, fontSize: 13, weight: 400))
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem { Text(problem).uiText(13).foregroundStyle(theme.ink2) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(theme.background)
    }

    /// Fetches the feed once, so only a feed Folio can read is added, under its own title.
    private func add() {
        var address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !checking else { return }
        if !address.contains("://") { address = "https://" + address }
        checking = true
        problem = nil
        Task {
            defer { checking = false }
            guard let feed = try? await FeedRetrieval.fetch(address), !feed.items.isEmpty else {
                problem = "Folio couldn’t read a feed at that address. Check it’s an RSS or Atom feed."
                return
            }
            guard !feeds.contains(where: { $0.url == address }) else { url = ""; return }
            context.insert(NewsFeed(url: address, title: feed.title.isEmpty ? (URL(string: address)?.host() ?? address) : feed.title))
            try? context.save()
            app.scheduler.retryBriefs()
            url = ""
        }
    }
}

/// "Favourite quotes › Manage": quotes the quote Brief explains, oldest first. Not in the designs; kept minimal.
private struct QuotesSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FavoriteQuote.createdAt) private var quotes: [FavoriteQuote]
    @State private var text = ""
    @State private var author = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Favourite quotes").displayText(27).foregroundStyle(theme.ink)
            Text("Each quote Brief explains the next one here: who said it, where, and what it means. When they’re all explained, Folio picks well-known ones.")
                .uiText(13, lineHeight: 1.5).foregroundStyle(theme.ink2).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(quotes) { quote in
                        SettingRow(title: "“\(quote.text)”", meta: meta(quote)) {
                            Button("Remove") {
                                context.delete(quote)
                                try? context.save()
                            }
                            .buttonStyle(.quiet)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            VStack(spacing: 8) {
                field("The quote", text: $text)
                HStack(spacing: 8) {
                    field("Who said it (optional)", text: $author)
                    Button("Add", action: add)
                        .buttonStyle(SecondaryButtonStyle(height: 40, horizontalPadding: 14, fontSize: 13, weight: 400))
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(height: 40, horizontalPadding: 16, fontSize: 13))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(theme.background)
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(theme.ink3))
            .textFieldStyle(.plain)
            .uiText(13)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.control, lineWidth: 1))
            .onSubmit(add)
    }

    private func meta(_ quote: FavoriteQuote) -> String {
        let status = quote.unsourced ? "No source found" : quote.explainedAt != nil ? "Explained" : "Waiting"
        return [quote.author, status].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func add() {
        let quote = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard !quote.isEmpty else { return }
        context.insert(FavoriteQuote(text: quote, author: author.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? context.save()
        app.scheduler.retryBriefs()
        text = ""
        author = ""
    }
}
