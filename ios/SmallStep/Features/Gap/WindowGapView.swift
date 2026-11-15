import SwiftUI

/// Opened from a free-time nudge. The gap is the rest of that window, so the student only picks energy.
struct WindowGapView: View {
    @Environment(AppModel.self) private var model
    @Environment(Navigator.self) private var navigator
    let tap: WindowTap

    @State private var energy: Int?
    @State private var busy = false
    @State private var message: String?

    /// The window from now (rounded up to 5 minutes) until it ends.
    static func remaining(_ tap: WindowTap, now: Date = Date()) -> (start: Date, minutes: Int) {
        let rounded = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
        let start = max(tap.start, rounded)
        let end = tap.start.addingTimeInterval(Double(tap.minutes) * 60)
        return (start, max(0, Int(end.timeIntervalSince(start) / 60)))
    }

    private var left: (start: Date, minutes: Int) { Self.remaining(tap) }
    private var tooLate: Bool { left.minutes < GapFinder.minMinutes }

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your free time").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                if tooLate {
                    Text("This free time is nearly over. You can still ask for ideas for another time.").ssBodyText()
                } else {
                    Text("\(left.minutes) minutes, until \(left.start.addingTimeInterval(Double(left.minutes) * 60).formatted(date: .omitted, time: .shortened)).")
                        .ssBodyText()
                }
            }

            if !tooLate {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Energy").ssHeadingText()
                    Text("Optional.").ssSecondaryText()
                    ChipGroup(options: [(1, "Low"), (2, "Okay"), (3, "Good")], selection: $energy, clearable: true)
                }
                .softCard()
            }

            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            VStack(spacing: 8) {
                if tooLate {
                    Button("Choose another time") { navigator.path = [.gap] }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(action: { Task { await go() } }) {
                        if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Get suggestions") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                }
                Button("Not now") { navigator.goHome() }.buttonStyle(QuietButtonStyle()).disabled(busy)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func go() async {
        let gap = left
        guard gap.minutes >= GapFinder.minMinutes else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let request = try await model.requestSuggestions(start: gap.start, minutes: gap.minutes, energy: energy,
                                                             origin: .windowReminder, windowID: tap.windowId)
            navigator.path.append(.suggestions(request.set, minutes: gap.minutes, gapID: request.gapID, start: gap.start))
        } catch BackendError.setupIncomplete {
            await model.refresh()
        } catch {
            message = "Couldn't load suggestions. Try again."
        }
    }
}
