import Foundation

/// A report for one rehearsal. Scores are a practice signal, never a
/// prediction of whether the candidate will be hired.
struct Feedback: Hashable, nonisolated Codable {
    var overall: Int
    var communication: Int
    var communicationNote: String
    var answerQuality: Int
    var answerQualityNote: String
    var summary: String
    var strengths: [String]
    /// The one area to improve next.
    var focus: Skill
    /// The specific moment in this interview that shows the focus area.
    var focusEvidence: String
    /// Set when the interview ended early, so the score isn't over-trusted.
    var coverageNote: String?

    /// What went wrong, in a few words each: the judged parts that scored
    /// lowest across the areas, worst first.
    var weaknesses: [String] {
        let weak = areas.flatMap(\.parts).filter { $0.score < 75 && $0.rule == nil }
        var seen = Set<String>()
        return weak.sorted { $0.score < $1.score }
            .map(\.evidence)
            .filter { seen.insert($0).inserted }
            .prefix(2)
            .map { $0 }
    }

    /// Points taken off for ending the interview early.
    var deduction: Int = 0
    /// The answer judge's verdicts for every answered question, and the
    /// interview's measurements. Nil until real judging and measuring exist,
    /// and in feedback saved before them; the scores then fall back to the
    /// estimates.
    var verdicts: [JudgedPart]?
    var measurements: Measurements?

    /// The six areas the interview is scored on, worked out from its parts.
    var areas: [AreaScore] {
        Scoring.areas(answerQuality: answerQuality, communication: communication, focus: focus,
                      verdicts: verdicts ?? [], measured: measurements)
    }

    /// One answer scored on the same six areas: mapped from AI evaluation when available,
    /// or lifted for a strong answer / lowered where its weakness shows.
    func areas(for entry: TranscriptEntry) -> [AreaScore] {
        if let eval = entry.evaluation {
            let res = eval.evaluation_result
            let techScore = Int(round(Double(res.evaluation.correctness.score + res.evaluation.completeness.score + res.evaluation.technical_depth.score) / 30.0 * 100.0))
            let probScore = Int(round(Double(res.evaluation.relevance.score + res.evaluation.technical_depth.score) / 20.0 * 100.0))
            let commScore = Int(round(Double(res.communication.clarity + res.communication.structure + res.communication.conciseness) / 30.0 * 100.0))
            let depthScore = res.evaluation.technical_depth.score * 10
            let uncertScore = res.evaluation.relevance.score * 10
            let confScore = res.communication.structure * 10

            return [
                AreaScore(area: .technical, parts: [
                    ScorePart(title: "Correctness", weight: 35, score: res.evaluation.correctness.score * 10, evidence: res.evaluation.correctness.feedback),
                    ScorePart(title: "Technical Depth", weight: 35, score: res.evaluation.technical_depth.score * 10, evidence: res.evaluation.technical_depth.feedback),
                    ScorePart(title: "Completeness", weight: 30, score: res.evaluation.completeness.score * 10, evidence: res.evaluation.completeness.feedback)
                ]),
                AreaScore(area: .problemSolving, parts: [
                    ScorePart(title: "Approach", weight: 50, score: probScore, evidence: res.evaluation.relevance.feedback),
                    ScorePart(title: "Logical Reasoning", weight: 50, score: res.evaluation.clarity.score * 10, evidence: res.evaluation.clarity.feedback)
                ]),
                AreaScore(area: .communication, parts: [
                    ScorePart(title: "Clarity", weight: 35, score: res.communication.clarity * 10, evidence: "Clear communication"),
                    ScorePart(title: "Structure", weight: 35, score: res.communication.structure * 10, evidence: "Organized thought process"),
                    ScorePart(title: "Conciseness", weight: 30, score: res.communication.conciseness * 10, evidence: "Direct answers without filler")
                ]),
                AreaScore(area: .projectDepth, parts: [
                    ScorePart(title: "Depth of Explanation", weight: 50, score: depthScore, evidence: res.evaluation.technical_depth.feedback),
                    ScorePart(title: "Trade-offs", weight: 50, score: res.evaluation.relevance.score * 10, evidence: "Evaluated key trade-offs")
                ]),
                AreaScore(area: .uncertainty, parts: [
                    ScorePart(title: "Handling Edge Cases", weight: 100, score: uncertScore, evidence: "Addressed system boundary conditions")
                ]),
                AreaScore(area: .confidence, parts: [
                    ScorePart(title: "Delivery Poise", weight: 100, score: confScore, evidence: "Assertive technical reasoning")
                ])
            ]
        }

        guard let moment = entry.moment else { return [] }
        let answer: Scoring.Answer
        if case .weakness(let skill) = moment.kind { answer = .weak(skill) } else { answer = .strong }
        return Scoring.areas(answerQuality: answerQuality, communication: communication, focus: focus, for: answer,
                             verdicts: entry.verdicts ?? [], measured: entry.measurements)
    }

    /// One answer's score: the AI score out of 100, or the average of its six areas.
    func score(for entry: TranscriptEntry) -> Int? {
        if let eval = entry.evaluation {
            return eval.scoreOutOf100
        }
        return entry.moment == nil ? nil : Scoring.overall(areas(for: entry))
    }

    /// The average of the six areas, less any deduction: what `overall` is.
    var scoredTotal: Int {
        if overall > 0 { return overall }
        return max(Scoring.overall(areas) - deduction, 0)
    }

    /// Where the score sits, in the ring's own four colors.
    var band: Band { Band(score: overall) }

    enum Band: CaseIterable {
        case needsWork, onYourWay, almostReady, interviewReady

        init(score: Int) {
            switch score {
            case ..<40: self = .needsWork
            case ..<80: self = .onYourWay
            case ..<90: self = .almostReady
            default: self = .interviewReady
            }
        }

        var title: String {
            switch self {
            case .needsWork: "Keep Practicing"
            case .onYourWay: "Getting There"
            case .almostReady: "Almost Ready"
            case .interviewReady: "Interview Ready"
            }
        }

        /// The scores in the band, as the scale under the ring labels them.
        var range: ClosedRange<Int> {
            switch self {
            case .needsWork: 0...39
            case .onYourWay: 40...79
            case .almostReady: 80...89
            case .interviewReady: 90...100
            }
        }
    }
}
