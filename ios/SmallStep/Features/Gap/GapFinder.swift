import Foundation

struct FreeGap: Identifiable, Hashable {
    let start: Date
    let end: Date
    var id: Date { start }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct CalendarDay: Hashable, Identifiable {
    let date: Date          // start of that day in the participant's time zone
    let gaps: [FreeGap]
    var id: Date { date }
}

struct CalendarImport: Hashable {
    let days: [CalendarDay]
    let notes: [String]
    var isEmpty: Bool { days.allSatisfy { $0.gaps.isEmpty } }
}

enum GapFinder {
    static let minMinutes = 10
    static let maxMinutes = 480        // the database accepts at most 8 hours per gap
    static let dayCount = 3            // today and the next two days

    /// Free time inside [wake, bedtime) on the day starting at `dayStart`, minus busy intervals.
    /// Nothing before `now` is offered. Gaps shorter than `minMinutes` are dropped.
    static func freeGaps(busy: [BusyInterval], dayStart: Date, wake: Int, bedtime: Int,
                         timeZone: TimeZone, now: Date) -> [FreeGap] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let open = cal.date(byAdding: .minute, value: wake, to: dayStart),
              let close = cal.date(byAdding: .minute, value: bedtime > wake ? bedtime : bedtime + 1440, to: dayStart) else { return [] }

        var cursor = max(open, roundedUp(now))
        var gaps: [FreeGap] = []

        func emit(_ from: Date, _ to: Date) {
            let capped = min(to, from.addingTimeInterval(Double(maxMinutes) * 60))
            if capped.timeIntervalSince(from) >= Double(minMinutes) * 60 { gaps.append(FreeGap(start: from, end: capped)) }
        }

        for b in busy.sorted(by: { $0.start < $1.start }) where b.end > cursor && b.start < close {
            if b.start > cursor { emit(cursor, min(b.start, close)) }
            cursor = max(cursor, b.end)
            if cursor >= close { break }
        }
        if cursor < close { emit(cursor, close) }
        return gaps
    }

    private static func roundedUp(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
    }

    /// Days of busy times kept on the phone after an upload.
    static let storedDays = 30

    /// Parses a calendar file into busy times (start and end only) from yesterday through `days` ahead.
    static func busyTimes(fromCalendar text: String, timeZone: TimeZone, now: Date = Date(), days: Int = storedDays)
        -> (busy: [BusyInterval], notes: [String])? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        // Start a day early: a late event from yesterday can run past midnight into today.
        guard let start = cal.date(byAdding: .day, value: -1, to: today),
              let end = cal.date(byAdding: .day, value: days + 1, to: today) else { return nil }
        let parsed = ICSParser.parse(text, window: DateInterval(start: start, end: end), defaultTimeZone: timeZone)
        return (parsed.busy, ICSNote.allCases.filter(parsed.notes.contains).map(\.rawValue))
    }

    /// Free gaps for today and the next couple of days, from stored busy times.
    static func upcoming(busy: [BusyInterval], notes: [String], profile: ProfileRow, now: Date = Date()) -> CalendarImport? {
        guard let wake = Rhythm.minutes(fromClock: profile.wake), let bed = Rhythm.minutes(fromClock: profile.bedtime) else { return nil }
        let zone = profile.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        let days: [CalendarDay] = (0..<dayCount).compactMap { offset in
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            return CalendarDay(date: dayStart, gaps: freeGaps(busy: busy, dayStart: dayStart, wake: wake, bedtime: bed, timeZone: zone, now: now))
        }
        return CalendarImport(days: days, notes: notes)
    }

    /// Parse and find gaps in one go (used by tests).
    static func importCalendar(text: String, profile: ProfileRow, now: Date = Date()) -> CalendarImport? {
        let zone = profile.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        guard profile.wake != nil, let parsed = busyTimes(fromCalendar: text, timeZone: zone, now: now, days: dayCount) else { return nil }
        return upcoming(busy: parsed.busy, notes: parsed.notes, profile: profile, now: now)
    }
}
