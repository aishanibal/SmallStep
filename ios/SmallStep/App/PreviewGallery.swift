#if DEBUG
import SwiftUI

/// Debug-only: `-preview <name>` on launch shows one screen with sample data, for screenshots.
/// Compiled out of release builds.
struct PreviewGallery: View {
    let name: String
    @State private var model = AppModel(backend: nil, defaults: UserDefaults(suiteName: "preview")!)
    @State private var navigator = Navigator()

    private static let cards = [
        SuggestionCard(id: UUID(), title: "Gentle stretch", description: "A short stretch could ease your afternoon.", durationMin: 15, position: 0),
        SuggestionCard(id: UUID(), title: "Slow breathing", description: "Breathe in for four, out for six, a few times.", durationMin: 5, position: 1),
        SuggestionCard(id: UUID(), title: "Morning walk", description: "A movement activity from your list.", durationMin: 10, position: 2),
    ]

    private static let sampleImport: CalendarImport = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func gap(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, day: Int = 0) -> FreeGap {
            let base = cal.date(byAdding: .day, value: day, to: today)!
            return FreeGap(start: cal.date(bySettingHour: h1, minute: m1, second: 0, of: base)!,
                           end: cal.date(bySettingHour: h2, minute: m2, second: 0, of: base)!)
        }
        return CalendarImport(days: [
            CalendarDay(date: today, gaps: [gap(10, 0, 11, 15), gap(14, 30, 15, 0)]),
            CalendarDay(date: cal.date(byAdding: .day, value: 1, to: today)!, gaps: [gap(8, 0, 12, 0, day: 1)]),
        ], notes: [ICSNote.allDayIgnored.rawValue])
    }()

    var body: some View {
        Group {
            switch name {
            case "consent": ConsentView()
            case "login": LoginView()
            case "activities": ActivitiesSetupView()
            case "editor":
                ActivityEditorView(draft: { var d = ActivityDraft(); d.name = "Evening walk"; d.weeklyIntention = 3; return d }(), isNew: false, onSave: { _ in }, onDelete: {})
            case "rhythm": RhythmSetupView()
            case "home": HomeView()
            case "gap": NavigationStack { GapEntryView() }
            case "suggestions": NavigationStack { SuggestionsView(result: SuggestionSet(setId: UUID(), cards: Self.cards), minutes: 20) }
            case "none": NoneReasonSheet { _ in }
            case "dev": DeveloperView()
            case "calendar": NavigationStack { CalendarGapsView(imported: Self.sampleImport) }
            case "outcome-start": NavigationStack { OutcomeView(context: .init(outcomeId: UUID(), card: Self.cards[0], start: .chosen)) }
            case "outcome-doing": NavigationStack { OutcomeView(context: .init(outcomeId: UUID(), card: Self.cards[0], start: .followUp)) }
            default: Text("unknown preview")
            }
        }
        .environment(model)
        .environment(navigator)
        .tint(Color.ssSage)
        .background(Color.ssBackground)
    }
}
#endif
