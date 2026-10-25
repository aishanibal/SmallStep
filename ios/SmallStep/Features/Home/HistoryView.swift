import SwiftUI

/// What this participant has already logged. The suggestion source is never shown.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [HistoryEntry] = []
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("History").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("What you have chosen and how it went.").ssBodyText()
            }

            if let message {
                Text(message).ssBodyText().softCard(tint: .ssTaupeSoft)
            } else if loaded && entries.isEmpty {
                Text("Nothing logged yet.").ssBodyText().softCard()
            } else {
                VStack(spacing: 16) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title).font(.ssCardTitle).foregroundStyle(Color.ssText)
                            Text(line(for: entry)).ssSecondaryText()
                        }
                        .softCard()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func line(for entry: HistoryEntry) -> String {
        let when = entry.at.formatted(date: .abbreviated, time: .shortened)
        if let detail = entry.detail, !detail.isEmpty { return "\(entry.status) · \(detail) · \(when)" }
        return "\(entry.status) · \(when)"
    }

    private func load() async {
        do {
            entries = try await model.loadHistory()
            message = nil
        } catch {
            message = "History didn't load. Please try again."
        }
        loaded = true
    }
}
