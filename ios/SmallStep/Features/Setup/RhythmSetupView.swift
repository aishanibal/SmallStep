import SwiftUI
import UniformTypeIdentifiers

struct RhythmSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var wake = Rhythm.date(minutes: 7 * 60)
    @State private var bedtime = Rhythm.date(minutes: 23 * 60)
    @State private var breakfast = Rhythm.date(minutes: 8 * 60)
    @State private var lunch = Rhythm.date(minutes: 12 * 60 + 30)
    @State private var dinner = Rhythm.date(minutes: 19 * 60)
    @State private var quietStart = Rhythm.date(minutes: 22 * 60)
    @State private var quietEnd = Rhythm.date(minutes: 7 * 60)
    @State private var statement = ""
    @State private var busy = false
    @State private var message: String?
    @State private var showImporter = false
    @State private var calendarStatus: String? = CalendarStore.load().map { CalendarStore.status(for: $0) }
    @State private var calendarNotes: [String] = CalendarStore.load()?.notes ?? []

    var body: some View {
        ScreenScroll {
            StepProgress(step: 2, of: 2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Your day").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("Suggestions only happen while you're awake and outside quiet hours.").ssBodyText()
            }

            VStack(spacing: 4) {
                row("I wake up", $wake)
                row("I go to bed", $bedtime)
                row("Breakfast", $breakfast)
                row("Lunch", $lunch)
                row("Dinner", $dinner)
            }
            .softCard()

            VStack(alignment: .leading, spacing: 4) {
                Text("Quiet hours").ssHeadingText()
                Text("No suggestions during these.").ssSecondaryText().padding(.bottom, 8)
                row("From", $quietStart)
                row("Until", $quietEnd)
            }
            .softCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("What does wellness mean to you?").ssHeadingText()
                Text("Optional.").ssSecondaryText()
                TextField("In your own words", text: $statement, axis: .vertical)
                    .lineLimit(2...4).font(.ssBody).frame(minHeight: 44)
                    .onChange(of: statement) { if statement.count > 300 { statement = String(statement.prefix(300)) } }
                Divider().overlay(Color.ssHairline)
            }
            .softCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar").ssHeadingText()
                Text("Optional. Upload an .ics file to find your free time. It's read on this phone and event names aren't kept.")
                    .ssSecondaryText()
                if let calendarStatus { Text(calendarStatus).ssBodyText() }
                ForEach(calendarNotes, id: \.self) { Text($0).ssSecondaryText() }
                Button(calendarStatus == nil ? "Upload calendar file" : "Replace calendar file") { showImporter = true }
                    .buttonStyle(QuietButtonStyle())
            }
            .softCard()

            Text("Time zone: \(TimeZone.current.identifier), from your phone.").ssSecondaryText()

            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            Button(action: { Task { await save() } }) {
                if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Finish setup") }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(busy)
        }
        .onAppear {
            model.markSetupStarted()
            if let p = model.profile, p.hasRhythm { load(p) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType.calendarEvent, UTType(filenameExtension: "ics")].compactMap { $0 }) { result in
            guard case .success(let url) = result else { return }
            Task {
                calendarStatus = await CalendarStore.importFile(url, timeZone: .current)
                calendarNotes = CalendarStore.load()?.notes ?? []
            }
        }
    }

    private func row(_ title: String, _ value: Binding<Date>) -> some View {
        HStack {
            Text(title).ssBodyText()
            Spacer()
            DatePicker(title, selection: value, displayedComponents: .hourAndMinute).labelsHidden()
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private func load(_ p: ProfileRow) {
        func d(_ s: String?, _ fallback: Date) -> Date { Rhythm.minutes(fromClock: s).map { Rhythm.date(minutes: $0) } ?? fallback }
        wake = d(p.wake, wake); bedtime = d(p.bedtime, bedtime); breakfast = d(p.breakfast, breakfast)
        lunch = d(p.lunch, lunch); dinner = d(p.dinner, dinner)
        quietStart = d(p.quietStart, quietStart); quietEnd = d(p.quietEnd, quietEnd)
        statement = p.wellnessStatement ?? ""
    }

    private func save() async {
        busy = true; message = nil
        defer { busy = false }
        func s(_ d: Date) -> String { Rhythm.clockString(minutes: Rhythm.minutes(from: d)) }
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = ProfileUpdate(
            wake: s(wake), bedtime: s(bedtime), breakfast: s(breakfast), lunch: s(lunch), dinner: s(dinner),
            quietStart: s(quietStart), quietEnd: s(quietEnd), wellnessStatement: trimmed.isEmpty ? nil : trimmed
        )
        do { try await model.saveRhythm(update) }
        catch { message = "That didn't save. Please try again." }
    }
}
