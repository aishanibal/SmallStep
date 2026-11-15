import SwiftUI
import UserNotifications

/// Reminder controls: on/off, a daily limit, usual free times, quiet hours (shared with suggestions), and pause.
struct RemindersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var enabled = true
    @State private var dailyCap = ReminderSettings.defaultCap
    @State private var quietStart = Rhythm.date(minutes: 22 * 60)
    @State private var quietEnd = Rhythm.date(minutes: 7 * 60)
    @State private var pausedUntil: Date?
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var busy = false
    @State private var message: String?
    @State private var addingWindow = false
    @State private var windowMessage: String?

    static let capRange = 1...5

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reminders").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("SmallStep can remind you to mark what you picked as done or skipped, and nudge you when one of your usual free times starts.")
                    .ssBodyText()
            }

            if permission == .denied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for SmallStep in Settings, so reminders can't show.").ssBodyText()
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .softCard(tint: .ssTaupeSoft)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enabled) { Text("Send reminders").ssBodyText() }
                    .tint(Color.ssSage).frame(minHeight: 44)
                if enabled {
                    Divider().overlay(Color.ssHairline)
                    Stepper(value: $dailyCap, in: Self.capRange) {
                        Text("At most \(dailyCap) a day").ssBodyText()
                    }
                    .frame(minHeight: 44)
                }
            }
            .softCard()
            .gentle(value: enabled)

            windowsCard

            VStack(alignment: .leading, spacing: 4) {
                Text("Quiet hours").ssHeadingText()
                Text("No reminders or suggestions during these. A reminder due then waits until they end.")
                    .ssSecondaryText().padding(.bottom, 8)
                row("From", $quietStart)
                row("Until", $quietEnd)
            }
            .softCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Pause").ssHeadingText()
                if let pausedUntil, pausedUntil > Date() {
                    Text("Paused until \(pausedUntil.formatted(date: .abbreviated, time: .shortened)).").ssBodyText()
                    Button("Resume reminders") { Task { await save(pausedUntil: nil) } }
                        .buttonStyle(QuietButtonStyle()).disabled(busy)
                } else {
                    Text("Take a break without turning reminders off.").ssSecondaryText()
                    Button("Pause for a day") { Task { await save(pausedUntil: Date().addingTimeInterval(86_400)) } }
                        .buttonStyle(QuietButtonStyle()).disabled(busy)
                    Button("Pause for a week") { Task { await save(pausedUntil: Date().addingTimeInterval(7 * 86_400)) } }
                        .buttonStyle(QuietButtonStyle()).disabled(busy)
                }
            }
            .softCard()

            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            Button(action: { Task { await save(pausedUntil: pausedUntil) } }) {
                if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Save") }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(busy)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingWindow) { AddWindowSheet() }
        .onAppear(perform: load)
        .task { permission = await NotificationScheduler.shared.authorization() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { permission = await NotificationScheduler.shared.authorization() } }
        }
    }

    private var windowsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usual free times").ssHeadingText()
            Text("Get a nudge when one starts. No calendar needed.").ssSecondaryText()
            ForEach(model.windows) { window in
                HStack {
                    Text(Self.describe(window)).ssBodyText()
                    Spacer()
                    Button { Task { await remove(window) } } label: {
                        Image(systemName: "minus.circle").font(.title3).foregroundStyle(Color.ssTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove \(Self.describe(window))")
                }
            }
            if let windowMessage { Text(windowMessage).ssSecondaryText() }
            Button("Add a free time") { addingWindow = true }.buttonStyle(QuietButtonStyle())
        }
        .softCard()
    }

    static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func describe(_ w: ReminderWindow) -> String {
        let day = weekdayNames[max(0, min(6, w.weekday - 1))]
        return "\(day) · \(Rhythm.date(minutes: w.startMinute).formatted(date: .omitted, time: .shortened)) · \(w.minutes) min"
    }

    private func remove(_ window: ReminderWindow) async {
        windowMessage = nil
        do { try await model.removeWindow(window) } catch { windowMessage = "That didn't save. Please try again." }
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

    private func load() {
        let s = model.reminderSettings
        enabled = s.enabled
        dailyCap = min(max(s.dailyCap, Self.capRange.lowerBound), Self.capRange.upperBound)
        quietStart = Rhythm.date(minutes: s.quietStart)
        quietEnd = Rhythm.date(minutes: s.quietEnd)
        pausedUntil = s.pausedUntil
    }

    private func save(pausedUntil newPause: Date?) async {
        busy = true; message = nil
        defer { busy = false }
        func clock(_ d: Date) -> String { Rhythm.clockString(minutes: Rhythm.minutes(from: d)) }
        let update = ReminderSettingsUpdate(
            remindersOn: enabled, dailyCap: dailyCap, pausedUntil: newPause,
            quietStart: clock(quietStart), quietEnd: clock(quietEnd))
        do {
            try await model.saveReminderSettings(update)
            pausedUntil = newPause
            permission = await NotificationScheduler.shared.authorization()
            message = "Saved."
        } catch {
            message = "That didn't save. Please try again."
        }
    }
}

/// Add one free time on one or more weekdays.
struct AddWindowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var weekdays: Set<Int> = []
    @State private var start = Rhythm.date(minutes: 14 * 60)
    @State private var minutes: Int? = 30
    @State private var busy = false
    @State private var message: String?

    private let lengths = [15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("Add a free time").ssHeadingText()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Which days?").ssBodyText()
                    FlowLayout {
                        ForEach(1...7, id: \.self) { day in
                            Chip(title: RemindersView.weekdayNames[day - 1], selected: weekdays.contains(day)) {
                                if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                            }
                        }
                    }
                    .gentle(value: weekdays)
                }
                .softCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Starts at").ssBodyText()
                        Spacer()
                        DatePicker("Starts at", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                    .frame(minHeight: 48)
                    Text("How long?").ssBodyText()
                    ChipGroup(options: lengths.map { ($0, "\($0) min") }, selection: $minutes)
                }
                .softCard()

                if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

                VStack(spacing: 8) {
                    Button(action: { Task { await save() } }) {
                        if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Add") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(busy || weekdays.isEmpty || minutes == nil)
                    Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).disabled(busy)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        guard let minutes, !weekdays.isEmpty else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await model.addWindows(weekdays: weekdays, startMinute: Rhythm.minutes(from: start), minutes: minutes)
            dismiss()
        } catch {
            message = "That didn't save. Please try again."
        }
    }
}
