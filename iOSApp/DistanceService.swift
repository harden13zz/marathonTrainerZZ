import Foundation
import CoreMotion
import CoreLocation

/// 基于 GPS + 计步器的距离和配速计算
@MainActor
final class DistanceService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var distanceMeters: Double = 0
    @Published var stepCount: Int = 0
    @Published var currentPaceSecPerKm: Double?  // 当前配速（秒/公里）
    @Published var averagePaceSecPerKm: Double?  // 平均配速
    @Published var isTracking = false
    @Published var locationError: String?

    private let pedometer = CMPedometer()
    private let locationManager = CLLocationManager()
    private var startDate: Date?
    private var baselineSteps: Int = 0
    private var baselineDistance: Double = 0
    private var lastLocation: CLLocation?
    private var locationUpdates: [CLLocation] = []
    
    override init() {
        super.init()
    }

    func startTracking() {
        // 配置 GPS
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5  // 每 5 米更新一次
        locationManager.requestWhenInUseAuthorization()
        
        let authStatus = locationManager.authorizationStatus
        if authStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if authStatus == .denied || authStatus == .restricted {
            locationError = "定位权限被拒绝，请在设置中允许"
            // 降级到计步器
            startPedometerOnly()
            return
        }
        
        startDate = Date()
        isTracking = true
        locationUpdates = []
        lastLocation = nil
        
        // 启动 GPS
        locationManager.startUpdatingLocation()
        
        // 同时启动计步器作为备用
        startPedometer()
    }
    
    private func startPedometerOnly() {
        startDate = Date()
        isTracking = true
        startPedometer()
    }
    
    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }

        pedometer.queryPedometerData(from: Date(), to: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.baselineSteps = data.numberOfSteps.intValue
                self.baselineDistance = data.distance?.doubleValue ?? 0
                self.distanceMeters = self.baselineDistance
                self.stepCount = self.baselineSteps
            }
        }

        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.stepCount = data.numberOfSteps.intValue - self.baselineSteps
                if let dist = data.distance?.doubleValue {
                    self.distanceMeters = max(self.distanceMeters, dist - self.baselineDistance)
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
        currentPaceSecPerKm = nil
        averagePaceSecPerKm = nil
        lastLocation = nil
        locationUpdates = []
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                // 过滤掉精度太差的位置
                guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 50 else { continue }
                
                if let last = lastLocation {
                    let distance = location.distance(from: last)
                    // 过滤掉异常跳变（>100 米/秒 认为是 GPS 漂移）
                    let timeDiff = location.timestamp.timeIntervalSince(last.timestamp)
                    guard timeDiff > 0, distance / timeDiff < 100 else { continue }
                    
                    distanceMeters += distance
                    locationUpdates.append(location)
                    
                    // 计算当前配速（基于最近 100 米）
                    calculatePace(from: locationUpdates)
                }
                
                lastLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationError = "定位失败：\(error.localizedDescription)"
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                locationError = "定位权限被拒绝"
                isTracking = false
            case .authorizedWhenInUse, .authorizedAlways:
                locationError = nil
            default:
                break
            }
        }
    }
    
    private func calculatePace(from locations: [CLLocation]) {
        guard locations.count >= 2 else { return }
        
        // 取最近 100 米计算配速
        var recentDistance: Double = 0
        var recentTime: TimeInterval = 0
        
        for i in stride(from: locations.count - 1, to: 0, by: -1) {
            let dist = locations[i].distance(from: locations[i-1])
            let time = locations[i].timestamp.timeIntervalSince(locations[i-1].timestamp)
            
            recentDistance += dist
            recentTime += time
            
            if recentDistance >= 100 { break }
        }
        
        guard recentDistance > 0, recentTime > 0 else { return }
        
        // 配速 = 时间 / 距离（秒/公里）
        let paceSecPerKm = recentTime / (recentDistance / 1000.0)
        currentPaceSecPerKm = paceSecPerKm
        
        // 平均配速
        if let start = startDate {
            let totalTime = Date().timeIntervalSince(start)
            if distanceMeters > 0 {
                averagePaceSecPerKm = totalTime / (distanceMeters / 1000.0)
            }
        }
    }
}
