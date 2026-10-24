import SwiftUI

struct OutcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let context: OutcomeContext

    private enum Step { case start, doing, skipReason, rating }
    @State private var step: Step
    @State private var rating: Int?
    @State private var busy = false
    @State private var message: String?

    init(context: OutcomeContext) {
        self.context = context
        _step = State(initialValue: context.start == .chosen ? .start : .doing)
    }

    private let skipReasons: [(String, String)] = [
        ("no_energy", "No energy"), ("ran_out_of_time", "Ran out of time"),
        ("changed_my_mind", "Changed my mind"), ("wrong_place", "Wrong place"), ("something_else", "Something else"),
    ]

    var body: some View {
        ScreenScroll {
            switch step {
            case .start:
                Text("Your choice").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                summary
                Button("Start") { step = .doing }.buttonStyle(PrimaryButtonStyle())
                Button("Not now") { navigator.goHome() }.buttonStyle(QuietButtonStyle())

            case .doing:
                Text(context.start == .chosen ? "In progress" : "How did it go?")
                    .font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                summary
                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }
                VStack(spacing: 8) {
                    Button("Done") { Task { await finish(completed: true) } }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    Button("Skip") { step = .skipReason }.buttonStyle(QuietButtonStyle()).disabled(busy)
                }

            case .skipReason:
                Text("What got in the way?").font(.ssHeading).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }
                FlowLayout {
                    ForEach(skipReasons, id: \.0) { reason in
                        Chip(title: reason.1, selected: false) { Task { await finish(completed: false, reason: reason.0) } }
                    }
                }

            case .rating:
                Text("How well did it fit?").font(.ssHeading).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout {
                        ForEach(1...5, id: \.self) { n in
                            Chip(title: "\(n)", selected: rating == n) { rating = n }
                                .accessibilityLabel("\(n) out of 5")
                        }
                    }
                    HStack {
                        Text("1 · Poor fit").ssSecondaryText()
                        Spacer()
                        Text("5 · Great fit").ssSecondaryText()
                    }
                }
                .gentle(value: rating)
                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }
                VStack(spacing: 8) {
                    Button("Save") { Task { await saveRating() } }.buttonStyle(PrimaryButtonStyle()).disabled(rating == nil || busy)
                    Button("Skip rating") { Task { await close() } }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .gentle(value: step)
        .navigationBarBackButtonHidden(step != .start && step != .doing)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.card.title).font(.ssCardTitle).foregroundStyle(Color.ssText)
            Text(context.card.description).ssBodyText()
            Text("\(context.card.durationMin) min").ssSecondaryText()
        }
        .softCard()
        .accessibilityElement(children: .combine)
    }

    private func finish(completed: Bool, reason: String? = nil) async {
        guard let backend = model.backend else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await backend.updateOutcome(context.outcomeId, OutcomeUpdate(completed: completed, skipReason: reason))
            if completed { Haptics.soft() }
            step = .rating
        } catch {
            message = "That didn't save. Please try again."
        }
    }

    private func saveRating() async {
        guard let backend = model.backend, let rating else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await backend.updateOutcome(context.outcomeId, OutcomeUpdate(fitRating: rating))
            await close()
        } catch {
            message = "That didn't save. Please try again."
        }
    }

    private func close() async {
        await model.refreshPending()
        navigator.goHome(notice: "Saved.")
    }
}
