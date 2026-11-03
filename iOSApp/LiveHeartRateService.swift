import Foundation
import HealthKit

@MainActor
final class LiveHeartRateService: ObservableObject {

    @Published var currentHeartRate: Double = 0
    @Published var isMonitoring = false
    @Published var error: String?

    private let store = HKHealthStore()
    private var query: HKSampleQuery?
    private var timer: Timer?

    private static let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!

    func startMonitoring(workoutStart: Date) {
        isMonitoring = true
        error = nil
        schedulePolling(workoutStart: workoutStart)
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    private func schedulePolling(workoutStart: Date) {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchLatestHR(since: workoutStart)
            }
        }
        fetchLatestHR(since: workoutStart)
    }

    private func fetchLatestHR(since date: Date) {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: false)]

        let sampleQuery = HKSampleQuery(
            sampleType: Self.heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: sort
        ) { [weak self] results, queryError in
            Task { @MainActor in
                guard let self else { return }
                if let err = queryError {
                    self.error = err.localizedDescription
                    return
                }
                guard let sample = results?.first as? HKQuantitySample else { return }
                let unit = HKUnit.count().unitDivided(by: .minute())
                self.currentHeartRate = sample.quantity.doubleValue(for: unit)
            }
        }
        store.execute(sampleQuery)
    }

    // MARK: - 历史数据查询（Task 2 用）

    func fetchRecentWorkouts(days: Int = 30) async -> [HKWorkout] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(keyPath: \HKWorkout.startDate, ascending: false)]

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: 100, sortDescriptors: sort) { results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    func fetchMorningHRV() async -> Double? {
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: true)]

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: hrvType, predicate: predicate,
                                  limit: 1, sortDescriptors: sort) { results, _ in
                let sample = results?.first as? HKQuantitySample
                let value = sample?.quantity.doubleValue(for: HKUnit.millisecond())
                continuation.resume(returning: value)
            }
            store.execute(q)
        }
    }

    func fetchRestingHeartRate() async -> Double? {
        let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sort = [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: false)]

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: 1, sortDescriptors: sort) { results, _ in
                let sample = results?.first as? HKQuantitySample
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    func fetchSleepAnalysis() async -> (total: Double, deep: Double)? {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { results, _ in
                guard let samples = results as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                var totalMin: Double = 0
                var deepMin: Double = 0
                for s in samples {
                    let dur = s.endDate.timeIntervalSince(s.startDate) / 60
                    totalMin += dur
                    if s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                        deepMin += dur
                    }
                }
                continuation.resume(returning: (totalMin, deepMin))
            }
            store.execute(q)
        }
    }
}
