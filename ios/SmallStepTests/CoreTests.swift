import XCTest
@testable import SmallStep

final class ParticipantCodeTests: XCTestCase {
    func testNormalizesAndValidates() {
        XCTAssertEqual(ParticipantCode.normalized("  Maple-17 "), "maple-17")
        XCTAssertEqual(ParticipantCode.normalized("a_b-9"), "a_b-9")
        XCTAssertNil(ParticipantCode.normalized("ab"))                       // too short
        XCTAssertNil(ParticipantCode.normalized("has space"))
        XCTAssertNil(ParticipantCode.normalized("name@mail.com"))            // no personal email addresses
        XCTAssertNil(ParticipantCode.normalized(String(repeating: "a", count: 25)))
    }

    func testSyntheticEmail() {
        XCTAssertEqual(ParticipantCode.email(for: "maple-17", domain: "study.example"), "maple-17@study.example")
    }
}

final class RhythmTests: XCTestCase {
    func testClockStrings() {
        XCTAssertEqual(Rhythm.clockString(minutes: 450), "07:30:00")
        XCTAssertEqual(Rhythm.clockString(minutes: 23 * 60 + 5), "23:05:00")
        XCTAssertEqual(Rhythm.minutes(fromClock: "07:30:00"), 450)
        XCTAssertEqual(Rhythm.minutes(fromClock: "07:30"), 450)
        XCTAssertNil(Rhythm.minutes(fromClock: nil))
        XCTAssertNil(Rhythm.minutes(fromClock: "25:00:00"))
    }

    func testDatePickerRoundTrip() {
        for minutes in [0, 7 * 60, 12 * 60 + 30, 23 * 60 + 59] {
            XCTAssertEqual(Rhythm.minutes(from: Rhythm.date(minutes: minutes)), minutes)
        }
    }
}

final class ModelTests: XCTestCase {
    /// What the `suggest` function returns. The app must decode it and never see a source.
    func testDecodesSuggestResponse() throws {
        let json = """
        {"set_id":"11111111-1111-1111-1111-111111111111","cards":[
          {"id":"22222222-2222-2222-2222-222222222222","title":"Gentle stretch","description":"A yoga activity from your list.","duration_min":15,"position":0},
          {"id":"33333333-3333-3333-3333-333333333333","title":"Slow breathing","description":"Breathe in for four.","duration_min":5,"position":1}]}
        """.data(using: .utf8)!
        let set = try JSONDecoder().decode(SuggestionSet.self, from: json)
        XCTAssertEqual(set.cards.count, 2)
        XCTAssertEqual(set.cards[0].durationMin, 15)
        XCTAssertNotNil(set.setId)
    }

    func testEmptyResultHasNoSetID() throws {
        let set = try JSONDecoder().decode(SuggestionSet.self, from: #"{"set_id":null,"cards":[]}"#.data(using: .utf8)!)
        XCTAssertNil(set.setId)
        XCTAssertTrue(set.cards.isEmpty)
    }

    func testCardModelHasNoSourceFields() {
        let card = SuggestionCard(id: UUID(), title: "t", description: "d", durationMin: 5, position: 0)
        let names = Mirror(reflecting: card).children.compactMap(\.label)
        XCTAssertEqual(Set(names), ["id", "title", "description", "durationMin", "position"])
    }

    func testWheneverIntentionEncodesAsNull() throws {
        var draft = ActivityDraft(); draft.name = "Walk"; draft.weeklyIntention = nil
        let data = try JSONEncoder().encode(draft.write)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(object["weekly_intention"] is NSNull, "a nil intention must clear the column")
        XCTAssertEqual(object["duration_min"] as? Int, 15)
    }

    func testDraftNormalisesFields() {
        var draft = ActivityDraft()
        draft.name = "  Walk "; draft.category = " Movement "; draft.durationMin = 20
        XCTAssertEqual(draft.write.name, "Walk")
        XCTAssertEqual(draft.write.category, "movement")
        XCTAssertEqual(draft.write.durationMin, 20)
        XCTAssertEqual(draft.summary, "Movement · 20 min · anywhere")
        XCTAssertTrue(draft.isValid)
        draft.name = "   "
        XCTAssertFalse(draft.isValid)
    }

    func testProfileUpdateOmitsNilFields() throws {
        let data = try JSONEncoder().encode(ProfileUpdate(wake: "07:00:00"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["wake"])
    }

    func testProfileRhythmCompleteness() {
        var p = ProfileRow(id: UUID())
        XCTAssertFalse(p.hasRhythm)
        p.wake = "07:00:00"; p.bedtime = "23:00:00"; p.breakfast = "08:00:00"; p.lunch = "12:30:00"
        p.dinner = "19:00:00"; p.quietStart = "22:00:00"; p.quietEnd = "07:00:00"
        XCTAssertFalse(p.hasRhythm, "timezone still missing")
        p.timezone = "America/New_York"
        XCTAssertTrue(p.hasRhythm)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testWithoutSettingsShowsConfigScreen() async {
        let model = AppModel(backend: nil, defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        await model.start()
        XCTAssertEqual(model.stage, .configMissing)
    }
}

final class DevInfoTests: XCTestCase {
    /// functions.invoke decodes with a plain JSONDecoder, so the model must not need a date strategy.
    func testDecodesDevInfoWithAPlainDecoder() throws {
        let json = """
        {"history_summary_now":["Not suggested recently: Walk (never)."],
         "last":{"set_created_at":"2026-03-10T14:00:00.123+00:00","status":"model","error":null,"model":"m","prompt":"You help one person","history_summary_used":"x"}}
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(DevInfo.self, from: json)
        XCTAssertEqual(info.historySummaryNow.count, 1)
        XCTAssertEqual(info.last?.status, "model")
        XCTAssertNil(try JSONDecoder().decode(DevInfo.self, from: #"{"history_summary_now":[],"last":null}"#.data(using: .utf8)!).last)
    }
}

final class ActivityDraftIdentityTests: XCTestCase {
    /// Drafts that haven't been saved yet have no database id. SwiftUI lists and sheets key on `id`,
    /// so unsaved drafts must still be distinct from each other or they overwrite one another on screen.
    func testUnsavedDraftsAreDistinct() {
        var a = ActivityDraft(), b = ActivityDraft(), c = ActivityDraft()
        a.name = "Walk"; b.name = "Stretch"; c.name = "Breathe"
        XCTAssertEqual(Set([a.id, b.id, c.id]).count, 3)
    }
}
