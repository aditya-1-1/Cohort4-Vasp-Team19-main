import Observation
import SwiftUI

/// The login screen's view model: the form, its rules, and signing in. With
/// Supabase set up (`BackendSecrets`) these are real accounts through
/// `AuthService`. Without it nothing is sent: logging in opens the returning
/// candidate's app, and a new account opens a new candidate's.
@Observable
final class LoginViewModel {
    enum Working { case apple, email }

    var isCreatingAccount = false
    var name = ""
    var email = "" {
        didSet { if email != oldValue { emailError = nil } }
    }
    var password = ""
    var showsPassword = false
    /// Which button is waiting, if any.
    private(set) var working: Working?
    private(set) var emailError: String?
    /// Shown after sign up when the account must confirm its email first.
    private(set) var confirmationNotice: String?

    // MARK: - Rules

    static let minimumPasswordLength = 8

    var emailLooksValid: Bool {
        let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@")
        return parts.count == 2 && parts[0].count > 0 && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }

    var passwordRules: [(text: String, isMet: Bool)] {
        [
            ("\(Self.minimumPasswordLength) characters", password.count >= Self.minimumPasswordLength),
            ("A number", password.contains(where: \.isNumber)),
            ("A letter", password.contains(where: \.isLetter)),
        ]
    }

    /// What's still missing, one thing at a time, in plain words.
    var passwordHint: String {
        let short = Self.minimumPasswordLength - password.count
        if short > 0 { return short == 1 ? "1 more character" : "\(short) more characters" }
        if !password.contains(where: \.isNumber) { return "Add a number" }
        if !password.contains(where: \.isLetter) { return "Add a letter" }
        return "Good password"
    }

    var canSubmit: Bool {
        guard working == nil, !email.isEmpty, !password.isEmpty else { return false }
        if isCreatingAccount {
            return !name.trimmingCharacters(in: .whitespaces).isEmpty && passwordRules.allSatisfy(\.isMet)
        }
        return true
    }

    // MARK: - Actions

    func toggleMode() {
        isCreatingAccount.toggle()
        emailError = nil
        showsPassword = false
    }

    /// Checks the email, then signs in. Returns false when the email needs
    /// fixing, so the screen can put the cursor back in it.
    @discardableResult
    func submit(in appState: AppState) -> Bool {
        guard emailLooksValid else {
            emailError = "Enter an email address like name@example.com."
            return false
        }
        signIn(with: .email, in: appState)
        return true
    }

    /// With accounts set up, creates or logs in to a real one. Otherwise waits
    /// as a request would and opens the mock app: a new account as a new
    /// candidate, a log in as the returning one.
    func signIn(with method: Working, in appState: AppState) {
        emailError = nil
        confirmationNotice = nil
        if Backend.isConfigured {
            guard method == .email else {
                emailError = "Sign in with Apple isn’t set up yet. Use your email for now."
                return
            }
            signInToAccount(in: appState)
            return
        }
        working = method
        let isNew = isCreatingAccount
        let firstName = name.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            appState.load(isNew ? .newUser : .returning)
            if isNew, let firstName { appState.candidateName = firstName }
            withAnimation(.smooth(duration: 0.4)) {
                // A new account sets up its profile first.
                appState.needsProfileSetup = isNew
                appState.isSignedIn = true
            }
            working = nil
        }
    }

    private func signInToAccount(in appState: AppState) {
        working = .email
        let isNew = isCreatingAccount
        let name = name.trimmingCharacters(in: .whitespaces)
        let email = email.trimmingCharacters(in: .whitespaces)
        let password = password
        Task {
            defer { working = nil }
            do {
                if isNew {
                    switch try await AuthService.signUp(name: name, email: email, password: password) {
                    case .signedIn(let account):
                        appState.didSignIn(account, isNew: true)
                    case .confirmEmail:
                        withAnimation {
                            confirmationNotice = "Check your email to confirm your account, then log in."
                            isCreatingAccount = false
                        }
                    }
                } else {
                    let account = try await AuthService.signIn(email: email, password: password)
                    appState.didSignIn(account, isNew: false)
                }
            } catch {
                withAnimation { emailError = error.localizedDescription }
            }
        }
    }
}

/// The reset password sheet's view model.
@Observable
final class ResetPasswordViewModel {
    var email: String
    private(set) var isSending = false
    private(set) var isSent = false

    init(email: String) {
        self.email = email
    }

    var emailLooksValid: Bool {
        let parts = email.trimmingCharacters(in: .whitespaces).split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    var canSend: Bool { emailLooksValid && !isSending }

    func send() {
        guard canSend else { return }
        isSending = true
        Task {
            if Backend.isConfigured {
                // Says it was sent either way, so nobody can test which
                // emails have accounts.
                try? await AuthService.sendPasswordReset(to: email.trimmingCharacters(in: .whitespaces))
            } else {
                try? await Task.sleep(for: .seconds(1))
            }
            isSending = false
            isSent = true
        }
    }
}
