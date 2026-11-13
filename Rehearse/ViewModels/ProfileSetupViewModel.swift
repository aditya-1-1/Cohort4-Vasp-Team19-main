import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Profile setup's view model: the answers to each step, moving between
/// steps, reading a resume and asking about notifications. Each answer is
/// kept in `AppState` as soon as it's given.
@Observable
final class ProfileSetupViewModel {
    enum Step: Int, CaseIterable {
        case role, experience, interview, resume, notifications, done
    }

    /// The role tile that lets a role be typed in.
    static let otherRoleTitle = "Other"
    static let readableExtensions: Set<String> = ["pdf", "docx", "doc", "rtf", "txt", "heic", "jpg", "jpeg", "png"]

    private(set) var step: Step = .role
    private(set) var movingForward = true
    /// One of the role tiles' titles, or `otherRoleTitle` for a role typed in.
    var roleChoice: String?
    var otherRole = ""
    var stage: CareerStage?
    var studyYear = 2
    var workYears = 3
    var hasInterview: Bool?
    var company = ""
    var interviewDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    var interviewType: InterviewType = .technical
    /// The file being read, while it's read.
    private(set) var readingFileName: String?
    private(set) var readError: String?
    /// The picked file the current resume was read from; a resume with any
    /// other name was built from notes.
    private(set) var uploadedFileName: String?
    private(set) var notificationStatus: UNAuthorizationStatus?
    private(set) var isAskingForNotifications = false
    /// The interview saved from the interview step, so going back and on
    /// again updates it rather than adding a second.
    private var savedInterviewID: Interview.ID?

    // MARK: - What the screen shows

    var role: String {
        let choice = roleChoice == Self.otherRoleTitle ? otherRole : (roleChoice ?? "")
        return choice.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canContinue: Bool {
        switch step {
        case .role: !role.isEmpty
        case .experience: stage != nil
        case .interview: hasInterview != nil && (hasInterview == false || !company.trimmingCharacters(in: .whitespaces).isEmpty)
        default: true
        }
    }

    /// Notifications have their own Not Now, so they don't need a Skip.
    var isOptional: Bool {
        [.interview, .resume].contains(step)
    }

    /// Built from notes rather than read from a picked file.
    func resumeIsBuilt(_ resume: ResumeStatus) -> Bool {
        guard let context = resume.context else { return false }
        return context.fileName != uploadedFileName
    }

    /// The interview the first one will be: the real one if there is one,
    /// otherwise a technical interview for the chosen role.
    func firstInterview(in appState: AppState) -> Interview {
        if let next = appState.upcomingInterviews.first { return next }
        return Interview(role: appState.targetRole, experienceLevel: appState.experienceLevel, type: .technical)
    }

    // MARK: - Moving through

    func advance(skipping: Bool = false, in appState: AppState) {
        if !skipping { save(to: appState) }
        if let next = Step(rawValue: step.rawValue + 1) { go(to: next, forward: true) }
    }

    func goBack() {
        go(to: Step(rawValue: step.rawValue - 1) ?? .role, forward: false)
    }

    func go(to next: Step, forward: Bool) {
        movingForward = forward
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }

    /// Keeps each answer as soon as it's given.
    private func save(to appState: AppState) {
        switch step {
        case .role:
            appState.targetRole = role
        case .experience:
            guard let stage else { return }
            appState.experienceLevel = Experience.level(stage: stage, studyYear: studyYear, workYears: workYears)
        case .interview:
            guard hasInterview == true else { return }
            let name = company.trimmingCharacters(in: .whitespaces)
            var interview = Interview(
                role: appState.targetRole,
                company: name.isEmpty ? nil : name,
                experienceLevel: appState.experienceLevel,
                type: interviewType,
                date: interviewDate
            )
            if let savedInterviewID { interview.id = savedInterviewID }
            savedInterviewID = interview.id
            appState.saveUpcomingInterview(interview)
        default:
            break
        }
    }

    /// Leaves setup for Home, or straight into the first interview.
    func finish(startingFirstInterview: Bool, in appState: AppState) {
        let interview = firstInterview(in: appState)
        withAnimation(.smooth(duration: 0.4)) { appState.needsProfileSetup = false }
        if startingFirstInterview {
            appState.startInterview(interview, resume: appState.resume.context)
        }
    }

    // MARK: - Resume

    /// What opening the resume should show.
    enum ResumePreview {
        /// The builder, on the page it wrote.
        case builder
        case file(URL)
        /// The picked file has gone.
        case unavailable
    }

    func preview(in appState: AppState) -> ResumePreview {
        if resumeIsBuilt(appState.resume) {
            // The builder opens on the page it wrote, to read and edit. If
            // its notes weren't kept, they're taken back from the page.
            if appState.resumeDraft == nil, let context = appState.resume.context {
                appState.resumeDraft = ResumeDraft(context: context, role: appState.targetRole)
            }
            appState.builderOpensOnPage = true
            return .builder
        }
        if let name = uploadedFileName, let file = ResumeReader.keptFile(named: name) {
            return .file(file)
        }
        return .unavailable
    }

    func readResume(_ fileName: String, in appState: AppState) {
        readError = nil
        guard Self.readableExtensions.contains((fileName as NSString).pathExtension.lowercased()) else {
            readError = "“\(fileName)” isn’t a file we can read. Choose a PDF or Word document."
            return
        }
        readingFileName = fileName
        Task {
            let result = await AppState.readResume(named: fileName)
            withAnimation {
                switch result {
                case .ready:
                    uploadedFileName = fileName
                    appState.resume = result
                case .failed(_, let reason):
                    readError = reason
                default:
                    break
                }
                readingFileName = nil
            }
        }
    }

    /// Back to no resume: the kept copy of a picked file, or the builder's
    /// notes for a built one, go with it.
    func deleteResume(in appState: AppState) {
        if let name = uploadedFileName, let file = ResumeReader.keptFile(named: name) {
            try? FileManager.default.removeItem(at: file)
        }
        if resumeIsBuilt(appState.resume) { appState.resumeDraft = nil }
        withAnimation(.smooth(duration: 0.3)) {
            appState.removeResume()
            uploadedFileName = nil
            readError = nil
        }
    }

    // MARK: - Notifications

    func refreshNotificationStatus() async {
        notificationStatus = await InterviewReminders.authorizationStatus()
    }

    /// Asks iOS, keeps the answer, then moves on.
    func turnOnNotifications(in appState: AppState) {
        isAskingForNotifications = true
        Task {
            appState.remindersOn = await InterviewReminders.requestPermission()
            await refreshNotificationStatus()
            isAskingForNotifications = false
            advance(in: appState)
        }
    }

    /// Continue or Not Now: keeps the choice, then moves on.
    func continueWithReminders(_ on: Bool, in appState: AppState) {
        appState.remindersOn = on
        advance(in: appState)
    }

    #if DEBUG
    /// `-step N` opens setup at a step, for screenshots.
    func applyDebugArguments(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-step"), arguments.indices.contains(index + 1),
              let number = Int(arguments[index + 1]), let debugStep = Step(rawValue: number) else { return false }
        roleChoice = "iOS Engineer"
        stage = arguments.contains("-professional") ? .professional : .student
        hasInterview = true
        company = "Apple"
        step = debugStep
        return true
    }
    #endif
}
