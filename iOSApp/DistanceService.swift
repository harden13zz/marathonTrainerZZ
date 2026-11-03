import Foundation
import CoreMotion

/// 基于 CoreMotion 的距离估算（免费账号无后台 GPS 的替代方案）
@MainActor
final class DistanceService: ObservableObject {

    @Published var distanceMeters: Double = 0
    @Published var stepCount: Int = 0
    @Published var isTracking = false

    private let pedometer = CMPedometer()
    private var startDate: Date?
    private var baselineSteps: Int = 0
    private var baselineDistance: Double = 0

    func startTracking() {
        guard CMPedometer.isStepCountingAvailable() else {
            isTracking = false
            return
        }

        startDate = Date()
        isTracking = true

        // 获取基线步数
        pedometer.queryPedometerData(from: Date(), to: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.baselineSteps = data.numberOfSteps.intValue
                self.baselineDistance = data.distance?.doubleValue ?? 0
                self.distanceMeters = self.baselineDistance
                self.stepCount = self.baselineSteps
            }
        }

        // 实时更新
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.stepCount = data.numberOfSteps.intValue - self.baselineSteps
                if let dist = data.distance?.doubleValue {
                    self.distanceMeters = dist - self.baselineDistance
                }
            }
        }
    }

    func stopTracking() {
        pedometer.stopUpdates()
        isTracking = false
    }

    func reset() {
        distanceMeters = 0
        stepCount = 0
        baselineSteps = 0
        baselineDistance = 0
    }
}
