import Foundation

/// The student's reminder controls, read from their profile. Quiet hours are the same ones suggestions use.
struct ReminderSettings: Codable, Equatable {
    var enabled: Bool
    var dailyCap: Int
    var pausedUntil: Date?
    /// Minutes after midnight. Equal start and end means no quiet hours.
    var quietStart: Int
    var quietEnd: Int
    var timeZoneID: String

    static let defaultCap = 3

    init(enabled: Bool = true, dailyCap: Int = defaultCap, pausedUntil: Date? = nil,
         quietStart: Int = 22 * 60, quietEnd: Int = 7 * 60, timeZoneID: String = TimeZone.current.identifier) {
        self.enabled = enabled; self.dailyCap = dailyCap; self.pausedUntil = pausedUntil
        self.quietStart = quietStart; self.quietEnd = quietEnd; self.timeZoneID = timeZoneID
    }

    init(profile: ProfileRow) {
        self.init(
            enabled: profile.remindersOn ?? true,
            dailyCap: profile.reminderDailyCap ?? Self.defaultCap,
            pausedUntil: profile.remindersPausedUntil,
            quietStart: Rhythm.minutes(fromClock: profile.quietStart) ?? 22 * 60,
            quietEnd: Rhythm.minutes(fromClock: profile.quietEnd) ?? 7 * 60,
            timeZoneID: profile.timezone ?? TimeZone.current.identifier
        )
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    func isPaused(at date: Date) -> Bool { pausedUntil.map { date < $0 } ?? false }
}

/// A reminder to log one chosen activity. Kept on the phone so the schedule can be rebuilt at any time.
struct ReminderPlan: Codable, Equatable, Identifiable {
    let outcomeId: UUID
    let card: SuggestionCard
    var fireDate: Date
    var snoozes = 0
    /// Set when Done or Skip was saved. Kept for a while so it still counts toward the daily cap.
    var resolvedAt: Date?
    var id: UUID { outcomeId }

    /// Whether the notification has already been shown (it fired before the outcome was logged).
    func wasDelivered(now: Date) -> Bool { fireDate <= min(now, resolvedAt ?? now) }
}

enum ReminderDecision: Equatable {
    case fire(Date)
    case suppressed(String)     // "off", "paused", "daily_cap", and for windows "quiet_hours"
}

/// One upcoming start of a free-time window.
struct WindowOccurrence: Equatable, Hashable {
    let windowId: UUID
    let start: Date
    let minutes: Int
    var key: String { "\(windowId.uuidString)-\(Int(start.timeIntervalSince1970))" }
}

/// Every decision for one rebuild of the schedule.
struct ReminderSchedule: Equatable {
    var outcomes: [UUID: ReminderDecision] = [:]
    var windows: [String: ReminderDecision] = [:]
}

/// Pure scheduling rules. No notification APIs here, so all of it is unit-tested.
enum ReminderRules {
    static let slackMinutes = 5
    static let snoozeMinutes = 15
    static let maxSnoozes = 3
    /// Plans older than this are forgotten.
    static let keepHours = 48
    /// Window nudges are set this many days ahead; opening the app tops them up.
    static let windowDaysAhead = 7
    /// iOS keeps at most 64 pending notifications per app. Leave a little room.
    static let maxPending = 60

    /// When the activity should be over: it starts at the gap (or now, if the gap already began) and lasts its duration.
    static func outcomeFireDate(gapStart: Date, durationMin: Int, now: Date) -> Date {
        max(gapStart, now).addingTimeInterval(Double(durationMin + slackMinutes) * 60)
    }

    /// A time inside quiet hours moves to when quiet hours end. Handles windows that cross midnight.
    static func outOfQuietHours(_ date: Date, _ s: ReminderSettings) -> Date {
        let length = ((s.quietEnd - s.quietStart) % 1440 + 1440) % 1440
        guard length > 0 else { return date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = s.timeZone
        let dayStart = cal.startOfDay(for: date)
        let minute = Int(date.timeIntervalSince(dayStart) / 60)
        let intoQuiet = ((minute - s.quietStart) % 1440 + 1440) % 1440
        guard intoQuiet < length else { return date }
        return cal.date(byAdding: .minute, value: length - intoQuiet, to: cal.date(byAdding: .minute, value: minute, to: dayStart)!)!
    }

    /// Outcome reminders only. See `schedule` for the rules.
    static func decide(_ plans: [ReminderPlan], settings s: ReminderSettings, now: Date) -> [UUID: ReminderDecision] {
        schedule(plans: plans, windows: [], shownWindowFires: [], settings: s, now: now).outcomes
    }

    /// The upcoming starts of each window, from now through `windowDaysAhead` days, earliest first.
    static func occurrences(_ windows: [ReminderWindow], settings s: ReminderSettings, now: Date) -> [WindowOccurrence] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = s.timeZone
        let today = cal.startOfDay(for: now)
        var out: [WindowOccurrence] = []
        for offset in 0..<windowDaysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let iso = (cal.component(.weekday, from: day) + 5) % 7 + 1      // Calendar: 1 = Sunday. ISO: 1 = Monday.
            for w in windows where w.weekday == iso {
                guard let start = cal.date(byAdding: .minute, value: w.startMinute, to: day), start > now else { continue }
                out.append(WindowOccurrence(windowId: w.id, start: start, minutes: w.minutes))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Decides every notification still to come.
    /// - Off, paused: nothing is sent.
    /// - Quiet hours: an outcome reminder waits until they end; a window nudge that starts in them is dropped.
    /// - Daily cap: reminders already shown that day count. Outcome reminders come first, then window nudges.
    /// - At most `maxPending` notifications are set at once; the furthest-out window nudges wait for a later rebuild.
    static func schedule(plans: [ReminderPlan], windows: [WindowOccurrence], shownWindowFires: [Date],
                         settings s: ReminderSettings, now: Date) -> ReminderSchedule {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = s.timeZone
        var perDay: [Date: Int] = [:]
        for p in plans where p.wasDelivered(now: now) { perDay[cal.startOfDay(for: p.fireDate), default: 0] += 1 }
        for d in shownWindowFires where d <= now { perDay[cal.startOfDay(for: d), default: 0] += 1 }

        var out = ReminderSchedule()
        var pending = 0
        func check(_ when: Date) -> ReminderDecision {
            guard s.enabled else { return .suppressed("off") }
            if s.isPaused(at: when) { return .suppressed("paused") }
            let day = cal.startOfDay(for: when)
            if perDay[day, default: 0] >= s.dailyCap { return .suppressed("daily_cap") }
            perDay[day, default: 0] += 1
            pending += 1
            return .fire(when)
        }

        for p in plans.filter({ $0.resolvedAt == nil && $0.fireDate > now }).sorted(by: { $0.fireDate < $1.fireDate }) {
            out.outcomes[p.id] = check(outOfQuietHours(p.fireDate, s))
        }
        for w in windows.filter({ $0.start > now }).sorted(by: { $0.start < $1.start }) {
            guard pending < maxPending else { break }
            if s.enabled, outOfQuietHours(w.start, s) != w.start { out.windows[w.key] = .suppressed("quiet_hours"); continue }
            out.windows[w.key] = check(w.start)
        }
        return out
    }

    /// Drops plans that are long finished, so the store stays small.
    static func pruned(_ plans: [ReminderPlan], now: Date) -> [ReminderPlan] {
        let cutoff = now.addingTimeInterval(-Double(keepHours) * 3600)
        return plans.filter { max($0.fireDate, $0.resolvedAt ?? $0.fireDate) > cutoff }
    }
}
