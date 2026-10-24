import Foundation
import HealthKit

@Observable
final class HealthKitManager {
    static let stepCountType = HKQuantityType(.stepCount)
    static let waterType = HKQuantityType(.dietaryWater)
    static let weightType = HKQuantityType(.bodyMass)

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private let store = HKHealthStore()

    func requestAuthorization() async {
        guard isAvailable else { return }
        let readTypes: Set<HKObjectType> = [Self.stepCountType, Self.waterType, Self.weightType]
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Apps and devices (e.g. "Zepp", "iPhone") that have written samples of this type.
    func sources(for type: HKQuantityType) async -> [HKSource] {
        guard isAvailable else { return [] }
        let descriptor = HKSourceQueryDescriptor(predicate: .quantitySample(type: type))
        let sources = (try? await descriptor.result(for: store)) ?? []
        return sources.sorted { $0.name < $1.name }
    }

    /// Cumulative total for `type` on the calendar day containing `date`.
    /// Pass `nil` for `sourceBundleID` to sum across all sources.
    func total(
        for type: HKQuantityType,
        unit: HKUnit,
        date: Date,
        sourceBundleID: String?
    ) async -> Double? {
        guard let predicate = await dayPredicate(for: type, date: date, sourceBundleID: sourceBundleID) else {
            return nil
        }
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let descriptor = HKSampleQueryDescriptor(predicates: [samplePredicate], sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store) else { return nil }

        // Some sources mirror the exact same log entry into HealthKit more than once
        // (e.g. a paired device and its companion app both syncing the same entry).
        // A plain statistics sum would double-count those, so de-duplicate any samples
        // that share a start time, end time, and quantity before summing.
        var seenKeys = Set<String>()
        var sum = 0.0
        for sample in samples {
            let value = sample.quantity.doubleValue(for: unit)
            let key = "\(sample.startDate.timeIntervalSince1970)|\(sample.endDate.timeIntervalSince1970)|\(value)"
            if seenKeys.insert(key).inserted {
                sum += value
            }
        }
        return sum
    }

    /// Most recent discrete sample for `type` (e.g. a weight scale reading) on the calendar day
    /// containing `date`. Pass `nil` for `sourceBundleID` to consider samples from any source.
    func latestSample(
        for type: HKQuantityType,
        unit: HKUnit,
        date: Date,
        sourceBundleID: String?
    ) async -> Double? {
        guard let predicate = await dayPredicate(for: type, date: date, sourceBundleID: sourceBundleID) else {
            return nil
        }
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [samplePredicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        let results = try? await descriptor.result(for: store)
        return results?.first?.quantity.doubleValue(for: unit)
    }

    private func dayPredicate(
        for type: HKQuantityType,
        date: Date,
        sourceBundleID: String?
    ) async -> NSPredicate? {
        guard isAvailable else { return nil }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        let dayPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)

        guard let sourceBundleID else { return dayPredicate }

        let matchingSources = await sources(for: type).filter { $0.bundleIdentifier == sourceBundleID }
        guard !matchingSources.isEmpty else { return nil }
        let sourcePredicate = HKQuery.predicateForObjects(from: Set(matchingSources))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [dayPredicate, sourcePredicate])
    }
}
