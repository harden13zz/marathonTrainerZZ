//
//  WorkoutService.swift
//  watchOS —— HKWorkoutSession + HKLiveWorkoutBuilder 最小实现（Step 0）
//
//  验证目标：免费签名下，手表上的 WorkoutSession 能否启动、能否拿到实时心率、
//  结束后能否把本次运动写进系统健康库（并同步到 iPhone 的「健身」App）。
//
//  Task 7 会在此基础上扩展为：分段状态机、配速区间判定、震动 + 语音提醒、
//  完整时序日志缓存。这里只做「能跑起来」的最小闭环。
//

import Foundation
import HealthKit

@MainActor
final class WorkoutService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case paused
        case finished
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?

    // MARK: - 权限

    /// 需要「写」运动记录 + 「读」心率/距离；手表侧必须自己拥有这些权限。
    private static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let dist = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(dist) }
        return types
    }

    func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(NSError(domain: "MT", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "本机无 HealthKit"])))
            return
        }
        store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes) { ok, error in
            if let error {
                completion(.failure(error))
            } else if !ok {
                completion(.failure(NSError(domain: "MT", code: 2,
                                            userInfo: [NSLocalizedDescriptionKey: "用户未授权"])))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - 会话控制

    func start() {
        requestAuthorization { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                case .success:
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }

            state = .running
            elapsed = 0
            startTimer()
        } catch {
            state = .failed("无法启动 WorkoutSession：\(error.localizedDescription)")
        }
    }

    func pause() {
        guard state == .running else { return }
        session?.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        session?.resume()
        state = .running
    }

    func stop() {
        guard state == .running || state == .paused else { return }
        session?.end()
        stopTimer()
    }

    // MARK: - 计时

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                self.elapsed += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 供 UI 显示的格式化字符串
    var elapsedText: String {
        let total = Int(elapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutService: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .ended:
                self.state = .finished
                self.builder?.endCollection(withEnd: date) { _, _ in
                    self.builder?.finishWorkout { _, error in
                        if let error {
                            Task { @MainActor in
                                self.state = .failed("保存运动失败：\(error.localizedDescription)")
                            }
                        }
                    }
                }
                self.stopTimer()
            case .running:
                self.state = .running
            case .paused:
                self.state = .paused
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
            self.stopTimer()
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutService: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // 取出心率 / 卡路里 / 距离的最近值
        var newHR: Double?
        var newEnergy: Double?
        var newDistance: Double?

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                newHR = statistics.mostRecentQuantity()?.doubleValue(for: unit)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                newEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                newDistance = statistics.sumQuantity()?.doubleValue(for: .meter())
            default:
                break
            }
        }

        Task { @MainActor in
            if let newHR { self.heartRate = newHR }
            if let newEnergy { self.activeCalories = newEnergy }
            if let newDistance { self.distanceMeters = newDistance }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Step 0 不处理事件（暂停/恢复由 UI 驱动）
    }
}
