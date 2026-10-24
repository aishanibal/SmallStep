import Foundation

/// An activity being edited on the setup screen. `savedID` is nil until it has been saved.
struct ActivityDraft: Identifiable, Equatable {
    /// Stable and unique per draft, so lists and sheets never confuse two unsaved drafts.
    var id: UUID { localID }

    static let categories = ["movement", "strength", "running", "nutrition", "mindfulness", "yoga", "rest"]

    var localID = UUID()
    /// The database id; nil until saved. Not the SwiftUI identity (see `id`).
    var savedID: UUID?
    var name = ""
    var category = "movement"          // one of `categories`, or free text
    var durationMin = 15
    var location: ActivityLocation = .anywhere
    var priority = 2                   // 3 = matters most
    var weeklyIntention: Int?          // nil = "whenever"

    init() {}

    init(_ row: ActivityRow) {
        savedID = row.id; name = row.name; category = row.category
        durationMin = row.durationMin; location = row.location
        priority = row.priority; weeklyIntention = row.weeklyIntention
    }

    var write: ActivityWrite {
        ActivityWrite(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                      category: category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                      durationMin: durationMin, location: location,
                      priority: priority, weeklyIntention: weeklyIntention)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !category.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var summary: String {
        "\(category.capitalized) · \(durationMin) min · \(location.label.lowercased())"
    }
}
