import SwiftUI

/// Email and password, with a switch between signing in and creating an account.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var detail: String?
    @FocusState private var focus: Field?
    private enum Field { case email, password }
    private enum Mode { case signIn, create }

    private var creating: Bool { mode == .create }

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text(creating ? "Create account" : "Sign in")
                    .font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text(creating ? "Welcome to SmallStep." : "Welcome back.").ssBodyText()
            }

            VStack(alignment: .leading, spacing: 18) {
                field("Email") {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                field(creating ? "Password (at least \(AccountEmail.minPasswordLength) characters)" : "Password") {
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
            }
            .softCard()

            if let message {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).ssBodyText()
                    if let detail { Text(detail).ssSecondaryText() }
                }
                .softCard(tint: .ssTaupeSoft)
            }

            VStack(spacing: 8) {
                Button(action: { Task { await submit() } }) {
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text(creating ? "Create account" : "Sign in") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || email.isEmpty || password.isEmpty)

                Button(creating ? "Already have an account? Sign in" : "New here? Create an account") {
                    mode = creating ? .signIn : .create
                    message = nil; detail = nil
                }
                .buttonStyle(QuietButtonStyle()).disabled(busy)
            }
        }
        .gentle(value: mode)
        .onChange(of: email) { message = nil; detail = nil }
        .onChange(of: password) { message = nil; detail = nil }
        .fadeIn()
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ssSecondaryText()
            content().font(.ssBody).frame(minHeight: 44)
            Divider().overlay(Color.ssHairline)
        }
    }

    private func submit() async {
        guard !busy else { return }
        message = nil; detail = nil
        guard let normalized = AccountEmail.normalized(email) else {
            message = "Please enter a valid email address."
            return
        }
        if creating, password.count < AccountEmail.minPasswordLength {
            message = "Please use at least \(AccountEmail.minPasswordLength) characters for your password."
            return
        }
        busy = true
        defer { busy = false }
        do {
            if creating {
                try await model.createAccount(email: normalized, password: password)
            } else if try await model.signIn(email: normalized, password: password) == .unknownCredentials {
                message = "That email and password don't match an account."
                detail = "Check what you typed, or create an account."
            }
        } catch let error as BackendError {
            message = error.localizedDescription
        } catch {
            message = creating ? "Couldn't create your account." : "Sign-in didn't work."
            detail = error.localizedDescription
        }
    }
}
