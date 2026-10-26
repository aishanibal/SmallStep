import Foundation
import Supabase

/// Errors with wording that is safe to show to a participant.
enum BackendError: LocalizedError {
    case notConfigured
    case signUpNeedsConfirmation
    case codeAlreadyUsed
    case sessionNotKept
    case setupIncomplete
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The app isn't connected to the study yet."
        case .signUpNeedsConfirmation: "This study account needs an email step that isn't switched on. Please tell the study team."
        case .codeAlreadyUsed: "That code is already in use. Check the passcode, or choose another code."
        case .sessionNotKept: "This phone couldn't keep you signed in. Please try again."
        case .setupIncomplete: "Let's finish setting up first."
        case .server(let detail): detail
        }
    }
}

enum SignInResult { case signedIn, unknownCredentials }

/// All network calls in one place. Everything runs as the signed-in participant under Row Level Security.
final class Backend {
    let client: SupabaseClient

    init?() {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.publishableKey else { return nil }
        client = SupabaseClient(
            supabaseURL: url, supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    // MARK: Auth

    func currentUserID() async -> UUID? {
        try? await requireUserID()
    }

    /// The signed-in participant, or an error the login screen can show. A missing keychain session
    /// must not look like a successful sign-in.
    func requireUserID() async throws -> UUID {
        do {
            let session = try await client.auth.session
            if session.isExpired { throw BackendError.sessionNotKept }
            return session.user.id
        } catch let error as BackendError {
            throw error
        } catch {
            throw BackendError.sessionNotKept
        }
    }

    func signIn(email: String, passcode: String) async throws -> SignInResult {
        do {
            _ = try await client.auth.signIn(email: email, password: passcode)
            return .signedIn
        } catch let error as AuthError {
            if case .api(_, let code, _, _) = error, code == .invalidCredentials { return .unknownCredentials }
            throw error
        }
    }

    func createAccount(email: String, passcode: String) async throws {
        let response: AuthResponse
        do {
            response = try await client.auth.signUp(email: email, password: passcode)
        } catch let error as AuthError {
            if case .api(_, let code, _, _) = error, code == .emailExists || code == .userAlreadyExists {
                throw BackendError.codeAlreadyUsed
            }
            throw error
        }
        // GoTrue hides an existing account as a user with no identities and no session.
        if response.session == nil {
            if response.user.identities?.isEmpty == true { throw BackendError.codeAlreadyUsed }
            throw BackendError.signUpNeedsConfirmation
        }
    }

    func signOut() async { try? await client.auth.signOut() }

    // MARK: Profile and activities

    func loadProfile(_ id: UUID) async throws -> ProfileRow {
        try await client.from("profiles").select().eq("id", value: id).single().execute().value
    }

    func updateProfile(_ id: UUID, _ update: ProfileUpdate) async throws {
        try await client.from("profiles").update(update).eq("id", value: id).execute()
    }

    func loadActivities(_ id: UUID) async throws -> [ActivityRow] {
        try await client.from("activities").select().eq("participant_id", value: id)
            .order("created_at").execute().value
    }

    /// Makes the stored list match `drafts`: update the ones with ids, insert new ones, delete the rest.
    func saveActivities(existing: [ActivityRow], drafts: [ActivityDraft]) async throws {
        let keep = Set(drafts.compactMap(\.savedID))
        for gone in existing where !keep.contains(gone.id) {
            try await client.from("activities").delete().eq("id", value: gone.id).execute()
        }
        for draft in drafts {
            if let id = draft.savedID {
                try await client.from("activities").update(draft.write).eq("id", value: id).execute()
            } else {
                try await client.from("activities").insert(draft.write).execute()
            }
        }
    }

    // MARK: Gaps and suggestions

    func insertGap(_ gap: GapInsert) async throws -> UUID {
        let row: IDRow = try await client.from("gaps").insert(gap).select("id").single().execute().value
        return row.id
    }

    func suggest(gapID: UUID) async throws -> SuggestionSet {
        do {
            return try await client.functions.invoke("suggest", options: FunctionInvokeOptions(body: ["gap_id": gapID.uuidString]))
        } catch FunctionsError.httpError(let code, let data) {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            if reason == "setup_incomplete" { throw BackendError.setupIncomplete }
            throw BackendError.server("Something went wrong on our side (\(code)). Please try again in a moment.")
        }
    }

    /// Developer screen only.
    func devInfo() async throws -> DevInfo {
        do {
            return try await client.functions.invoke("dev-info", options: FunctionInvokeOptions(body: [String: String]()))
        } catch FunctionsError.httpError(let code, _) {
            throw BackendError.server("dev-info returned \(code).")
        }
    }

    // MARK: Outcomes

    func chooseSuggestion(setID: UUID, suggestionID: UUID) async throws -> UUID {
        let row: IDRow = try await client.from("outcomes")
            .insert(OutcomeInsert(setId: setID, chosenSuggestionId: suggestionID)).select("id").single().execute().value
        return row.id
    }

    func chooseNone(setID: UUID, reason: String) async throws {
        try await client.from("outcomes").insert(OutcomeInsert(setId: setID, noneReason: reason)).execute()
    }

    /// Marks a set as "asked for other ideas." A second tap on the same set is already saved.
    func recordAnother(setID: UUID) async throws {
        do {
            try await chooseNone(setID: setID, reason: "wanted_another")
        } catch {
            let code = (error as? PostgrestError)?.code
            let message = error.localizedDescription.lowercased()
            guard code == "23505" || message.contains("duplicate") || message.contains("unique") else { throw error }
        }
    }

    func updateOutcome(_ id: UUID, _ update: OutcomeUpdate) async throws {
        try await client.from("outcomes").update(update).eq("id", value: id).execute()
    }

    /// The most recent chosen-but-unresolved outcome, if any.
    func pendingOutcome(_ participant: UUID) async throws -> PendingOutcome? {
        let rows: [OutcomeRow] = try await client.from("outcomes")
            .select("id, set_id, chosen_suggestion_id, completed")
            .eq("participant_id", value: participant).order("ts", ascending: false).limit(5).execute().value
        guard let open = rows.first(where: { $0.chosenSuggestionId != nil && $0.completed == nil }),
              let suggestionID = open.chosenSuggestionId else { return nil }
        let card: SuggestionCard = try await client.from("suggestions")
            .select("id, title, description, duration_min, position").eq("id", value: suggestionID).single().execute().value
        return PendingOutcome(outcomeId: open.id, card: card)
    }

    /// Newest first. Titles come from the cards the participant is allowed to read. Sources stay hidden.
    func loadHistory(_ participant: UUID) async throws -> [HistoryEntry] {
        let rows: [HistoryOutcome] = try await client.from("outcomes")
            .select("id, chosen_suggestion_id, completed, skip_reason, fit_rating, none_reason, ts")
            .eq("participant_id", value: participant).order("ts", ascending: false).limit(100).execute().value
        let chosen = Array(Set(rows.compactMap(\.chosenSuggestionId)))
        var titles: [UUID: String] = [:]
        if !chosen.isEmpty {
            let cards: [SuggestionCard] = try await client.from("suggestions")
                .select("id, title, description, duration_min, position").in("id", values: chosen).execute().value
            for card in cards { titles[card.id] = card.title }
        }
        return rows.map { HistoryEntry(row: $0, cardTitle: $0.chosenSuggestionId.flatMap { titles[$0] }) }
    }
}
