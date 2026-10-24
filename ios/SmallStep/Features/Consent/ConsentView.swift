import SwiftUI

struct ConsentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to SmallStep").font(.ssTitle).foregroundStyle(Color.ssText)
                    .accessibilityAddTraits(.isHeader)
                Text("Before you start:").ssBodyText()
            }

            if model.consentDeclined {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Okay.").ssHeadingText()
                    Text("Nothing has been recorded. You can close the app.").ssBodyText()
                    Button("Look again") { model.consentDeclined = false }.buttonStyle(QuietButtonStyle())
                }
                .softCard()
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    // PLACEHOLDER TEXT: replace with the approved consent wording before real participants use the app.
                    Text("[Placeholder consent text. The study team will replace this.]")
                        .ssSecondaryText()
                    point("doc.text", "This app is part of a class study (CS 4261). What you do in the app is recorded for that study.")
                    point("icloud", "Your answers and activity are stored in the cloud, under a code instead of your name.")
                    point("sparkles", "To create ideas, a summary of your free time, activity names and wellness line is processed by an LLM provider. Calendar event titles are never sent.")
                    point("hand.raised", "Taking part is up to you, and skipping any idea is always fine.")
                }
                .softCard()

                VStack(spacing: 8) {
                    Button("I agree") { Task { await model.acceptConsent() } }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("I'd rather not") { model.consentDeclined = true }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .fadeIn()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.ssBlue).frame(width: 30).accessibilityHidden(true)
            Text(text).ssBodyText()
        }
        .accessibilityElement(children: .combine)
    }
}
