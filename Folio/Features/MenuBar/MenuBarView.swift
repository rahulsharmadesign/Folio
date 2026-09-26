import SwiftData
import SwiftUI

/// Menu bar extra (11, MenuBar.dc.html), 360×460: the ready edition, the next one, pause, open, settings.
struct MenuBarView: View {
    @Environment(Theme.self) private var theme
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// The menu bar extra's own panel; `.window`-style extras don't close themselves after an action.
    @State private var panel = PanelReference()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folio").displayText(20, italic: true).foregroundStyle(theme.ink)
                Spacer()
                Text(app.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .uiText(12).foregroundStyle(theme.ink2)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)

            if app.scheduler.version >= 0, let ready = app.scheduler.readyUnread(now: app.now), let target = target(for: ready) {
                readyCard(ready, target: target)
            }
            if let next = SchedulePlanner.next(after: app.now, slots: app.prefs.slots) {
                nextCard(next)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                row(app.prefs.isPaused(at: app.now) ? "Resume editions" : "Pause editions for today") {
                    if app.prefs.isPaused(at: app.now) {
                        app.prefs.pausedUntil = nil
                    } else {
                        app.prefs.pausedUntil = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: app.now))
                    }
                }
                row("Open Folio") { open(.today) }
                row("Settings…", shortcut: "⌘ ,") {
                    panel.window?.close()
                    openSettings()
                    NSApp.activate()
                }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(theme.rule).frame(height: 1) }
        }
        .padding(16)
        .frame(width: 360, height: 460)
        .background(theme.background)
        .background(PanelReader(reference: panel))
    }

    private func target(for edition: Edition) -> ReadingTarget? {
        if let brief = edition.brief { return .brief(brief, edition) }
        if let part = edition.part { return .passage(part, edition) }
        return nil
    }

    private func readyCard(_ edition: Edition, target: ReadingTarget) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        let slot = app.prefs.slots.first { $0.id == edition.slotID }
        let title: String
        let meta: String
        switch target {
        case .passage(let part, _):
            title = part.chapterTitle.isEmpty ? (part.work?.title ?? "") : part.chapterTitle
            meta = "\(part.work?.title ?? ""), part \(part.index + 1) · \(ReadingTime.minutes(part.charCount)) min"
        case .brief(let brief, _):
            title = brief.title
            meta = "The Brief · \(ReadingTime.minutes(brief.charCount)) min"
        }
        return Button {
            panel.window?.close()
            app.read(target)
            openWindow(id: FolioApp.mainWindowID)
            NSApp.activate()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(theme.accentColor).frame(width: 6, height: 6)
                    Text("Ready · \(slot?.editionName ?? SchedulePlanner.editionName(at: edition.scheduledFor))")
                }
                .uiText(12, weight: 500)
                .foregroundStyle(theme.inkOnWash)
                Text(title).displayText(21, lineHeight: 1.2).foregroundStyle(theme.ink).multilineTextAlignment(.leading)
                Text(meta).uiText(13).foregroundStyle(theme.inkOnWash)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                theme.wash
                    .overlay { WashStack(layers: [.right("wc-lapis", -90, top: -70, 280, 200, opacity: 0.7)]) }
                    .overlay { GrainLayer(opacity: 1) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.rule, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func nextCard(_ next: SlotOccurrence) -> some View {
        let time = SchedulePlanner.timeLabel(next.date)
        let title: String
        switch next.slot.content {
        case .brief:
            let unread = try? app.library.context.fetch(FetchDescriptor<Brief>(predicate: #Predicate { $0.readAt == nil })).first
            title = "The Brief — " + (unread?.title ?? "a topic from your list")
        default:
            title = app.library.currentWork.map { w in "\(w.title), part \(w.nextPartIndex + 1)" } ?? "Your next passage"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Next · \(time), \(SchedulePlanner.inLabel(next.date, now: app.now))").uiText(12).foregroundStyle(theme.ink2)
            Text(title).displayText(17).foregroundStyle(theme.ink).lineLimit(2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.rule, lineWidth: 1))
    }

    private func open(_ route: Route) {
        panel.window?.close()
        app.route = route
        openWindow(id: FolioApp.mainWindowID)
        NSApp.activate()
    }

    private func row(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).uiText(14).foregroundStyle(theme.ink)
                Spacer()
                if let shortcut { Text(shortcut).uiText(12).foregroundStyle(theme.ink2) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class PanelReference {
    weak var window: NSWindow?
}

/// Captures the window hosting the menu bar extra's content.
private struct PanelReader: NSViewRepresentable {
    let reference: PanelReference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in reference.window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window { reference.window = window }
    }
}

/// The book icon from the sidebar, as a template image for the status item.
@MainActor
enum MenuBarIcon {
    /// `dot`: an edition is ready and unread (the only "badge" Folio has, and only in the menu bar).
    static func make(dot: Bool = false) -> NSImage {
        let renderer = ImageRenderer(content: IconView(icon: .library, size: 18, strokeWidth: 1.5)
            .overlay(alignment: .topTrailing) { if dot { Circle().frame(width: 6, height: 6).offset(x: 2, y: -1) } })
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
