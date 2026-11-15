import Foundation
import Observation

/// Decides which screen is showing and holds the participant's data.
@MainActor @Observable
final class AppModel {
    enum Stage { case starting, configMissing, consent, signedOut, setupActivities, setupRhythm, home }

    private(set) var stage: Stage = .starting
    private(set) var profile: ProfileRow?
    private(set) var activities: [ActivityRow] = []
    private(set) var pending: PendingOutcome?
    private(set) var windows: [ReminderWindow] = []
    /// Nil until loaded (or if it couldn't load); the Home card is hidden then.
    private(set) var weekly: [ProgressLine]?
    var consentDeclined = false

    let backend: Backend?
    private let defaults: UserDefaults
    private var userID: UUID?

    private enum Key {
        static let consent = "consentAccepted"
        static let setupStarted = "setupStartedAt"
    }

    init(backend: Backend? = Backend(), defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    // MARK: Launch and consent

    func start() async {
        guard backend != nil else { stage = .configMissing; return }
        guard defaults.bool(forKey: Key.consent) else { stage = .consent; return }
        await resume()
    }

    func acceptConsent() async {
        defaults.set(true, forKey: Key.consent)
        consentDeclined = false
        await resume()
    }

    private func resume() async {
        if let id = await backend?.currentUserID() {
            userID = id
            await refresh()
        } else {
            stage = .signedOut
        }
    }

    // MARK: Sign in

    func signIn(email: String, password: String) async throws -> SignInResult {
        guard let backend else { throw BackendError.notConfigured }
        let result = try await backend.signIn(email: email, password: password)
        if result == .signedIn { try await finishSignIn() }
        return result
    }

    func createAccount(email: String, password: String) async throws {
        guard let backend else { throw BackendError.notConfigured }
        try await backend.createAccount(email: email, password: password)
        try await finishSignIn()
    }

    /// Signed in: load the participant's data. If that fails, say so instead of staying on the login screen.
    private func finishSignIn() async throws {
        guard let backend else { throw BackendError.notConfigured }
        userID = try await backend.requireUserID()
        try await load()
        // Record the consent the participant gave on this device.
        if let id = userID, profile?.consentedAt == nil {
            try? await backend.updateProfile(id, ProfileUpdate(consentedAt: Date()))
            await refresh()
        }
    }

    func signOut() async {
        await backend?.signOut()
        CalendarStore.clear()   // the next person on this phone shouldn't see these busy times
        NotificationScheduler.shared.clearAll()
        userID = nil; profile = nil; activities = []; pending = nil; windows = []; weekly = nil
        stage = .signedOut
    }

    // MARK: Data

    /// Reloads everything and picks the right stage: setup if anything is missing, otherwise home.
    func refresh() async {
        do { try await load() } catch {
            // Keep whatever we had; the next action will surface a real error.
            if stage == .starting { stage = .signedOut }
        }
    }

    private func load() async throws {
        guard let backend, let id = userID else { return }
        do {
            profile = try await backend.loadProfile(id)
            activities = try await backend.loadActivities(id)
            pending = try await backend.pendingOutcome(id)
            // Optional feature: if this fails, the app still works and keeps the last known windows.
            if let loaded = try? await backend.loadWindows(id) { windows = loaded }
        } catch {
            throw BackendError.server("You're signed in, but your data didn't load. \(error.localizedDescription)")
        }
        await syncReminders()
        if activities.count < 3 { stage = .setupActivities }
        else if profile?.hasRhythm != true { stage = .setupRhythm }
        else { stage = .home }
    }

    // MARK: Reminders

    var reminderSettings: ReminderSettings { profile.map(ReminderSettings.init) ?? ReminderSettings() }

    /// Called right after a card is chosen. Asks for notification permission the first time.
    func planOutcomeReminder(outcomeId: UUID, card: SuggestionCard, gapStart: Date) async {
        await NotificationScheduler.shared.scheduleOutcomeReminder(
            outcomeId: outcomeId, card: card, gapStart: gapStart, settings: reminderSettings)
        await uploadReminderEvents()
    }

    /// Done or Skip was saved, so its reminder goes away.
    func outcomeResolved(_ outcomeId: UUID) async {
        NotificationScheduler.shared.resolve(outcomeId)
        await uploadReminderEvents()
    }

    func saveReminderSettings(_ update: ReminderSettingsUpdate) async throws {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        if update.remindersOn { _ = await NotificationScheduler.shared.requestAuthorizationIfNeeded() }
        try await backend.updateReminderSettings(id, update)
        profile = try await backend.loadProfile(id)
        await syncReminders()
    }

    /// Rebuilds the reminder schedule from the profile and sends anything logged while the app was closed.
    func syncReminders() async {
        guard profile != nil else { return }
        await NotificationScheduler.shared.sync(reminderSettings, windows: windows)
        await uploadReminderEvents()
    }

    /// Adds the same free time on each chosen weekday (ISO, 1 = Monday). Asks for permission the first time.
    func addWindows(weekdays: Set<Int>, startMinute: Int, minutes: Int) async throws {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        let rows = weekdays.sorted().map {
            ReminderWindowInsert(weekday: $0, startTime: Rhythm.clockString(minutes: startMinute), minutes: minutes)
        }
        try await backend.insertWindows(rows)
        if reminderSettings.enabled { _ = await NotificationScheduler.shared.requestAuthorizationIfNeeded() }
        windows = try await backend.loadWindows(id)
        await syncReminders()
    }

    func removeWindow(_ window: ReminderWindow) async throws {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        try await backend.removeWindow(window.id)
        windows = try await backend.loadWindows(id)
        await syncReminders()
    }

    private func uploadReminderEvents() async {
        guard let backend, userID != nil else { return }
        let events = NotificationScheduler.shared.queuedEvents
        guard !events.isEmpty else { return }
        NotificationScheduler.shared.dropEvents(await backend.uploadReminderEvents(events))
    }

    /// This week's completed activities for the Home card.
    func refreshWeekly(now: Date = Date()) async {
        guard let backend, userID != nil else { return }
        let zone = profile?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let rows = try? await backend.weeklyProgress(weekStart: WeeklyProgress.weekStart(now, timeZone: zone)) else { return }
        weekly = WeeklyProgress.lines(rows: rows, activities: activities)
    }

    func refreshPending() async {
        guard let backend, let id = userID else { return }
        pending = try? await backend.pendingOutcome(id)
    }

    // MARK: Setup

    /// Starts the setup stopwatch the first time setup is shown (kept across relaunches).
    func markSetupStarted() {
        if defaults.object(forKey: Key.setupStarted) == nil { defaults.set(Date(), forKey: Key.setupStarted) }
    }

    /// `advanceSetup` moves on from the first-time list. Later edits from Home stay where they are.
    func saveActivities(_ drafts: [ActivityDraft], advanceSetup: Bool = true) async throws {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        try await backend.saveActivities(existing: activities, drafts: drafts)
        activities = try await backend.loadActivities(id)
        guard advanceSetup else { return }
        stage = profile?.hasRhythm == true ? .home : .setupRhythm
    }

    func loadHistory() async throws -> [HistoryEntry] {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        return try await backend.loadHistory(id)
    }

    func saveRhythm(_ update: ProfileUpdate) async throws {
        guard let backend, let id = userID else { throw BackendError.notConfigured }
        var update = update
        update.timezone = TimeZone.current.identifier
        if profile?.setupSeconds == nil, let started = defaults.object(forKey: Key.setupStarted) as? Date {
            update.setupSeconds = max(0, Int(Date().timeIntervalSince(started)))
        }
        try await backend.updateProfile(id, update)
        defaults.removeObject(forKey: Key.setupStarted)
        profile = try await backend.loadProfile(id)
        await syncReminders()      // quiet hours may have changed
        stage = .home
    }

    /// Saves a gap (start, minutes, optional energy; never anything from a calendar) and asks for ideas.
    func requestSuggestions(start: Date, minutes: Int, energy: Int?, origin: GapOrigin = .manual,
                            windowID: UUID? = nil) async throws -> (set: SuggestionSet, gapID: UUID) {
        guard let backend else { throw BackendError.notConfigured }
        await syncTimeZone()
        let gapID = try await backend.insertGap(GapInsert(startTime: start, minutes: min(max(minutes, 5), GapFinder.maxMinutes),
                                                          energy: energy, origin: origin, windowId: windowID))
        let set = try await backend.suggest(gapID: gapID)
        return (set, gapID)
    }

    /// Records that this set was turned down in favor of new ideas, then asks again for the same gap.
    func anotherSuggestions(setID: UUID, gapID: UUID) async throws -> SuggestionSet {
        guard let backend else { throw BackendError.notConfigured }
        try await backend.recordAnother(setID: setID)
        return try await backend.suggest(gapID: gapID)
    }

    /// The profile's time zone follows the phone, so clock times stay right when someone travels.
    func syncTimeZone() async {
        guard let backend, let id = userID, let current = profile?.timezone, current != TimeZone.current.identifier else { return }
        try? await backend.updateProfile(id, ProfileUpdate(timezone: TimeZone.current.identifier))
        profile?.timezone = TimeZone.current.identifier
    }
}
