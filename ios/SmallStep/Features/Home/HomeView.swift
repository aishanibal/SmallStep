import SwiftUI

enum Route: Hashable {
    case gap
    case suggestions(SuggestionSet, minutes: Int)
    case outcome(OutcomeContext)
    case activities
    case history
}

struct OutcomeContext: Hashable {
    enum Start { case chosen, followUp }
    let outcomeId: UUID
    let card: SuggestionCard
    let start: Start
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

                VStack(spacing: 8) {
                    Button("Get suggestions") { navigator.path.append(.gap) }.buttonStyle(PrimaryButtonStyle())
                    Button("Your activities") { navigator.path.append(.activities) }.buttonStyle(QuietButtonStyle())
                    Button("History") { navigator.path.append(.history) }.buttonStyle(QuietButtonStyle())
                    Button("Sign out") { Task { await model.signOut() } }.buttonStyle(QuietButtonStyle())
                }
            }
            .gentle(value: navigator.notice)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .gap: GapEntryView()
                case .suggestions(let result, let minutes): SuggestionsView(result: result, minutes: minutes)
                case .outcome(let context): OutcomeView(context: context)
                case .activities: ActivitiesManageView()
                case .history: HistoryView()
                }
            }
        }
        .environment(navigator)
        .sheet(isPresented: $showDeveloper) { DeveloperView() }
        .task {
            await model.syncTimeZone()
            await model.refreshPending()
        }
        .onChange(of: navigator.path.count) { Task { await model.refreshPending() } }
    }
}
