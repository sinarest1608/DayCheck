import Foundation

struct DailyRecord: Codable, Identifiable {
    var date: Date
    var weightKg: Double
    var waterLiters: Double
    var steps: Double
    var supplementsTaken: Bool
    var chamomileTea: Bool
    var dietPercent: Int

    var id: Date { date }

    init(
        date: Date,
        weightKg: Double,
        waterLiters: Double,
        steps: Double,
        supplementsTaken: Bool,
        chamomileTea: Bool,
        dietPercent: Int
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weightKg = weightKg
        self.waterLiters = waterLiters
        self.steps = steps
        self.supplementsTaken = supplementsTaken
        self.chamomileTea = chamomileTea
        self.dietPercent = dietPercent
    }

    init(from entry: StatusEntry) {
        self.init(
            date: entry.date,
            weightKg: entry.weightKg,
            waterLiters: entry.waterLiters,
            steps: entry.steps,
            supplementsTaken: entry.supplementsTaken,
            chamomileTea: entry.chamomileTea,
            dietPercent: entry.dietPercent
        )
    }
}

/// A Friday–Thursday week of `DailyRecord`s with averages over however many
/// days were actually logged (not padded out to 7).
struct WeekSummary: Identifiable {
    let weekStart: Date
    let weekEnd: Date
    let records: [DailyRecord]

    var id: Date { weekStart }

    var daysLogged: Int { records.count }

    var avgSteps: Double { average { $0.steps } }
    var avgWaterLiters: Double { average { $0.waterLiters } }
    var avgWeightKg: Double { average { $0.weightKg } }
    var avgDietPercent: Double { average { Double($0.dietPercent) } }

    var supplementsDays: Int { records.filter(\.supplementsTaken).count }
    var chamomileDays: Int { records.filter(\.chamomileTea).count }

    private func average(_ value: (DailyRecord) -> Double) -> Double {
        guard !records.isEmpty else { return 0 }
        return records.reduce(0) { $0 + value($1) } / Double(records.count)
    }
}

@Observable
final class HistoryStore {
    private(set) var records: [DailyRecord] = []

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("history.json")
        load()
    }

    /// Upserts by calendar day: a second save for the same date overwrites
    /// the first instead of creating a duplicate entry.
    func save(_ record: DailyRecord) {
        let calendar = Calendar.current
        if let index = records.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: record.date) }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.date < $1.date }
        persist()
    }

    /// Removes any records whose day matches one of `dates`.
    func delete(dates: Set<Date>) {
        let calendar = Calendar.current
        records.removeAll { record in
            dates.contains { calendar.isDate($0, inSameDayAs: record.date) }
        }
        persist()
    }

    /// All recorded weeks, newest first.
    var weeks: [WeekSummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record in
            Self.weekStart(for: record.date, calendar: calendar)
        }
        return grouped
            .map { weekStart, records in
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
                return WeekSummary(
                    weekStart: weekStart,
                    weekEnd: weekEnd,
                    records: records.sorted { $0.date < $1.date }
                )
            }
            .sorted { $0.weekStart > $1.weekStart }
    }

    /// The most recent Friday on or before `date` (weeks run Friday–Thursday).
    private static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // Sunday = 1 ... Saturday = 7
        let daysSinceFriday = (weekday - 6 + 7) % 7
        return calendar.date(byAdding: .day, value: -daysSinceFriday, to: day) ?? day
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([DailyRecord].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
