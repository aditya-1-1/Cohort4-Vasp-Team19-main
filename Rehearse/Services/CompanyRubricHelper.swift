import Foundation

/// Provides company-specific interview evaluation rubrics and badge descriptions.
struct CompanyRubricHelper {
    static func shortTitle(for company: String) -> String {
        let lower = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("amazon") || lower.contains("aws") {
            return "16 Leadership Principles"
        } else if lower.contains("google") || lower.contains("alphabet") {
            return "GCA & Googleyness"
        } else if lower.contains("meta") || lower.contains("facebook") {
            return "Move Fast & High Impact"
        } else if lower.contains("apple") {
            return "Craftsmanship & Precision"
        } else if lower.contains("netflix") {
            return "Freedom & Responsibility"
        } else if lower.contains("microsoft") {
            return "Growth Mindset & Empathy"
        } else if lower.contains("stripe") {
            return "Operational Rigor & Depth"
        } else {
            return "Tailored Company Standards"
        }
    }

    static func rubricDescription(for company: String) -> String {
        let trimmed = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("amazon") || lower.contains("aws") {
            return "Evaluates against Amazon's 16 Leadership Principles (Customer Obsession, Ownership, Bias for Action, Dive Deep)."
        } else if lower.contains("google") || lower.contains("alphabet") {
            return "Evaluates for General Cognitive Ability (GCA), Googleyness (navigating ambiguity), and scalable architecture."
        } else if lower.contains("meta") || lower.contains("facebook") {
            return "Evaluates for Move Fast velocity, high-scale system design, and Long-Term Impact."
        } else if lower.contains("apple") {
            return "Evaluates for precision craftsmanship, hardware/software empathy, user privacy, and attention to detail."
        } else if lower.contains("netflix") {
            return "Evaluates for Freedom & Responsibility, extreme autonomy, and Context Not Control."
        } else if lower.contains("microsoft") {
            return "Evaluates for Growth Mindset, Customer Empathy, and cross-team collaboration."
        } else if lower.contains("stripe") {
            return "Evaluates for first-principles engineering, operational resilience, and extreme written clarity."
        } else {
            return "Calibrates questions and evaluation to \(trimmed)'s specific engineering culture and domain challenges."
        }
    }
}
