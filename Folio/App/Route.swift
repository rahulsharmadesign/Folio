import Foundation

/// Every screen in DESIGN.md's inventory. The first five live beside the sidebar.
enum Route: String, CaseIterable, Hashable, Sendable {
    case today, library, notebook, schedule, appearance
    case reader, brief, editionEnd, onboarding

    static let sidebar: [Route] = [.today, .library, .notebook, .schedule, .appearance]

    var showsSidebar: Bool { Route.sidebar.contains(self) }

    var title: String {
        switch self {
        case .today: "Today"
        case .library: "Library"
        case .notebook: "Notebook"
        case .schedule: "Schedule"
        case .appearance: "Appearance"
        case .reader: "Reader"
        case .brief: "The Brief"
        case .editionEnd: "Edition complete"
        case .onboarding: "Welcome"
        }
    }

    var icon: FolioIcon? {
        switch self {
        case .today: .today
        case .library: .library
        case .notebook: .notebook
        case .schedule: .schedule
        case .appearance: .appearance
        default: nil
        }
    }
}
