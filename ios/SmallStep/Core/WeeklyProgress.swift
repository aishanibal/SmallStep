import Foundation

/// One row from weekly_progress(): completed outcomes this week for one activity (nil = other ideas).
struct ProgressRow: Decodable, Equatable {
    let activityId: UUID?
    let done: Int
    enum CodingKeys: String, CodingKey { case done, activityId = "activity_id" }
}

/// One line on the "This week" card. Only counts what was done: no streaks, nothing about missed days.
struct ProgressLine: Identifiable, Equatable {
    let id: String
    let title: String
    let done: Int
    let goal: Int?

    var summary: String {
        guard let goal else { return "\(done) done" }
        return done > goal ? "\(done) done · goal \(goal)" : "\(done) of \(goal)"
    }
    var goalMet: Bool { goal.map { done >= $0 } ?? false }
}

enum WeeklyProgress {
    /// Monday 00:00 of the week containing `now`, in the participant's time zone.
    static func weekStart(_ now: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
    }

    /// Activities with a weekly goal always show (even at 0, which reads as a fresh week, not a miss).
    /// Activities without one show once something is done. Other ideas come last.
    static func lines(rows: [ProgressRow], activities: [ActivityRow]) -> [ProgressLine] {
        var doneByActivity: [UUID: Int] = [:]
        var other = 0
        let known = Set(activities.map(\.id))
        for row in rows {
            if let id = row.activityId, known.contains(id) { doneByActivity[id, default: 0] += row.done }
            else { other += row.done }     // not tied to an activity, or one that was removed
        }
        // Most important first, then by name.
        let ordered = activities.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.name < $1.name }
        var out = ordered.compactMap { a -> ProgressLine? in
            let done = doneByActivity[a.id] ?? 0
            guard a.weeklyIntention != nil || done > 0 else { return nil }
            return ProgressLine(id: a.id.uuidString, title: a.name, done: done, goal: a.weeklyIntention)
        }
        if other > 0 { out.append(ProgressLine(id: "other", title: "Other ideas", done: other, goal: nil)) }
        return out
    }
}
