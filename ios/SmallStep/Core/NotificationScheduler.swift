import Foundation
import Observation
import UserNotifications

enum ReminderAction: String, Hashable { case open, done, skip }

/// A reminder the student acted on, waiting for Home to open the right screen.
struct ReminderTap: Hashable {
    let outcomeId: UUID
    let action: ReminderAction
}

/// A free-time nudge the student tapped: the window and when this occurrence started.
struct WindowTap: Hashable {
    let windowId: UUID
    let start: Date
    let minutes: Int
}

/// Hands reminder taps from the notification delegate to the UI. Set before Home exists on a cold launch.
@MainActor @Observable
final class ReminderRouter {
    static let shared = ReminderRouter()
    var tap: ReminderTap?
    var windowTap: WindowTap?
}

/// The only place that talks to UNUserNotificationCenter. Plans live on the phone (UserDefaults) so the
/// whole schedule can be rebuilt whenever settings change, and so Snooze works from the lock screen.
/// What happened to each reminder is queued here and uploaded by AppModel when the app is open.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    static let category = "OUTCOME"
    static let lastCategory = "OUTCOME_NO_SNOOZE"     // after the last allowed snooze
    static let windowCategory = "WINDOW"
    enum ActionID { static let done = "DONE", skip = "SKIP", snooze = "SNOOZE" }
    private static let prefix = "outcome-"
    private static let windowPrefix = "window-"
    private enum Key {
        static let plans = "reminderPlans", settings = "reminderSettings", events = "reminderEventQueue"
        static let windows = "reminderWindows", windowFires = "reminderWindowFires"
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: Setup and permission

    func registerCategories() {
        let done = UNNotificationAction(identifier: ActionID.done, title: "Done", options: [.foreground])
        let skip = UNNotificationAction(identifier: ActionID.skip, title: "Skip", options: [.foreground])
        let snooze = UNNotificationAction(identifier: ActionID.snooze, title: "Snooze \(ReminderRules.snoozeMinutes) min", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done, skip, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.lastCategory, actions: [done, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.windowCategory, actions: [], intentIdentifiers: []),
        ])
    }

    func authorization() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Shows the system prompt the first time. True when SmallStep may show notifications.
    func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorization() {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    // MARK: Outcome reminders

    /// Called right after a card is chosen.
    func scheduleOutcomeReminder(outcomeId: UUID, card: SuggestionCard, gapStart: Date, settings: ReminderSettings, now: Date = Date()) async {
        let fire = ReminderRules.outcomeFireDate(gapStart: gapStart, durationMin: card.durationMin, now: now)
        plans = plans.filter { $0.outcomeId != outcomeId } + [ReminderPlan(outcomeId: outcomeId, card: card, fireDate: fire)]

        let allowed = settings.enabled ? await requestAuthorizationIfNeeded() : true
        let decision = await sync(settings, windows: nil, now: now).outcomes[outcomeId]
        switch decision {
        case .suppressed(let why): log(outcomeId, "suppressed", why)
        case .fire where !allowed, nil: log(outcomeId, "suppressed", "no_permission")
        case .fire: log(outcomeId, "scheduled")
        }
    }

    /// Done or Skip was saved: the reminder is no longer needed.
    func resolve(_ outcomeId: UUID, now: Date = Date()) {
        plans = plans.map { var p = $0; if p.outcomeId == outcomeId { p.resolvedAt = now }; return p }
        let id = [Self.identifier(outcomeId)]
        center.removePendingNotificationRequests(withIdentifiers: id)
        center.removeDeliveredNotifications(withIdentifiers: id)
    }

    /// Snooze from the notification: show it again later. Not an outcome, and nothing is sent to the server now.
    func snooze(_ outcomeId: UUID, now: Date = Date()) async {
        guard var plan = plans.first(where: { $0.outcomeId == outcomeId }), plan.resolvedAt == nil else { return }
        plan.fireDate = now.addingTimeInterval(Double(ReminderRules.snoozeMinutes) * 60)
        plan.snoozes += 1
        plans = plans.map { $0.outcomeId == outcomeId ? plan : $0 }
        log(outcomeId, "snoozed", "\(plan.snoozes)")
        await sync(settings ?? ReminderSettings(), windows: nil, now: now)
    }

    func plan(for outcomeId: UUID) -> ReminderPlan? { plans.first { $0.outcomeId == outcomeId } }

    /// Rebuilds every pending reminder and window nudge from what is stored and the current controls.
    /// Nil arguments keep what was stored last (Snooze runs without the server, so it passes nil).
    @discardableResult
    func sync(_ newSettings: ReminderSettings?, windows newWindows: [ReminderWindow]?, now: Date = Date()) async -> ReminderSchedule {
        if let newSettings { settings = newSettings }
        if let newWindows { windows = newWindows }
        let current = settings ?? ReminderSettings()
        plans = ReminderRules.pruned(plans, now: now)

        // Window nudges already shown still count toward today's cap.
        let cutoff = now.addingTimeInterval(-Double(ReminderRules.keepHours) * 3600)
        let shown = windowFires.filter { $0.value <= now && $0.value > cutoff }

        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) || $0.hasPrefix(Self.windowPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let occurrences = ReminderRules.occurrences(windows, settings: current, now: now)
        let decisions = ReminderRules.schedule(plans: plans, windows: occurrences, shownWindowFires: Array(shown.values),
                                               settings: current, now: now)
        switch await authorization() {
        case .authorized, .provisional, .ephemeral: break
        default:
            windowFires = shown
            return decisions
        }
        for plan in plans {
            guard case .fire(let date) = decisions.outcomes[plan.outcomeId] else { continue }
            try? await center.add(request(for: plan, at: date, now: now))
        }
        var fires = shown
        for occurrence in occurrences {
            guard case .fire(let date) = decisions.windows[occurrence.key] else { continue }
            try? await center.add(windowRequest(for: occurrence, now: now))
            fires[occurrence.key] = date
        }
        windowFires = fires
        return decisions
    }

    /// Sign out: nothing from this person stays scheduled or stored.
    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        for key in [Key.plans, Key.settings, Key.events, Key.windows, Key.windowFires] { defaults.removeObject(forKey: key) }
    }

    static func identifier(_ outcomeId: UUID) -> String { prefix + outcomeId.uuidString }

    private func request(for plan: ReminderPlan, at date: Date, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "How did it go?"
        content.body = "Mark “\(plan.card.title)” done or skipped."
        content.sound = .default
        content.threadIdentifier = "outcomes"
        content.categoryIdentifier = plan.snoozes >= ReminderRules.maxSnoozes ? Self.lastCategory : Self.category
        content.userInfo = ["outcomeId": plan.outcomeId.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: Self.identifier(plan.outcomeId), content: content, trigger: trigger)
    }

    private func windowRequest(for occurrence: WindowOccurrence, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "You've got \(occurrence.minutes) minutes free"
        content.body = "Want an idea for it?"
        content.sound = .default
        content.threadIdentifier = "windows"
        content.categoryIdentifier = Self.windowCategory
        content.userInfo = ["windowId": occurrence.windowId.uuidString,
                            "start": occurrence.start.timeIntervalSince1970, "minutes": occurrence.minutes]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, occurrence.start.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: Self.windowPrefix + occurrence.key, content: content, trigger: trigger)
    }

    // MARK: Event queue (uploaded by AppModel)

    func log(_ outcomeId: UUID, _ kind: String, _ detail: String? = nil) {
        queuedEvents.append(ReminderEventInsert(outcomeId: outcomeId, kind: kind, detail: detail))
    }

    func logWindow(_ windowId: UUID, _ kind: String) {
        queuedEvents.append(ReminderEventInsert(windowId: windowId, kind: kind))
    }

    var queuedEvents: [ReminderEventInsert] {
        get { read(Key.events) ?? [] }
        set { write(newValue, Key.events) }
    }

    func dropEvents(_ ids: Set<UUID>) { queuedEvents = queuedEvents.filter { !ids.contains($0.id) } }

    // MARK: Storage

    private(set) var plans: [ReminderPlan] {
        get { read(Key.plans) ?? [] }
        set { write(newValue, Key.plans) }
    }

    private(set) var windows: [ReminderWindow] {
        get { read(Key.windows) ?? [] }
        set { write(newValue, Key.windows) }
    }

    /// When each window nudge was set to show, by occurrence key. Past ones count toward the daily cap.
    private var windowFires: [String: Date] {
        get { read(Key.windowFires) ?? [:] }
        set { write(newValue, Key.windowFires) }
    }

    private(set) var settings: ReminderSettings? {
        get { read(Key.settings) }
        set { write(newValue, Key.settings) }
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func write<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
