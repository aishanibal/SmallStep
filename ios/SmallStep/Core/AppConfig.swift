import Foundation

/// Values come from ios/Config.local.xcconfig via Info.plist. The only key in the app is Supabase's
/// public (publishable) one; the Gemini key and Supabase secret key never touch the app or the repo.
enum AppConfig {
    private static func value(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty, !v.hasPrefix("$(") else { return nil }
        return v
    }

    static var supabaseURL: URL? { value("SUPABASE_URL").flatMap(URL.init(string:)) }
    static var publishableKey: String? { value("SUPABASE_PUBLISHABLE_KEY") }
    static var emailDomain: String { value("PARTICIPANT_EMAIL_DOMAIN") ?? "study.smallstep.example" }
    static var isConfigured: Bool { supabaseURL != nil && publishableKey != nil }
}
