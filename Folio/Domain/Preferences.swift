import Foundation

/// User preferences (SPEC › Preferences). Stored as JSON in UserDefaults; never holds secrets.
struct Preferences: Codable, Equatable, Sendable {
    // Appearance
    var themeID = Tokens.paper.id
    var displayFamily = Tokens.displayFamilyDefault
    var readingFamily = Tokens.readingFamilyDefault
    var uiFamily = Tokens.uiFamilyDefault
    var accentID = Tokens.defaultAccentID
    var textSize: Double = 20

    // Schedule
    var cadence: Cadence = .twice
    var slots: [ScheduleSlot] = ScheduleSlot.defaults(for: .twice)
    var editionLimit = Chunker.defaultLimit
    var neverPileUp = true
    var quietArrival = true
    /// "Pause editions for today" from the menu bar.
    var pausedUntil: Date?

    // Library
    var standardEbooks = true
    var gutenberg = true
    var surpriseWeekly = true

    // Onboarding (01)
    var onboarded = false
    var wantsBooks = true
    var wantsPublications = false
    var wantsBrief = true

    var openAtLogin = false

    private static let key = "FolioPreferences"

    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: key), let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    func isPaused(at now: Date) -> Bool { pausedUntil.map { now < $0 } ?? false }
}
