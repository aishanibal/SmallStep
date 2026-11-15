import XCTest
@testable import SmallStep

final class WeeklyProgressTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!

    private func activity(_ name: String, priority: Int, goal: Int?) -> ActivityRow {
        ActivityRow(id: UUID(), name: name, category: "Other", durationMin: 20, location: .anywhere, priority: priority, weeklyIntention: goal)
    }

    func testWeekStartsMondayInTheirTimeZone() {
        let f = ISO8601DateFormatter()
        // Sunday 22 Nov 2026 23:30 in New York is already Monday in UTC; the week is still the one starting Mon 16 Nov.
        let sundayNight = f.date(from: "2026-11-22T23:30:00-05:00")!
        XCTAssertEqual(WeeklyProgress.weekStart(sundayNight, timeZone: zone), f.date(from: "2026-11-16T00:00:00-05:00")!)
        let monday = f.date(from: "2026-11-23T00:10:00-05:00")!
        XCTAssertEqual(WeeklyProgress.weekStart(monday, timeZone: zone), f.date(from: "2026-11-23T00:00:00-05:00")!)
    }

    func testLinesShowGoalsCountsAndOtherIdeas() {
        let gym = activity("Gym", priority: 3, goal: 3)
        let steps = activity("Steps", priority: 2, goal: nil)
        let guitar = activity("Guitar", priority: 1, goal: 2)
        let pilates = activity("Pilates", priority: 2, goal: nil)          // nothing done, no goal: hidden
        let removed = UUID()
        let rows = [ProgressRow(activityId: gym.id, done: 4), ProgressRow(activityId: steps.id, done: 1),
                    ProgressRow(activityId: nil, done: 2), ProgressRow(activityId: removed, done: 1)]
        let lines = WeeklyProgress.lines(rows: rows, activities: [guitar, steps, gym, pilates])
        XCTAssertEqual(lines.map(\.title), ["Gym", "Steps", "Guitar", "Other ideas"])
        XCTAssertEqual(lines.map(\.summary), ["4 done · goal 3", "1 done", "0 of 2", "3 done"])
        XCTAssertEqual(lines.map(\.goalMet), [true, false, false, false])
    }

    func testDecodesTheFunctionResult() throws {
        let json = #"[{"activity_id":"11111111-1111-1111-1111-111111111111","done":2},{"activity_id":null,"done":1}]"#
        let rows = try JSONDecoder().decode([ProgressRow].self, from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.done), [2, 1])
        XCTAssertNil(rows[1].activityId)
    }
}
