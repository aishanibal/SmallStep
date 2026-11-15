import XCTest
@testable import SmallStep

final class ReminderRulesTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private let card = SuggestionCard(id: UUID(), title: "Stretch", description: "d", durationMin: 15, position: 0)

    /// A local New York time on 2026-11-16 (a Monday, EST).
    private func ny(_ hhmm: String, day: Int = 16) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: "2026-11-\(day)T\(hhmm):00-05:00")!
    }

    private func settings(_ change: (inout ReminderSettings) -> Void = { _ in }) -> ReminderSettings {
        var s = ReminderSettings(enabled: true, dailyCap: 3, pausedUntil: nil,
                                 quietStart: 22 * 60, quietEnd: 7 * 60, timeZoneID: zone.identifier)
        change(&s)
        return s
    }

    private func plan(_ fire: Date, resolvedAt: Date? = nil) -> ReminderPlan {
        ReminderPlan(outcomeId: UUID(), card: card, fireDate: fire, resolvedAt: resolvedAt)
    }

    func testFiresWhenTheActivityShouldBeOver() {
        // A gap starting later: from the gap start. A gap already under way: from now.
        XCTAssertEqual(ReminderRules.outcomeFireDate(gapStart: ny("14:00"), durationMin: 15, now: ny("10:00")), ny("14:20"))
        XCTAssertEqual(ReminderRules.outcomeFireDate(gapStart: ny("10:00"), durationMin: 15, now: ny("10:10")), ny("10:30"))
    }

    func testQuietHoursMoveTheReminderToWhenTheyEnd() {
        let s = settings()
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("21:59"), s), ny("21:59"))
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("22:30"), s), ny("07:00", day: 17))   // crosses midnight
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("06:00"), s), ny("07:00"))
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("07:00"), s), ny("07:00"))
        // a daytime window, and no quiet hours at all
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("13:15"), settings { $0.quietStart = 13 * 60; $0.quietEnd = 14 * 60 }), ny("14:00"))
        XCTAssertEqual(ReminderRules.outOfQuietHours(ny("23:00"), settings { $0.quietEnd = 22 * 60 }), ny("23:00"))
    }

    func testOffAndPausedAreSuppressed() {
        let p = plan(ny("15:00"))
        XCTAssertEqual(ReminderRules.decide([p], settings: settings { $0.enabled = false }, now: ny("12:00"))[p.id], .suppressed("off"))
        XCTAssertEqual(ReminderRules.decide([p], settings: settings { $0.pausedUntil = ny("16:00") }, now: ny("12:00"))[p.id], .suppressed("paused"))
        XCTAssertEqual(ReminderRules.decide([p], settings: settings { $0.pausedUntil = ny("14:00") }, now: ny("12:00"))[p.id], .fire(ny("15:00")))
    }

    func testDailyCapCountsRemindersAlreadyShown() {
        let shown = plan(ny("09:00"))                                    // fired earlier today, not logged yet
        let loggedFirst = plan(ny("11:00"), resolvedAt: ny("10:30"))     // logged before it fired: never shown
        let later = [plan(ny("13:00")), plan(ny("14:00")), plan(ny("15:00"))]
        let d = ReminderRules.decide([shown, loggedFirst] + later, settings: settings { $0.dailyCap = 3 }, now: ny("12:00"))
        XCTAssertEqual(d[later[0].id], .fire(ny("13:00")))
        XCTAssertEqual(d[later[1].id], .fire(ny("14:00")))
        XCTAssertEqual(d[later[2].id], .suppressed("daily_cap"))
        XCTAssertNil(d[shown.id], "already shown, nothing to schedule")
        XCTAssertNil(d[loggedFirst.id], "resolved, nothing to schedule")
    }

    func testCapIsPerDayAfterQuietHoursShift() {
        // Two reminders tonight in quiet hours move to tomorrow 7:00 and count toward tomorrow.
        let a = plan(ny("22:30")), b = plan(ny("23:30"))
        let d = ReminderRules.decide([a, b], settings: settings { $0.dailyCap = 1 }, now: ny("20:00"))
        XCTAssertEqual(d[a.id], .fire(ny("07:00", day: 17)))
        XCTAssertEqual(d[b.id], .suppressed("daily_cap"))
    }

    func testOldPlansArePruned() {
        let now = ny("12:00", day: 18)
        let old = plan(ny("09:00"), resolvedAt: ny("09:30"))
        let recent = plan(ny("13:00", day: 17))
        XCTAssertEqual(ReminderRules.pruned([old, recent], now: now).map(\.id), [recent.id])
    }

    func testSettingsComeFromTheProfile() {
        var p = ProfileRow(id: UUID())
        XCTAssertEqual(ReminderSettings(profile: p).enabled, true)          // on unless turned off
        XCTAssertEqual(ReminderSettings(profile: p).dailyCap, 3)
        p.remindersOn = false; p.reminderDailyCap = 2; p.quietStart = "23:00:00"; p.quietEnd = "06:30:00"
        let s = ReminderSettings(profile: p)
        XCTAssertEqual([s.enabled ? 1 : 0, s.dailyCap, s.quietStart, s.quietEnd], [0, 2, 23 * 60, 6 * 60 + 30])
    }

    func testSettingsUpdateAlwaysSendsThePause() throws {
        let update = ReminderSettingsUpdate(remindersOn: true, dailyCap: 3, pausedUntil: nil, quietStart: "22:00:00", quietEnd: "07:00:00")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as! [String: Any]
        XCTAssertTrue(json["reminders_paused_until"] is NSNull, "Resume must clear the pause, so null is sent")
    }

    // MARK: Free-time windows

    private func window(_ weekday: Int, _ clock: String, _ minutes: Int = 45) -> ReminderWindow {
        ReminderWindow(id: UUID(), weekday: weekday, startTime: clock, minutes: minutes)
    }

    func testWindowOccurrencesUseISOWeekdaysAndSkipThePast() {
        // Monday 16 Nov 2026, 12:00. Monday 10:00 has passed; Monday 14:00 and next Monday are 7 days out (excluded).
        let mon10 = window(1, "10:00:00"), mon14 = window(1, "14:00:00"), wed = window(3, "09:30:00"), sun = window(7, "18:00:00")
        let occ = ReminderRules.occurrences([mon10, mon14, wed, sun], settings: settings(), now: ny("12:00"))
        XCTAssertEqual(occ.map(\.start), [ny("14:00"), ny("09:30", day: 18), ny("18:00", day: 22)])
        XCTAssertEqual(occ.map(\.windowId), [mon14.id, wed.id, sun.id])
    }

    func testWindowInQuietHoursIsDroppedNotMoved() {
        let late = WindowOccurrence(windowId: UUID(), start: ny("22:30"), minutes: 30)
        let ok = WindowOccurrence(windowId: UUID(), start: ny("15:00"), minutes: 30)
        let d = ReminderRules.schedule(plans: [], windows: [late, ok], shownWindowFires: [], settings: settings(), now: ny("12:00"))
        XCTAssertEqual(d.windows[late.key], .suppressed("quiet_hours"))
        XCTAssertEqual(d.windows[ok.key], .fire(ny("15:00")))
    }

    func testOutcomeRemindersComeBeforeWindowsUnderTheCap() {
        // Cap 2: one nudge already shown this morning, one outcome reminder later, so the afternoon window is cut.
        let outcome = plan(ny("16:00"))
        let afternoon = WindowOccurrence(windowId: UUID(), start: ny("14:00"), minutes: 30)
        let tomorrow = WindowOccurrence(windowId: UUID(), start: ny("14:00", day: 17), minutes: 30)
        let d = ReminderRules.schedule(plans: [outcome], windows: [afternoon, tomorrow], shownWindowFires: [ny("09:00")],
                                       settings: settings { $0.dailyCap = 2 }, now: ny("12:00"))
        XCTAssertEqual(d.outcomes[outcome.id], .fire(ny("16:00")))
        XCTAssertEqual(d.windows[afternoon.key], .suppressed("daily_cap"))
        XCTAssertEqual(d.windows[tomorrow.key], .fire(ny("14:00", day: 17)))
    }

    func testWindowsRespectOffPauseAndThePendingLimit() {
        let w = WindowOccurrence(windowId: UUID(), start: ny("15:00"), minutes: 30)
        XCTAssertEqual(ReminderRules.schedule(plans: [], windows: [w], shownWindowFires: [], settings: settings { $0.enabled = false }, now: ny("12:00")).windows[w.key], .suppressed("off"))
        XCTAssertEqual(ReminderRules.schedule(plans: [], windows: [w], shownWindowFires: [], settings: settings { $0.pausedUntil = ny("18:00") }, now: ny("12:00")).windows[w.key], .suppressed("paused"))
        // 70 windows over the next days with a high cap: only the first maxPending are decided.
        let many = (0..<70).map { WindowOccurrence(windowId: UUID(), start: ny("12:00").addingTimeInterval(Double($0 + 1) * 60), minutes: 10) }
        let d = ReminderRules.schedule(plans: [], windows: many, shownWindowFires: [], settings: settings { $0.dailyCap = 100 }, now: ny("12:00"))
        XCTAssertEqual(d.windows.count, ReminderRules.maxPending)
    }

    func testWindowTapLeavesTheRestOfTheWindow() {
        let tap = WindowTap(windowId: UUID(), start: ny("14:00"), minutes: 45)
        XCTAssertEqual(WindowGapView.remaining(tap, now: ny("13:58")).minutes, 45)            // early: the whole window
        let late = WindowGapView.remaining(tap, now: ny("14:12"))                            // rounds up to 14:15
        XCTAssertEqual([late.start, Date(timeIntervalSince1970: Double(late.minutes))], [ny("14:15"), Date(timeIntervalSince1970: 30)])
        XCTAssertEqual(WindowGapView.remaining(tap, now: ny("15:00")).minutes, 0)
    }

    func testGapInsertCarriesItsOrigin() throws {
        let id = UUID()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            GapInsert(startTime: Date(), minutes: 30, energy: nil, origin: .windowReminder, windowId: id))) as! [String: Any]
        XCTAssertEqual(json["origin"] as? String, "window_reminder")
        XCTAssertEqual(json["window_id"] as? String, id.uuidString)
        let manual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GapInsert(startTime: Date(), minutes: 30))) as! [String: Any]
        XCTAssertEqual(manual["origin"] as? String, "manual")
        XCTAssertNil(manual["window_id"])
    }
}
