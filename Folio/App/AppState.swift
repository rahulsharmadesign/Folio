import Foundation
import Observation

/// App-wide navigation and session state.
@MainActor @Observable
final class AppState {
    var route: Route

    /// `-FolioDesignFixtures YES` fills screens with the mockups' sample content so they can be
    /// compared with design/screens/*.png. Never on by default.
    let designFixtures: Bool

    init(defaults: UserDefaults = .standard) {
        designFixtures = defaults.bool(forKey: "FolioDesignFixtures")
        route = defaults.string(forKey: "FolioRoute").flatMap(Route.init(rawValue:)) ?? .today
    }

    /// The sidebar's "Next edition" card. Real data arrives with the scheduler (M2).
    var nextEdition: NextEditionSummary? {
        designFixtures ? DesignFixtures.nextEdition : nil
    }
}
