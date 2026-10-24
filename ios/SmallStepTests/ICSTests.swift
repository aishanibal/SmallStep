import XCTest
@testable import SmallStep

private let ny = TimeZone(identifier: "America/New_York")!

/// "2026-03-10 14:00" in New York (daylight time starts 8 March 2026), as a Date.
private func at(_ s: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = ny; f.locale = Locale(identifier: "en_US_POSIX")
    return f.date(from: s)!
}

private func ics(_ events: String...) -> String {
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" + events.joined(separator: "\r\n") + "\r\nEND:VCALENDAR\r\n"
}

private func event(_ lines: String...) -> String { "BEGIN:VEVENT\r\n" + lines.joined(separator: "\r\n") + "\r\nEND:VEVENT" }

private let week = DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-15 00:00"))

private func parse(_ text: String) -> ICSResult { ICSParser.parse(text, window: week, defaultTimeZone: ny) }
private func spans(_ r: ICSResult) -> [String] {
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = ny; f.locale = Locale(identifier: "en_US_POSIX")
    return r.busy.map { "\(f.string(from: $0.start))-\(f.string(from: $0.end).suffix(5))" }
}

final class ICSParserTests: XCTestCase {
    func testUTCEvent() {
        let r = parse(ics(event("UID:a", "DTSTART:20260310T150000Z", "DTEND:20260310T160000Z")))   // 11:00-12:00 EDT
        XCTAssertEqual(spans(r), ["03-10 11:00-12:00"])
    }

    func testTimeZoneIDAndFoldedLines() {
        let r = parse(ics(event("UID:a", "DTSTART;TZID=America/New_York:2026031", " 0T140000", "DTEND;TZID=America/New_York:20260310T150000")))
        XCTAssertEqual(spans(r), ["03-10 14:00-15:00"])
    }

    func testFloatingTimeUsesDefaultZone() {
        XCTAssertEqual(spans(parse(ics(event("DTSTART:20260310T090000", "DTEND:20260310T093000")))), ["03-10 09:00-09:30"])
    }

    func testDurationInsteadOfEnd() {
        XCTAssertEqual(spans(parse(ics(event("DTSTART:20260310T090000", "DURATION:PT1H30M")))), ["03-10 09:00-10:30"])
    }

    func testAllDayTransparentAndCancelledAreNotBusy() {
        let r = parse(ics(
            event("DTSTART;VALUE=DATE:20260310", "DTEND;VALUE=DATE:20260311"),
            event("DTSTART:20260310T090000", "DTEND:20260310T100000", "TRANSP:TRANSPARENT"),
            event("DTSTART:20260310T110000", "DTEND:20260310T120000", "STATUS:CANCELLED")))
        XCTAssertTrue(r.busy.isEmpty)
        XCTAssertTrue(r.notes.contains(.allDayIgnored))
    }

    func testWindowsAndUnknownZoneNames() {
        let known = parse(ics(event("DTSTART;TZID=Eastern Standard Time:20260310T090000", "DTEND;TZID=Eastern Standard Time:20260310T100000")))
        XCTAssertEqual(spans(known), ["03-10 09:00-10:00"])
        XCTAssertFalse(known.notes.contains(.unknownTimeZone))
        let unknown = parse(ics(event("DTSTART;TZID=Nowhere Standard Time:20260310T090000", "DTEND;TZID=Nowhere Standard Time:20260310T100000")))
        XCTAssertTrue(unknown.notes.contains(.unknownTimeZone))
        XCTAssertEqual(unknown.busy.count, 1)
    }

    func testNestedAlarmDoesNotDisturbTheEvent() {
        let r = parse(ics("BEGIN:VEVENT\r\nDTSTART:20260310T090000\r\nDTEND:20260310T100000\r\nBEGIN:VALARM\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT"))
        XCTAssertEqual(spans(r), ["03-10 09:00-10:00"])
    }

    func testOutsideTheWindowIsLeftOut_andOvernightEventsCarryOver() {
        XCTAssertTrue(parse(ics(event("DTSTART:20260301T090000", "DTEND:20260301T100000"))).busy.isEmpty)
        let overnight = parse(ics(event("DTSTART:20260308T220000", "DTEND:20260309T020000")))   // ends 2am inside the window
        XCTAssertEqual(overnight.busy.count, 1)
    }

    // MARK: Repeating events

    func testWeeklyOnDaysWithAnExcludedDate() {
        let r = parse(ics(event("UID:w", "DTSTART;TZID=America/New_York:20260302T090000", "DTEND;TZID=America/New_York:20260302T100000",
                                "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR", "EXDATE;TZID=America/New_York:20260311T090000")))
        XCTAssertEqual(spans(r), ["03-09 09:00-10:00", "03-13 09:00-10:00"])   // Wed 11th excluded
    }

    func testCountUntilAndInterval() {
        let counted = parse(ics(event("DTSTART:20260309T090000", "DTEND:20260309T100000", "RRULE:FREQ=DAILY;COUNT=2")))
        XCTAssertEqual(counted.busy.count, 2)
        let until = parse(ics(event("DTSTART:20260309T090000", "DTEND:20260309T100000", "RRULE:FREQ=DAILY;UNTIL=20260311T235959")))
        XCTAssertEqual(until.busy.count, 3)
        let every2 = parse(ics(event("DTSTART:20260309T090000", "DTEND:20260309T100000", "RRULE:FREQ=DAILY;INTERVAL=2")))
        XCTAssertEqual(spans(every2), ["03-09 09:00-10:00", "03-11 09:00-10:00", "03-13 09:00-10:00"])
    }

    func testRepeatingMeetingKeepsItsWallClockTimeAcrossDaylightSaving() {
        // Starts on 2 March (standard time, UTC-5); the 9th is daylight time (UTC-4). Still 9:00 local.
        let r = parse(ics(event("DTSTART;TZID=America/New_York:20260302T090000", "DTEND;TZID=America/New_York:20260302T100000", "RRULE:FREQ=WEEKLY")))
        XCTAssertEqual(spans(r), ["03-09 09:00-10:00"])
        XCTAssertEqual(r.busy[0].start, ISO8601DateFormatter().date(from: "2026-03-09T13:00:00Z"))
    }

    func testMonthlyByDateSkipsMonthsWithoutThatDay() {
        let jan31 = ICSParser.parse(ics(event("DTSTART:20260131T090000", "DTEND:20260131T100000", "RRULE:FREQ=MONTHLY")),
                                    window: DateInterval(start: at("2026-02-01 00:00"), end: at("2026-04-01 00:00")), defaultTimeZone: ny)
        XCTAssertEqual(jan31.busy.count, 1, "only 31 March; February and (April) have no 31st")
    }

    func testUnsupportedPatternsAreFlaggedNotGuessed() {
        let r = parse(ics(event("DTSTART:20260309T090000", "DTEND:20260309T100000", "RRULE:FREQ=MONTHLY;BYDAY=1MO")))
        XCTAssertTrue(r.notes.contains(.unsupportedRecurrence))
        XCTAssertEqual(r.busy.count, 1, "keeps the first occurrence only")
    }

    func testMovedOccurrenceReplacesTheOriginal() {
        let r = parse(ics(
            event("UID:d", "DTSTART:20260309T090000", "DTEND:20260309T100000", "RRULE:FREQ=DAILY;COUNT=3"),
            event("UID:d", "RECURRENCE-ID:20260310T090000", "DTSTART:20260310T160000", "DTEND:20260310T170000")))
        XCTAssertEqual(spans(r), ["03-09 09:00-10:00", "03-10 16:00-17:00", "03-11 09:00-10:00"])
    }

    // MARK: Privacy

    func testTitlesAndPeopleNeverReachTheResult() {
        let text = ics(event("UID:p", "SUMMARY:Secret oncology appointment", "DESCRIPTION:Bring insurance card",
                             "LOCATION:Mercy Hospital", "ATTENDEE;CN=\"Jane Doe\":mailto:jane@example.com",
                             "DTSTART:20260310T150000Z", "DTEND:20260310T160000Z", "RRULE:FREQ=DAILY;COUNT=2"))
        let profile = ProfileRow(id: UUID(), wake: "07:00:00", bedtime: "23:00:00", breakfast: "08:00:00", lunch: "12:30:00",
                                 dinner: "19:00:00", quietStart: "22:00:00", quietEnd: "07:00:00", timezone: "America/New_York")
        let imported = GapFinder.importCalendar(text: text, profile: profile, now: at("2026-03-10 06:00"))
        let dump = String(describing: parse(text)) + String(describing: imported as Any)
        for secret in ["Secret", "oncology", "insurance", "Mercy", "Jane", "jane@example.com"] {
            XCTAssertFalse(dump.contains(secret), "\(secret) must not appear in anything the parser returns")
        }
        // The only values that exist are dates and minutes.
        let labels = Mirror(reflecting: BusyInterval(start: Date(), end: Date())).children.compactMap(\.label)
        XCTAssertEqual(Set(labels), ["start", "end"])
    }
}

final class GapFinderTests: XCTestCase {
    private func busy(_ pairs: (String, String)...) -> [BusyInterval] { pairs.map { BusyInterval(start: at($0.0), end: at($0.1)) } }
    private func gaps(_ b: [BusyInterval], now: String = "2026-03-10 06:00", wake: Int = 420, bed: Int = 1380) -> [String] {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = ny
        return GapFinder.freeGaps(busy: b, dayStart: at("2026-03-10 00:00"), wake: wake, bedtime: bed, timeZone: ny, now: at(now))
            .map { "\(f.string(from: $0.start))-\(f.string(from: $0.end))" }
    }

    func testGapsStayInsideWakingHours() {
        XCTAssertEqual(gaps(busy(("2026-03-10 11:00", "2026-03-10 12:00"), ("2026-03-10 13:30", "2026-03-10 14:00"))),
                       ["07:00-11:00", "12:00-13:30", "14:00-22:00"])     // last one capped at 8 hours; nothing before 07:00
    }

    func testNothingBeforeNow() {
        XCTAssertEqual(gaps(busy(("2026-03-10 13:30", "2026-03-10 14:00")), now: "2026-03-10 12:22"), ["12:25-13:30", "14:00-22:00"],
                       "now is rounded up to the next 5 minutes")
    }

    func testEventStartingBeforeWakeAndTinyGaps() {
        XCTAssertEqual(gaps(busy(("2026-03-10 06:00", "2026-03-10 08:00"), ("2026-03-10 08:05", "2026-03-10 20:00"))), ["20:00-23:00"],
                       "the 5-minute sliver is dropped")
    }

    func testEventsOverlappingEachOtherAreMerged() {
        XCTAssertEqual(gaps(busy(("2026-03-10 09:00", "2026-03-10 11:00"), ("2026-03-10 10:00", "2026-03-10 10:30"), ("2026-03-10 11:00", "2026-03-10 22:55"))),
                       ["07:00-09:00"])
    }

    func testBedtimeAfterMidnight() {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; f.timeZone = ny
        let g = GapFinder.freeGaps(busy: busy(("2026-03-10 07:00", "2026-03-10 23:00")), dayStart: at("2026-03-10 00:00"),
                                   wake: 420, bedtime: 60, timeZone: ny, now: at("2026-03-10 06:00"))
        XCTAssertEqual(g.map { "\(f.string(from: $0.start))-\(f.string(from: $0.end))" }, ["03-10 23:00-03-11 01:00"])
    }

    func testEndToEndImportCoversThreeDays() {
        let profile = ProfileRow(id: UUID(), wake: "07:00:00", bedtime: "23:00:00", breakfast: "08:00:00", lunch: "12:30:00",
                                 dinner: "19:00:00", quietStart: "22:00:00", quietEnd: "07:00:00", timezone: "America/New_York")
        let text = ics(event("DTSTART;TZID=America/New_York:20260310T090000", "DTEND;TZID=America/New_York:20260310T170000", "RRULE:FREQ=DAILY"),
                       event("DTSTART;VALUE=DATE:20260311", "DTEND;VALUE=DATE:20260312"))
        let imported = GapFinder.importCalendar(text: text, profile: profile, now: at("2026-03-10 08:00"))!
        XCTAssertEqual(imported.days.count, 3)
        XCTAssertEqual(imported.days[0].gaps.map(\.minutes), [60, 360], "08:00-09:00 and 17:00-23:00, today only from now")
        XCTAssertEqual(imported.days[1].gaps.map(\.minutes), [120, 360], "07:00-09:00, then 17:00-23:00")
        XCTAssertEqual(imported.notes, [ICSNote.allDayIgnored.rawValue])
    }

    func testIncompleteProfileGivesNoImport() {
        XCTAssertNil(GapFinder.importCalendar(text: ics(), profile: ProfileRow(id: UUID())))
    }
}

final class StoredCalendarTests: XCTestCase {
    func testBusyTimesRoundTripThroughJSONWithoutTitles() throws {
        let text = ics(event("SUMMARY:Private thing", "DTSTART:20260310T150000Z", "DTEND:20260310T160000Z"))
        let parsed = GapFinder.busyTimes(fromCalendar: text, timeZone: ny, now: at("2026-03-10 06:00"))!
        let data = try JSONEncoder().encode(CalendarStore.Saved(busy: parsed.busy, notes: parsed.notes, importedAt: Date()))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private"))
        XCTAssertEqual(try JSONDecoder().decode(CalendarStore.Saved.self, from: data).busy, parsed.busy)
    }

    func testStoredBusyTimesCoverThirtyDays() {
        let text = ics(event("DTSTART;TZID=America/New_York:20260310T090000", "DTEND;TZID=America/New_York:20260310T100000", "RRULE:FREQ=DAILY"))
        let parsed = GapFinder.busyTimes(fromCalendar: text, timeZone: ny, now: at("2026-03-10 06:00"))!
        XCTAssertEqual(parsed.busy.count, GapFinder.storedDays + 1)   // today through 30 days ahead
    }
}
