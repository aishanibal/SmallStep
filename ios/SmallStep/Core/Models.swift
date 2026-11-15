import Foundation

// Rows as they appear in Postgres. Times of day are "HH:mm:ss" strings (Postgres `time`).

struct ProfileRow: Codable, Equatable {
    var id: UUID
    var wake: String?
    var bedtime: String?
    var breakfast: String?
    var lunch: String?
    var dinner: String?
    var quietStart: String?
    var quietEnd: String?
    var transitionMin: Int?
    var timezone: String?
    var wellnessStatement: String?
    var setupSeconds: Int?
    var consentedAt: Date?
    var remindersOn: Bool?
    var reminderDailyCap: Int?
    var remindersPausedUntil: Date?

    enum CodingKeys: String, CodingKey {
        case id, wake, bedtime, breakfast, lunch, dinner, timezone
        case quietStart = "quiet_start", quietEnd = "quiet_end", transitionMin = "transition_min"
        case wellnessStatement = "wellness_statement", setupSeconds = "setup_seconds", consentedAt = "consented_at"
        case remindersOn = "reminders_on", reminderDailyCap = "reminder_daily_cap", remindersPausedUntil = "reminders_paused_until"
    }

    var hasRhythm: Bool {
        [wake, bedtime, breakfast, lunch, dinner, quietStart, quietEnd, timezone].allSatisfy { $0 != nil }
    }
}

/// The Reminders screen's fields. Always sends every field, so Resume can clear the pause (null).
struct ReminderSettingsUpdate: Encodable {
    var remindersOn: Bool
    var dailyCap: Int
    var pausedUntil: Date?
    var quietStart: String
    var quietEnd: String

    enum CodingKeys: String, CodingKey {
        case remindersOn = "reminders_on", dailyCap = "reminder_daily_cap", pausedUntil = "reminders_paused_until"
        case quietStart = "quiet_start", quietEnd = "quiet_end"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(remindersOn, forKey: .remindersOn)
        try c.encode(dailyCap, forKey: .dailyCap)
        try c.encode(pausedUntil, forKey: .pausedUntil)     // encodes null when nil
        try c.encode(quietStart, forKey: .quietStart)
        try c.encode(quietEnd, forKey: .quietEnd)
    }
}

/// Fields sent when saving. Nil fields are left out, so they are never overwritten.
struct ProfileUpdate: Encodable {
    var wake: String?
    var bedtime: String?
    var breakfast: String?
    var lunch: String?
    var dinner: String?
    var quietStart: String?
    var quietEnd: String?
    var transitionMin: Int?
    var timezone: String?
    var wellnessStatement: String?
    var setupSeconds: Int?
    var consentedAt: Date?

    enum CodingKeys: String, CodingKey {
        case wake, bedtime, breakfast, lunch, dinner, timezone
        case quietStart = "quiet_start", quietEnd = "quiet_end", transitionMin = "transition_min"
        case wellnessStatement = "wellness_statement", setupSeconds = "setup_seconds", consentedAt = "consented_at"
    }
}

enum ActivityLocation: String, Codable, CaseIterable, Identifiable {
    case indoors, outdoors, anywhere
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct ActivityRow: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var category: String
    var durationMin: Int
    var location: ActivityLocation
    var priority: Int
    var weeklyIntention: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, category, location, priority
        case durationMin = "duration_min", weeklyIntention = "weekly_intention"
    }
}

struct ActivityWrite: Encodable {
    var name: String
    var category: String
    var durationMin: Int
    var location: ActivityLocation
    var priority: Int
    var weeklyIntention: Int?

    enum CodingKeys: String, CodingKey {
        case name, category, location, priority
        case durationMin = "duration_min", weeklyIntention = "weekly_intention"
    }

    // Encode a nil intention as JSON null so "whenever" really clears the column.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(durationMin, forKey: .durationMin)
        try c.encode(location, forKey: .location)
        try c.encode(priority, forKey: .priority)
        try c.encode(weeklyIntention, forKey: .weeklyIntention)
    }
}

enum GapOrigin: String, Encodable { case manual, calendar, windowReminder = "window_reminder" }

struct GapInsert: Encodable {
    var startTime: Date
    var minutes: Int
    var energy: Int?
    var origin: GapOrigin = .manual
    var windowId: UUID?
    enum CodingKeys: String, CodingKey { case startTime = "start_time", minutes, energy, origin, windowId = "window_id" }
}

/// A usual free time the student entered, e.g. Mondays at 14:00 for 45 minutes. Weekday is ISO (1 = Monday).
struct ReminderWindow: Codable, Identifiable, Hashable {
    let id: UUID
    let weekday: Int
    let startTime: String       // "HH:mm:ss", local
    let minutes: Int
    enum CodingKeys: String, CodingKey { case id, weekday, minutes, startTime = "start_time" }

    var startMinute: Int { Rhythm.minutes(fromClock: startTime) ?? 0 }
}

struct ReminderWindowInsert: Encodable {
    var weekday: Int
    var startTime: String
    var minutes: Int
    enum CodingKeys: String, CodingKey { case weekday, minutes, startTime = "start_time" }
}

struct IDRow: Decodable { let id: UUID }

/// A card as the app sees it. There is deliberately no source field.
struct SuggestionCard: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let durationMin: Int
    let position: Int
    enum CodingKeys: String, CodingKey { case id, title, description, position, durationMin = "duration_min" }
}

struct SuggestionSet: Codable, Hashable {
    let setId: UUID?
    let cards: [SuggestionCard]
    enum CodingKeys: String, CodingKey { case setId = "set_id", cards }
}

struct OutcomeRow: Decodable {
    let id: UUID
    let setId: UUID
    let chosenSuggestionId: UUID?
    let completed: Bool?
    enum CodingKeys: String, CodingKey { case id, completed, setId = "set_id", chosenSuggestionId = "chosen_suggestion_id" }
}

struct OutcomeInsert: Encodable {
    var setId: UUID
    var chosenSuggestionId: UUID?
    var noneReason: String?
    enum CodingKeys: String, CodingKey { case setId = "set_id", chosenSuggestionId = "chosen_suggestion_id", noneReason = "none_reason" }
}

struct OutcomeUpdate: Encodable {
    var completed: Bool?
    var skipReason: String?
    var fitRating: Int?
    /// "app" or "reminder": where Done/Skip was recorded.
    var via: String?
    enum CodingKeys: String, CodingKey { case completed, via, skipReason = "skip_reason", fitRating = "fit_rating" }
}

/// One line in reminder_events. The id is made on the phone so a resend after a failed upload is ignored.
/// About exactly one thing: an outcome reminder or a free-time window.
struct ReminderEventInsert: Codable, Equatable {
    var id = UUID()
    var outcomeId: UUID?
    var windowId: UUID?
    var kind: String
    var detail: String?
    var at = Date()
    enum CodingKeys: String, CodingKey { case id, kind, detail, at, outcomeId = "outcome_id", windowId = "window_id" }
}

/// An outcome that was chosen but not yet marked done or skipped.
struct PendingOutcome: Hashable {
    let outcomeId: UUID
    let card: SuggestionCard
}

struct HistoryOutcome: Decodable {
    let id: UUID
    let chosenSuggestionId: UUID?
    let completed: Bool?
    let skipReason: String?
    let fitRating: Int?
    let noneReason: String?
    let ts: Date
    enum CodingKeys: String, CodingKey {
        case id, completed, ts
        case chosenSuggestionId = "chosen_suggestion_id"
        case skipReason = "skip_reason", fitRating = "fit_rating", noneReason = "none_reason"
    }
}

/// One line in the participant's history. No suggestion source.
struct HistoryEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let at: Date
    let status: String
    let detail: String?

    init(row: HistoryOutcome, cardTitle: String?) {
        id = row.id
        at = row.ts
        if row.noneReason == "wanted_another" {
            title = "Asked for other ideas"
            status = "Swapped"
            detail = nil
        } else if row.chosenSuggestionId == nil {
            title = "None of these"
            status = "None of these"
            detail = Self.noneLabels[row.noneReason ?? ""]
        } else {
            title = cardTitle ?? "A suggestion"
            if row.completed == true {
                status = "Done"
                detail = row.fitRating.map { "Fit \($0) of 5" }
            } else if row.completed == false {
                status = "Skipped"
                detail = Self.skipLabels[row.skipReason ?? ""]
            } else {
                status = "Still open"
                detail = nil
            }
        }
    }

    private static let skipLabels = [
        "no_energy": "No energy", "ran_out_of_time": "Ran out of time",
        "changed_my_mind": "Changed my mind", "wrong_place": "Wrong place", "something_else": "Something else",
    ]
    private static let noneLabels = [
        "not_now": "Not now", "not_interested": "Not interested",
        "wrong_length": "Wrong length", "wrong_place": "Wrong place", "something_else": "Something else",
    ]
}

/// Response of the `dev-info` function, shown only on the hidden developer screen.
struct DevInfo: Decodable {
    struct Last: Decodable {
        let setCreatedAt: String   // ISO 8601; functions.invoke uses a plain JSONDecoder, so no Date here
        let status: String          // "model" or "fallback"
        let error: String?
        let model: String?
        let prompt: String?
        let historySummaryUsed: String?
        enum CodingKeys: String, CodingKey {
            case status, error, model, prompt
            case setCreatedAt = "set_created_at", historySummaryUsed = "history_summary_used"
        }
    }
    let historySummaryNow: [String]
    let last: Last?
    enum CodingKeys: String, CodingKey { case historySummaryNow = "history_summary_now", last }
}
