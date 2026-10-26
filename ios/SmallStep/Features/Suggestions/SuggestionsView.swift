import SwiftUI

struct SuggestionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let minutes: Int
    /// The gap these cards were built for, so "Suggest something else" can ask again without a new gap.
    let gapID: UUID?

    @State private var result: SuggestionSet
    @State private var selected: UUID?
    @State private var showNone = false
    @State private var busy = false
    @State private var swapping = false
    @State private var message: String?

    init(result: SuggestionSet, minutes: Int, gapID: UUID? = nil) {
        self.minutes = minutes
        self.gapID = gapID
        _result = State(initialValue: result)
    }

    private var cards: [SuggestionCard] { result.cards.sorted { $0.position < $1.position } }

    private var heading: String {
        "Suggestions for \(minutes) minutes"
    }

    var body: some View {
        ScreenScroll {
            if cards.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nothing fits this time").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                    Text("It may be outside your waking hours or in your quiet hours.").ssBodyText()
                }
                Button("Back") { navigator.goHome() }.buttonStyle(PrimaryButtonStyle())
            } else {
                Text(heading).font(.ssHeading).foregroundStyle(Color.ssText).lineSpacing(6).accessibilityAddTraits(.isHeader)

                VStack(spacing: 16) {
                    ForEach(cards) { card in
                        Button { selected = card.id } label: { cardView(card) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(card.title). \(card.description). \(card.durationMin) minutes.")
                            .accessibilityAddTraits(selected == card.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .gentle(value: selected)

                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

                VStack(spacing: 8) {
                    Button(action: { Task { await choose() } }) {
                        if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Choose") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(selected == nil || busy || swapping)
                    if gapID != nil {
                        Button(action: { Task { await another() } }) {
                            if swapping { ProgressView().tint(Color.ssBlue) } else { Text("Suggest something else") }
                        }
                        .buttonStyle(QuietButtonStyle()).disabled(busy || swapping)
                    }
                    Button("None of these") { showNone = true }.buttonStyle(QuietButtonStyle()).disabled(busy || swapping)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNone) { NoneReasonSheet { reason in await none(reason) } }
    }

    private func cardView(_ card: SuggestionCard) -> some View {
        let isSelected = selected == card.id
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title).font(.ssCardTitle).foregroundStyle(Color.ssText)
                Text(card.description).ssBodyText()
                Text("\(card.durationMin) min").ssSecondaryText()
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(isSelected ? Color.ssSage : Color.ssTextSecondary)
                .accessibilityHidden(true)
        }
        .softCard(selected: isSelected)
    }

    private func choose() async {
        guard !busy, !swapping else { return }
        guard let backend = model.backend, let setID = result.setId, let id = selected,
              let card = cards.first(where: { $0.id == id }) else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let outcomeID = try await backend.chooseSuggestion(setID: setID, suggestionID: id)
            navigator.path.removeLast()
            navigator.path.append(.outcome(.init(outcomeId: outcomeID, card: card, start: .chosen)))
        } catch {
            message = "That didn't go through. Please try again."
        }
    }

    private func another() async {
        guard !swapping, let gapID, let setID = result.setId else { return }
        swapping = true
        message = nil
        selected = nil
        defer { swapping = false }
        do {
            result = try await model.anotherSuggestions(setID: setID, gapID: gapID)
        } catch {
            message = "Couldn't load new suggestions. Try again."
        }
    }

    private func none(_ reason: String) async {
        guard let backend = model.backend, let setID = result.setId else { return }
        do {
            try await backend.chooseNone(setID: setID, reason: reason)
            showNone = false
            navigator.goHome(notice: "Saved.")
        } catch {
            showNone = false
            message = "That didn't go through. Please try again."
        }
    }
}

/// One tap on a reason records "None of these" and closes the sheet.
struct NoneReasonSheet: View {
    let onPick: (String) async -> Void
    @State private var busy = false

    private let reasons: [(String, String)] = [
        ("not_now", "Not now"), ("not_interested", "Not interested"),
        ("wrong_length", "Wrong length"), ("wrong_place", "Wrong place"), ("something_else", "Something else"),
    ]

    var body: some View {
        ScreenScroll {
            Text("Why none of these?").ssHeadingText()
            FlowLayout {
                ForEach(reasons, id: \.0) { reason in
                    Chip(title: reason.1, selected: false) {
                        guard !busy else { return }
                        busy = true
                        Task { await onPick(reason.0); busy = false }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
