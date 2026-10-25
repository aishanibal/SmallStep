import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var passcode = ""
    @State private var busy = false
    @State private var message: String?
    @State private var detail: String?
    @State private var offerCreate = false
    @FocusState private var focus: Field?
    private enum Field { case code, passcode }

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("Enter a participant code and passcode. Use the same ones to get your data back on another install.")
                    .ssBodyText()
            }

            VStack(alignment: .leading, spacing: 18) {
                field("Participant code") {
                    TextField("e.g. maple-17", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .code).submitLabel(.next)
                        .onSubmit { focus = .passcode }
                }
                field("Passcode (at least \(ParticipantCode.minPasscodeLength) characters)") {
                    SecureField("Passcode", text: $passcode)
                        .focused($focus, equals: .passcode).submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
            }
            .softCard()

            if offerCreate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No account with that code and passcode.").ssHeadingText()
                    Text("Create one, or check what you typed.").ssBodyText()
                }
                .softCard(tint: .ssBlueSoft)
            }

            if let message {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).ssBodyText()
                    if let detail { Text(detail).ssSecondaryText() }
                }
                .softCard(tint: .ssTaupeSoft)
            }

            VStack(spacing: 8) {
                Button(action: { Task { await submit() } }) {
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text(offerCreate ? "Create with this passcode" : "Continue") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || code.isEmpty || passcode.isEmpty)
                if offerCreate {
                    Button("Edit") { offerCreate = false; focus = .code }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .onChange(of: code) { offerCreate = false; message = nil }
        .onChange(of: passcode) { offerCreate = false; message = nil }
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
        guard let normalized = ParticipantCode.normalized(code) else {
            message = "Codes use letters, numbers, dashes or underscores (3 to 24 characters)."
            return
        }
        guard passcode.count >= ParticipantCode.minPasscodeLength else {
            message = "Please use at least \(ParticipantCode.minPasscodeLength) characters for the passcode."
            return
        }
        busy = true
        defer { busy = false }
        do {
            if offerCreate {
                try await model.createAccount(code: normalized, passcode: passcode)
            } else if try await model.signIn(code: normalized, passcode: passcode) == .unknownCredentials {
                offerCreate = true
            }
        } catch let error as BackendError {
            message = error.localizedDescription
        } catch {
            message = "Sign-in didn't work."
            detail = error.localizedDescription
        }
    }
}
