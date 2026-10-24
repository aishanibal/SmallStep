import Foundation

// Local .ics reader. It reads only when events start, end and repeat. SUMMARY, DESCRIPTION, LOCATION,
// ATTENDEE and every other property are skipped, so titles cannot reach any value this file produces.

struct BusyInterval: Hashable, Codable {
    var start: Date
    var end: Date
}

/// Things the participant should know about, because the result may be less exact than it looks.
enum ICSNote: String, Hashable, CaseIterable {
    case unsupportedRecurrence = "Some repeating events follow patterns we can't read, so those may be missing."
    case unknownTimeZone = "Some events used a time zone we don't recognise, so we assumed yours."
    case allDayIgnored = "All-day events aren't treated as busy."
}

struct ICSResult {
    var busy: [BusyInterval] = []
    var notes: Set<ICSNote> = []
}

enum ICSParser {
    /// Busy intervals that overlap `window`. `defaultTimeZone` is used for events without a zone.
    static func parse(_ text: String, window: DateInterval, defaultTimeZone: TimeZone) -> ICSResult {
        var result = ICSResult()
        let events = readEvents(text)

        // Edited or cancelled single occurrences of a repeating event replace that occurrence.
        var replaced: [String: [Date]] = [:]
        for e in events {
            if let uid = e.uid, let rid = e.recurrenceID,
               let parsed = parseDate(rid, defaultTimeZone: defaultTimeZone, notes: &result.notes) {
                replaced[uid, default: []].append(parsed.date)
            }
        }

        for e in events where !e.cancelled && !e.transparent {
            guard let startProp = e.dtstart,
                  let start = parseDate(startProp, defaultTimeZone: defaultTimeZone, notes: &result.notes) else { continue }
            if start.allDay { result.notes.insert(.allDayIgnored); continue }

            var duration: TimeInterval = 0
            if let endProp = e.dtend, let end = parseDate(endProp, defaultTimeZone: defaultTimeZone, notes: &result.notes), !end.allDay {
                duration = end.date.timeIntervalSince(start.date)
            } else if let d = e.duration {
                duration = parseDuration(d) ?? 0
            }
            guard duration > 0 else { continue }

            var starts = [start.date]
            if let ruleText = e.rrule {
                var excluded = Set((replaced[e.uid ?? ""] ?? []).map { Int($0.timeIntervalSince1970) })
                for p in e.exdates {
                    for piece in p.value.split(separator: ",") {
                        var single = p; single.value = String(piece)
                        if let d = parseDate(single, defaultTimeZone: defaultTimeZone, notes: &result.notes) { excluded.insert(Int(d.date.timeIntervalSince1970)) }
                    }
                }
                if let rule = RRule(ruleText, defaultTimeZone: defaultTimeZone, notes: &result.notes) {
                    starts = rule.occurrences(from: start.date, in: start.zone, until: window.end)
                } else {
                    result.notes.insert(.unsupportedRecurrence)   // keep just the first occurrence
                }
                starts = starts.filter { !excluded.contains(Int($0.timeIntervalSince1970)) }
            }

            for s in starts {
                let interval = BusyInterval(start: s, end: s.addingTimeInterval(duration))
                if interval.end > window.start && interval.start < window.end { result.busy.append(interval) }
            }
        }
        result.busy.sort { $0.start < $1.start }
        return result
    }

    // MARK: Reading lines

    /// One event with only the fields needed for timing. There is deliberately no title field.
    private struct RawEvent {
        var uid: String?
        var dtstart: Property?
        var dtend: Property?
        var duration: String?
        var rrule: String?
        var exdates: [Property] = []
        var recurrenceID: Property?
        var transparent = false
        var cancelled = false
    }

    fileprivate struct Property {
        var name: String
        var params: [String: String]
        var value: String
    }

    private static func readEvents(_ text: String) -> [RawEvent] {
        var events: [RawEvent] = []
        var stack: [String] = []
        var current: RawEvent?

        for line in unfold(text) {
            guard let prop = parseProperty(line) else { continue }
            switch prop.name {
            case "BEGIN":
                stack.append(prop.value.uppercased())
                if prop.value.uppercased() == "VEVENT" && stack.count >= 1 { current = RawEvent() }
            case "END":
                if prop.value.uppercased() == "VEVENT", let done = current { events.append(done); current = nil }
                if !stack.isEmpty { stack.removeLast() }
            default:
                // Only properties directly inside a VEVENT (not inside a nested alarm, say).
                guard stack.last == "VEVENT", current != nil else { continue }
                switch prop.name {
                case "UID": current?.uid = prop.value
                case "DTSTART": current?.dtstart = prop
                case "DTEND": current?.dtend = prop
                case "DURATION": current?.duration = prop.value
                case "RRULE": current?.rrule = prop.value
                case "EXDATE": current?.exdates.append(prop)
                case "RECURRENCE-ID": current?.recurrenceID = prop
                case "TRANSP": current?.transparent = prop.value.uppercased() == "TRANSPARENT"
                case "STATUS": current?.cancelled = prop.value.uppercased() == "CANCELLED"
                default: break    // SUMMARY, DESCRIPTION, LOCATION, ATTENDEE, ... are never read
                }
            }
        }
        return events
    }

    private static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalised.split(separator: "\n", omittingEmptySubsequences: true) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    private static func parseProperty(_ line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() } else if c == ":" && !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let value = String(line[line.index(after: colon)...])

        var parts: [String] = []
        var piece = ""
        inQuotes = false
        for c in line[..<colon] {
            if c == "\"" { inQuotes.toggle(); piece.append(c) }
            else if c == ";" && !inQuotes { parts.append(piece); piece = "" }
            else { piece.append(c) }
        }
        parts.append(piece)

        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            guard let eq = p.firstIndex(of: "=") else { continue }
            params[p[..<eq].uppercased()] = String(p[p.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: parts[0].uppercased(), params: params, value: value)
    }

    // MARK: Dates

    fileprivate struct ParsedDate { var date: Date; var allDay: Bool; var zone: TimeZone }

    /// A few Windows zone names that Outlook exports use.
    private static let windowsZones: [String: String] = [
        "Eastern Standard Time": "America/New_York", "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver", "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage", "Hawaiian Standard Time": "Pacific/Honolulu",
        "GMT Standard Time": "Europe/London", "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest", "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai", "Tokyo Standard Time": "Asia/Tokyo", "UTC": "UTC",
    ]

    fileprivate static func parseDate(_ p: Property, defaultTimeZone: TimeZone, notes: inout Set<ICSNote>) -> ParsedDate? {
        let v = p.value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter(\.isNumber)
        guard digits.count == 8 || digits.count == 14 else { return nil }

        var zone = defaultTimeZone
        if v.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC")!
        } else if let tzid = p.params["TZID"] {
            if let z = TimeZone(identifier: tzid) ?? windowsZones[tzid].flatMap(TimeZone.init(identifier:)) { zone = z }
            else { notes.insert(.unknownTimeZone) }
        }

        func int(_ r: Range<Int>) -> Int { Int(digits[digits.index(digits.startIndex, offsetBy: r.lowerBound)..<digits.index(digits.startIndex, offsetBy: r.upperBound)]) ?? 0 }
        var c = DateComponents()
        c.year = int(0..<4); c.month = int(4..<6); c.day = int(6..<8)
        let allDay = digits.count == 8
        if !allDay { c.hour = int(8..<10); c.minute = int(10..<12); c.second = int(12..<14) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        guard let date = cal.date(from: c) else { return nil }
        return ParsedDate(date: date, allDay: allDay, zone: zone)
    }

    /// "PT1H30M", "P1D", "P1W" -> seconds.
    private static func parseDuration(_ s: String) -> TimeInterval? {
        var total: TimeInterval = 0, number = "", inTime = false
        for ch in s.uppercased() {
            switch ch {
            case "P", "+": continue
            case "T": inTime = true
            case "0"..."9": number.append(ch)
            case "W": total += (Double(number) ?? 0) * 604_800; number = ""
            case "D": total += (Double(number) ?? 0) * 86_400; number = ""
            case "H" where inTime: total += (Double(number) ?? 0) * 3_600; number = ""
            case "M" where inTime: total += (Double(number) ?? 0) * 60; number = ""
            case "S" where inTime: total += Double(number) ?? 0; number = ""
            default: return nil
            }
        }
        return total
    }
}

// MARK: Repeating events (the common cases: daily, weekly with days, monthly by date, yearly)

private struct RRule {
    enum Freq { case daily, weekly, monthly, yearly }
    var freq: Freq
    var interval = 1
    var count: Int?
    var until: Date?
    var weekdays: [Int] = []     // Calendar weekday numbers, Sunday = 1

    /// Returns nil when the rule uses parts we don't support (the caller then flags it).
    init?(_ text: String, defaultTimeZone: TimeZone, notes: inout Set<ICSNote>) {
        var dict: [String: String] = [:]
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { dict[kv[0].uppercased()] = kv[1] }
        }
        switch dict["FREQ"]?.uppercased() {
        case "DAILY": freq = .daily
        case "WEEKLY": freq = .weekly
        case "MONTHLY": freq = .monthly
        case "YEARLY": freq = .yearly
        default: return nil
        }
        let unsupported = ["BYSETPOS", "BYMONTH", "BYMONTHDAY", "BYYEARDAY", "BYWEEKNO", "BYHOUR", "BYMINUTE", "BYSECOND"]
        if unsupported.contains(where: { dict[$0] != nil }) { return nil }
        if let byday = dict["BYDAY"] {
            guard freq == .weekly else { return nil }       // e.g. "first Monday of the month"
            let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            let days = byday.split(separator: ",").compactMap { map[String($0).uppercased()] }
            guard days.count == byday.split(separator: ",").count else { return nil }
            weekdays = days
        }
        interval = max(1, Int(dict["INTERVAL"] ?? "1") ?? 1)
        count = dict["COUNT"].flatMap { Int($0) }
        if let u = dict["UNTIL"] {
            let prop = ICSParser.Property(name: "UNTIL", params: [:], value: u)
            guard let parsed = ICSParser.parseDate(prop, defaultTimeZone: defaultTimeZone, notes: &notes) else { return nil }
            // A date-only UNTIL includes that whole day.
            until = parsed.allDay ? parsed.date.addingTimeInterval(86_399) : parsed.date
        }
    }

    /// Start times of occurrences from `start` up to `limit`, in the event's own time zone (so a 9:00
    /// meeting stays at 9:00 across daylight saving changes).
    func occurrences(from start: Date, in zone: TimeZone, until limit: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.firstWeekday = 2   // weeks start on Monday
        let stop = min(until ?? .distantFuture, limit)
        var out: [Date] = []
        var produced = 0
        let maxOccurrences = count ?? Int.max

        func add(_ d: Date) -> Bool {          // false once we should stop
            guard d <= stop, produced < maxOccurrences else { return false }
            out.append(d); produced += 1
            return true
        }

        switch freq {
        case .daily, .monthly, .yearly:
            let unit: Calendar.Component = freq == .daily ? .day : (freq == .monthly ? .month : .year)
            let startDay = cal.component(.day, from: start), startMonth = cal.component(.month, from: start)
            for k in 0..<20_000 {
                guard let d = cal.date(byAdding: unit, value: k * interval, to: start), d <= stop else { break }
                // "31st of each month" skips months with no 31st instead of sliding to the 30th.
                if freq != .daily, cal.component(.day, from: d) != startDay { continue }
                if freq == .yearly, cal.component(.month, from: d) != startMonth { continue }
                if !add(d) { break }
            }
        case .weekly:
            let days = weekdays.isEmpty ? [cal.component(.weekday, from: start)] : weekdays
            let offsets = Set(days.map { ($0 + 5) % 7 }).sorted()        // Monday = 0
            let timeParts = cal.dateComponents([.hour, .minute, .second], from: start)
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: start)?.start else { return [start] }
            weeks: for k in 0..<5_000 {
                guard let base = cal.date(byAdding: .weekOfYear, value: k * interval, to: weekStart), base <= stop else { break }
                for offset in offsets {
                    guard let day = cal.date(byAdding: .day, value: offset, to: base),
                          let d = cal.date(bySettingHour: timeParts.hour ?? 0, minute: timeParts.minute ?? 0, second: timeParts.second ?? 0, of: day),
                          d >= start else { continue }
                    if !add(d) { break weeks }
                }
            }
        }
        return out
    }
}
