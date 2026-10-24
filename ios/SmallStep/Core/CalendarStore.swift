import Foundation

/// Busy times from an uploaded calendar, kept on this phone only (start and end, never titles).
enum CalendarStore {
    struct Saved: Codable {
        var busy: [BusyInterval]
        var notes: [String]
        var importedAt: Date
    }

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calendar-busy.json")
    }

    static func load() -> Saved? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(_ saved: Saved) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }

    static let maxFileBytes = 5_000_000

    /// Reads a picked .ics file, parses it, and saves only the busy times. Returns a short status line.
    static func importFile(_ fileURL: URL, timeZone: TimeZone) async -> String {
        let opened = fileURL.startAccessingSecurityScopedResource()
        defer { if opened { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL), data.count <= maxFileBytes else {
            return "Couldn't read that file (calendar files up to 5 MB)."
        }
        let text = String(decoding: data, as: UTF8.self)
        guard let parsed = await Task.detached(operation: { GapFinder.busyTimes(fromCalendar: text, timeZone: timeZone) }).value else {
            return "Couldn't read that file."
        }
        do { try save(Saved(busy: parsed.busy, notes: parsed.notes, importedAt: Date())) } catch { return "Couldn't save the calendar." }
        return status(for: load())
    }

    static func status(for saved: Saved?) -> String {
        guard let saved else { return "No calendar added." }
        let date = saved.importedAt.formatted(date: .abbreviated, time: .omitted)
        return "Calendar added \(date): \(saved.busy.count) busy times over the next \(GapFinder.storedDays) days."
    }
}
