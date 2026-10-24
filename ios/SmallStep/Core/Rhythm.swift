import Foundation

/// Conversions between the clock pickers and Postgres `time` strings.
enum Rhythm {
    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    /// 450 -> "07:30:00"
    static func clockString(minutes: Int) -> String {
        String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    /// "07:30" or "07:30:00" -> 450
    static func minutes(fromClock s: String?) -> Int? {
        guard let s, s.count >= 5 else { return nil }
        let p = s.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}

enum ParticipantCode {
    /// Codes are lowercase letters, digits, "-" and "_", 3 to 24 characters.
    static func normalized(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.range(of: "^[a-z0-9_-]{3,24}$", options: .regularExpression) != nil else { return nil }
        return code
    }

    static func email(for code: String, domain: String = AppConfig.emailDomain) -> String { "\(code)@\(domain)" }

    /// Supabase requires at least 6 characters (set in supabase/config.toml and the dashboard).
    static let minPasscodeLength = 6
}
