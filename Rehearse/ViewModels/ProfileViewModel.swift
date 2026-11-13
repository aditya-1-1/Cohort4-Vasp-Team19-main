import Foundation
import Observation

/// The Profile screen's view model: signing out, deleting the account, and
/// turning interview reminders on, which asks iOS first.
@Observable
final class ProfileViewModel {
    private(set) var isDeleting = false
    var deleteError: String?
    /// Set when reminders were turned on but iOS has notifications off.
    var notificationsBlocked = false

    /// Real accounts are in use (Supabase is set up), not the prototype's
    /// own data.
    var usesRealAccounts: Bool { Backend.isConfigured }

    var signOutMessage: String {
        usesRealAccounts
            ? "You’ll need to log in again to see your interviews."
            : "In this prototype, signing out starts over as a new candidate."
    }

    func signOut(in appState: AppState) {
        if usesRealAccounts { appState.signOut() } else { appState.load(.newUser) }
    }

    func deleteAccount(in appState: AppState) {
        isDeleting = true
        Task {
            do {
                try await appState.deleteAccount()
            } catch {
                deleteError = error.localizedDescription
            }
            isDeleting = false
        }
    }

    /// Turning reminders on asks iOS first; if notifications are blocked,
    /// the switch stays off and Settings is offered instead.
    func setReminders(_ on: Bool, in appState: AppState) {
        guard on else {
            appState.remindersOn = false
            return
        }
        Task {
            let allowed = await InterviewReminders.requestPermission()
            appState.remindersOn = allowed
            notificationsBlocked = !allowed
        }
    }
}
