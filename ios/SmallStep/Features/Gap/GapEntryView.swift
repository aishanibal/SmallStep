import SwiftUI

/// With a calendar uploaded: pick one of its free gaps. Without one: starting now, pick the minutes.
struct GapEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    @State private var calendar: CalendarImport?
    @State private var useCalendar = true
    @State private var minutes = 20
    @State private var energy: Int?
    @State private var busy = false
    @State private var message: String?

    private let quickMinutes = [10, 15, 20, 30, 45, 60]

    var body: some View {
        Group {
            if useCalendar, let calendar {
                CalendarGapsView(imported: calendar, onUseNow: { useCalendar = false })
            } else {
                nowForm
            }
        }
        .task {
            if let profile = model.profile, let saved = CalendarStore.load() {
                calendar = GapFinder.upcoming(busy: saved.busy, notes: saved.notes, profile: profile)
            }
        }
    }

    private var nowForm: some View {
        ScreenScroll {
            Text("Free time").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                Text("Starting now, how many minutes?").ssHeadingText()
                ChipGroup(options: quickMinutes.map { ($0, "\($0) min") },
                          selection: Binding(get: { minutes }, set: { if let v = $0 { minutes = v } }))
                Stepper(value: $minutes, in: 5...GapFinder.maxMinutes, step: 5) { Text("\(minutes) minutes").ssBodyText() }
            }
            .softCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Energy").ssHeadingText()
                Text("Optional.").ssSecondaryText()
                ChipGroup(options: [(1, "Low"), (2, "Okay"), (3, "Good")], selection: $energy, clearable: true)
            }
            .softCard()

            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            VStack(spacing: 8) {
                Button(action: { Task { await go() } }) {
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Get suggestions") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                if calendar != nil {
                    Button("Use my calendar instead") { useCalendar = true }.buttonStyle(QuietButtonStyle()).disabled(busy)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func go() async {
        let now = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
        busy = true; message = nil
        defer { busy = false }
        do {
            let set = try await model.requestSuggestions(start: now, minutes: minutes, energy: energy)
            navigator.path.append(.suggestions(set, minutes: minutes))
        } catch BackendError.setupIncomplete {
            await model.refresh()
        } catch {
            message = "Couldn't load suggestions. Try again."
        }
    }
}
