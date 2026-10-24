import SwiftUI

/// Hidden screen (long press the title on Home). Shows what Source A is being told, so you can check
/// that the history summary changes as outcomes are logged. Not part of the participant experience.
struct DeveloperView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var info: DevInfo?
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("For the study team. Participants don't need this.").ssSecondaryText()

                if loading && info == nil { ProgressView().tint(Color.ssSage) }
                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

                if let info {
                    block("History summary, as of now", info.historySummaryNow.map { "• \($0)" }.joined(separator: "\n"))

                    if let last = info.last {
                        block("Last Source A request",
                              "Sent \(Self.display(last.setCreatedAt))\n" +
                              "Result: \(last.status == "model" ? "model answered" : "rule-based fallback")" +
                              (last.model.map { "\nModel: \($0)" } ?? "") +
                              (last.error.map { "\nError: \($0)" } ?? ""))
                        if let used = last.historySummaryUsed { block("History summary used in that request", used) }
                        if let prompt = last.prompt { block("Prompt sent to the model", prompt) }
                    } else {
                        block("Last Source A request", "None yet. Ask for ideas once, then come back.")
                    }
                }

                Button(action: { Task { await load() } }) {
                    if loading { ProgressView().tint(Color.ssOnSage) } else { Text("Refresh") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(loading)
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
        }
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).ssHeadingText()
            Text(text)
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Color.ssText).lineSpacing(4)
                .textSelection(.enabled)
        }
        .softCard()
    }

    private static func display(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: iso) }()
        return date?.formatted(date: .abbreviated, time: .standard) ?? iso
    }

    private func load() async {
        guard let backend = model.backend else { return }
        loading = true; message = nil
        defer { loading = false }
        do { info = try await backend.devInfo() }
        catch { message = "Couldn't load developer info: \(error.localizedDescription)" }
    }
}
