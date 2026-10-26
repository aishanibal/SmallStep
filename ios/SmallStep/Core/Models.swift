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
    var timezone: String?
    var wellnessStatement: String?
    var setupSeconds: Int?
    var consentedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, wake, bedtime, breakfast, lunch, dinner, timezone
        case quietStart = "quiet_start", quietEnd = "quiet_end"
        case wellnessStatement = "wellness_statement", setupSeconds = "setup_seconds", consentedAt = "consented_at"
    }

    var hasRhythm: Bool {
        [wake, bedtime, breakfast, lunch, dinner, quietStart, quietEnd, timezone].allSatisfy { $0 != nil }
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
    var timezone: String?
    var wellnessStatement: String?
    var setupSeconds: Int?
    var consentedAt: Date?

    enum CodingKeys: String, CodingKey {
        case wake, bedtime, breakfast, lunch, dinner, timezone
        case quietStart = "quiet_start", quietEnd = "quiet_end"
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

struct GapInsert: Encodable {
    var startTime: Date
    var minutes: Int
    var energy: Int?
    enum CodingKeys: String, CodingKey { case startTime = "start_time", minutes, energy }
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
    enum CodingKeys: String, CodingKey { case completed, skipReason = "skip_reason", fitRating = "fit_rating" }
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
