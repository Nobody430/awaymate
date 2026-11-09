import Foundation
import HealthKit

final class Health {
    static let shared = Health()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private var bodyMass: HKQuantityType { HKQuantityType(.bodyMass) }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(
            toShare: [bodyMass, HKObjectType.workoutType(), HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
                      HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)],
            read: [bodyMass])
    }

    func weights(since start: Date) async throws -> [(date: Date, kg: Double)] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    func saveWeight(_ kg: Double, at date: Date) async throws {
        guard isAvailable else { return }
        let sample = HKQuantitySample(type: bodyMass,
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                      start: date, end: date)
        try await store.save(sample)
    }

    /// Writes a meal's nutrients to Apple Health.
    func saveNutrition(kcal: Double, protein: Double, carbs: Double, fat: Double, at date: Date) async throws {
        guard isAvailable else { return }
        let pairs: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), kcal), (.dietaryProtein, .gram(), protein),
            (.dietaryCarbohydrates, .gram(), carbs), (.dietaryFatTotal, .gram(), fat),
        ]
        let samples = pairs.filter { $0.2 > 0 }.map { id, unit, value in
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date)
        }
        if !samples.isEmpty { try await store.save(samples) }
    }

    func saveStrengthWorkout(start: Date, end: Date) async throws {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
