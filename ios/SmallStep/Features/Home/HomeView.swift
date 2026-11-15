import SwiftUI

enum Route: Hashable {
    case gap
    case suggestions(SuggestionSet, minutes: Int, gapID: UUID, start: Date)
    case outcome(OutcomeContext)
    case activities
    case history
    case reminders
    case yourDay
    case freeWindow(WindowTap)
}

struct OutcomeContext: Hashable {
    /// `reminder*`: opened from a reminder (its body, Done, or Skip).
    enum Start { case chosen, followUp, reminderOpen, reminderDone, reminderSkip }
    let outcomeId: UUID
    let card: SuggestionCard
    let start: Start

    var fromReminder: Bool { [.reminderOpen, .reminderDone, .reminderSkip].contains(start) }
}

@MainActor @Observable
final class Navigator {
    var path: [Route] = []
    var notice: String?

    func goHome(notice: String? = nil) {
        path.removeAll()
        self.notice = notice
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var navigator = Navigator()
    @State private var showDeveloper = false
    private let router = ReminderRouter.shared

    var body: some View {
        NavigationStack(path: $navigator.path) {
            ScreenScroll {
                Text("SmallStep").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1.2) { showDeveloper = true }   // hidden developer screen

                if let notice = navigator.notice {
                    Text(notice).ssBodyText().softCard(tint: .ssBlueSoft).transition(.opacity)
                }

                if let pending = model.pending {
                    Button { navigator.path.append(.outcome(.init(outcomeId: pending.outcomeId, card: pending.card, start: .followUp))) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You chose “\(pending.card.title)”").font(.ssCardTitle).foregroundStyle(Color.ssText)
                            Text("Log how it went").ssSecondaryText()
                        }
                        .softCard(tint: .ssTaupeSoft)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Double tap to log how it went")
                }

                if let weekly = model.weekly { WeeklyCard(lines: weekly) }

                VStack(spacing: 8) {
                    Button("Get suggestions") { navigator.path.append(.gap) }.buttonStyle(PrimaryButtonStyle())
                    Button("Your activities") { navigator.path.append(.activities) }.buttonStyle(QuietButtonStyle())
                    Button("Your day") { navigator.path.append(.yourDay) }.buttonStyle(QuietButtonStyle())
                    Button("History") { navigator.path.append(.history) }.buttonStyle(QuietButtonStyle())
                    Button("Reminders") { navigator.path.append(.reminders) }.buttonStyle(QuietButtonStyle())
                    Button("Sign out") { Task { await model.signOut() } }.buttonStyle(QuietButtonStyle())
                }
            }
            .gentle(value: navigator.notice)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .gap: GapEntryView()
                case .suggestions(let result, let minutes, let gapID, let start):
                    SuggestionsView(result: result, minutes: minutes, gapID: gapID, gapStart: start)
                case .outcome(let context): OutcomeView(context: context)
                case .activities: ActivitiesManageView()
                case .history: HistoryView()
                case .reminders: RemindersView()
                case .yourDay: RhythmSetupView(onSaved: { navigator.goHome(notice: "Saved.") }).navigationBarTitleDisplayMode(.inline)
                case .freeWindow(let tap): WindowGapView(tap: tap)
                }
            }
        }
        .environment(navigator)
        .sheet(isPresented: $showDeveloper) { DeveloperView() }
        .task {
            await model.syncTimeZone()
            await model.refreshPending()
            await model.refreshWeekly()
        }
        .onChange(of: navigator.path.count) {
            Task {
                await model.refreshPending()
                if navigator.path.isEmpty { await model.refreshWeekly() }
            }
        }
        .task(id: router.tap) { await openReminder() }
        .task(id: router.windowTap) {
            guard let tap = router.windowTap else { return }
            router.windowTap = nil
            navigator.path = [.freeWindow(tap)]
        }
    }

    /// A reminder was tapped: open the logging screen for it, unless it was already logged.
    private func openReminder() async {
        guard let tap = router.tap else { return }
        router.tap = nil
        guard let backend = model.backend else { return }
        let card = NotificationScheduler.shared.plan(for: tap.outcomeId)?.card
            ?? (model.pending?.outcomeId == tap.outcomeId ? model.pending?.card : nil)
        guard let card, (try? await backend.outcomeIsOpen(tap.outcomeId)) == true else {
            NotificationScheduler.shared.resolve(tap.outcomeId)
            navigator.goHome(notice: "That one's already saved.")
            return
        }
        let start: OutcomeContext.Start = switch tap.action {
        case .open: .reminderOpen
        case .done: .reminderDone
        case .skip: .reminderSkip
        }
        navigator.path = [.outcome(.init(outcomeId: tap.outcomeId, card: card, start: start))]
    }
}

/// What was done this week. Counts only: no streaks, no missed days, nothing in red.
struct WeeklyCard: View {
    let lines: [ProgressLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").ssHeadingText().accessibilityAddTraits(.isHeader)
            if lines.allSatisfy({ $0.done == 0 }) {
                Text(lines.isEmpty ? "Things you finish will show up here." : "A fresh week. Things you finish will show up here.")
                    .ssSecondaryText()
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.title).ssBodyText()
                        Spacer(minLength: 12)
                        if line.goalMet {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.ssSage)
                                .accessibilityHidden(true)
                        }
                        Text(line.summary).ssSecondaryText().monospacedDigit()
                    }
                    if let goal = line.goal, goal > 0 {
                        ProgressView(value: Double(min(line.done, goal)), total: Double(goal))
                            .tint(Color.ssSage)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(line.title), \(line.summary)\(line.goalMet ? ", goal met" : "")")
            }
        }
        .softCard()
    }
}
