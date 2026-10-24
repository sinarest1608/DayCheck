import Foundation

struct StatusEntry {
    var date: Date = Date()
    var weightKg: Double = 0
    var waterLiters: Double = 0
    var waterGoalLiters: Double = 3.0
    var steps: Double = 0
    var stepsGoal: Double = 10_000
    var supplementsTaken: Bool = false
    var chamomileTea: Bool = false
    var dietPercent: Int = 100

    var message: String {
        let waterMark = waterLiters >= waterGoalLiters ? "✅" : "❌"
        let stepsMark = steps >= stepsGoal ? "✅" : "❌"
        let supplementsMark = supplementsTaken ? "✅" : "❌"
        let chamomileMark = chamomileTea ? "✅" : "❌"
        let dietMark = dietPercent >= 100 ? "💯" : "\(dietPercent)%"

        return [
            "Status - \(formattedDate)",
            "Weight - \(formattedWeight) Kg",
            "Water - \(formattedWater)L \(waterMark)",
            "Steps - \(formattedSteps) \(stepsMark)",
            "Supplements \(supplementsMark)",
            "Chamomile Tea \(chamomileMark)",
            "Diet \(dietMark)",
        ].joined(separator: "\n")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    private var formattedWeight: String {
        String(format: "%.1f", weightKg)
    }

    private var formattedWater: String {
        Self.truncatedDecimalString(waterLiters)
    }

    private var formattedSteps: String {
        if steps < 1000 {
            return String(Int(steps))
        }
        return "\(Self.truncatedDecimalString(steps / 1000))K"
    }

    /// Truncates (never rounds) to one decimal place so a value like 2.96
    /// never displays as a misleadingly-higher "3.0".
    private static func truncatedDecimalString(_ value: Double) -> String {
        let truncated = (value * 10).rounded(.towardZero) / 10
        if truncated.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(truncated))
        }
        return String(format: "%.1f", truncated)
    }
}
