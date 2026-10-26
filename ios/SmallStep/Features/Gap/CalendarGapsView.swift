import SwiftUI

/// Free gaps found in an imported calendar file. Pick one to get ideas for it.
struct CalendarGapsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let imported: CalendarImport
    var onUseNow: (() -> Void)?

    @State private var selected: FreeGap?
    @State private var energy: Int?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Free time").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("From your calendar. Pick one.").ssBodyText()
            }

            if imported.isEmpty {
                Text("No free time of 10+ minutes in your waking hours over the next 3 days.")
                    .ssBodyText().softCard()
            } else {
                ForEach(imported.days.filter { !$0.gaps.isEmpty }) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(dayTitle(day.date)).ssHeadingText()
                        ForEach(day.gaps) { gap in
                            Button { selected = gap } label: { gapRow(gap) }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(timeRange(gap)), \(gap.minutes) minutes")
                                .accessibilityAddTraits(selected == gap ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
                .gentle(value: selected)

                VStack(alignment: .leading, spacing: 12) {
                    Text("How's your energy?").ssHeadingText()
                    Text("Optional.").ssSecondaryText()
                    ChipGroup(options: [(1, "Low"), (2, "Okay"), (3, "Good")], selection: $energy, clearable: true)
                }
                .softCard()
            }

            ForEach(imported.notes, id: \.self) { note in Text(note).ssSecondaryText() }
            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            if !imported.isEmpty {
                Button(action: { Task { await go() } }) {
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Get suggestions") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(selected == nil || busy)
            }
            if let onUseNow {
                Button("Use right now instead", action: onUseNow).buttonStyle(QuietButtonStyle()).disabled(busy)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func gapRow(_ gap: FreeGap) -> some View {
        let isSelected = selected == gap
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange(gap)).font(.ssCardTitle).foregroundStyle(Color.ssText)
                Text(durationText(gap.minutes)).ssSecondaryText()
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(isSelected ? Color.ssSage : Color.ssTextSecondary).accessibilityHidden(true)
        }
        .softCard(selected: isSelected)
    }

    private var timeZone: TimeZone { model.profile?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current }

    private func timeRange(_ gap: FreeGap) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; f.timeZone = timeZone
        return "\(f.string(from: gap.start)) – \(f.string(from: gap.end))"
    }

    private func durationText(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min") : "\(minutes) min"
    }

    private func dayTitle(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; f.timeZone = timeZone
        return f.string(from: date)
    }

    private func go() async {
        guard let gap = selected else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let request = try await model.requestSuggestions(start: gap.start, minutes: gap.minutes, energy: energy)
            navigator.path.append(.suggestions(request.set, minutes: min(gap.minutes, GapFinder.maxMinutes), gapID: request.gapID))
        } catch BackendError.setupIncomplete {
            await model.refresh()
        } catch {
            message = "Couldn't load suggestions. Try again."
        }
    }
}
