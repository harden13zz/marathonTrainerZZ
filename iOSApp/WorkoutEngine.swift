import Foundation
import AVFoundation
import UIKit

@MainActor
final class WorkoutEngine: ObservableObject {

    enum EngineState: Equatable {
        case idle
        case running
        case paused
        case finished
        case failed(String)
    }

    @Published var state: EngineState = .idle
    @Published var currentSegmentIndex: Int = 0
    @Published var elapsedSec: TimeInterval = 0
    @Published var distanceMeters: Double = 0
    @Published var currentHR: Double = 0
    @Published var currentPaceSecPerKm: Double?
    @Published var alertMessage: String?

    private(set) var session: TrainingSessionSchema?
    private var timer: Timer?
    private var startTime: Date?
    private let hrService = LiveHeartRateService()
    private let distanceService = DistanceService()
    private let speechSynth = AVSpeechSynthesizer()

    var currentSegment: Segment? {
        guard let segs = session?.segments, currentSegmentIndex < segs.count else { return nil }
        return segs[currentSegmentIndex]
    }

    var totalSegments: Int { session?.segments.count ?? 0 }

    var elapsedText: String {
        let total = Int(elapsedSec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - 控制

    func start(session: TrainingSessionSchema) {
        self.session = session
        currentSegmentIndex = 0
        elapsedSec = 0
        distanceMeters = 0
        state = .running
        startTime = Date()

        hrService.startMonitoring(workoutStart: Date())
        distanceService.startTracking()
        startTimer()
        speak("开始训练：\(session.title)")
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        timer?.invalidate()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }

    func stop() {
        state = .finished
        timer?.invalidate()
        hrService.stopMonitoring()
        distanceService.stopTracking()
        speak("训练结束")
    }

    // MARK: - 计时与判定

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard state == .running else { return }
        elapsedSec += 1
        currentHR = hrService.currentHeartRate
        distanceMeters = distanceService.distanceMeters

        if let dist = estimateDistance() {
            distanceMeters = max(distanceMeters, dist)
        }

        evaluateSegment()
        checkAlerts()
    }

    private func estimateDistance() -> Double? {
        return nil
    }

    private func evaluateSegment() {
        guard let seg = currentSegment else { return }

        switch seg.segmentType {
        case .time:
            if let endSec = seg.endTimeSec, elapsedSec >= Double(endSec) {
                advanceSegment()
            }
        case .distance:
            if let endKm = seg.endKm, distanceMeters / 1000.0 >= endKm {
                advanceSegment()
            }
        }
    }

    private func advanceSegment() {
        guard let segs = session?.segments else { return }
        if currentSegmentIndex + 1 >= segs.count {
            stop()
        } else {
            currentSegmentIndex += 1
            let seg = segs[currentSegmentIndex]
            speak("进入第\(currentSegmentIndex + 1)段：\(seg.note ?? "")")
        }
    }

    private func checkAlerts() {
        guard let seg = currentSegment else { return }

        if let hrHigh = seg.hrHigh, currentHR > Double(hrHigh) {
            triggerAlert("心率过高，请减速")
        } else if let hrLow = seg.hrLow, currentHR > 0, currentHR < Double(hrLow) {
            triggerAlert("心率偏低，请加速")
        }

        if let paceHigh = seg.paceHigh, let paceSec = PaceParser.toSecondsPerKm(paceHigh),
           let currentPace = currentPaceSecPerKm, currentPace > paceSec {
            triggerAlert("配速偏慢")
        } else if let paceLow = seg.paceLow, let paceSec = PaceParser.toSecondsPerKm(paceLow),
                  let currentPace = currentPaceSecPerKm, currentPace < paceSec {
            triggerAlert("配速偏快")
        }
    }

    private var lastAlertTime: Date?

    private func triggerAlert(_ message: String) {
        let now = Date()
        guard now.timeIntervalSince(lastAlertTime ?? .distantPast) > 15 else { return }
        lastAlertTime = now
        alertMessage = message
        triggerHaptic()
        if SecureStore.shared.voiceEnabled {
            speak(message)
        }
    }

    private func triggerHaptic() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.warning)
    }

    private func speak(_ text: String) {
        guard SecureStore.shared.voiceEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        speechSynth.speak(utterance)
    }

    // MARK: - 生成日志

    func buildLog() -> WorkoutLog? {
        guard let session, let start = startTime else { return nil }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        let trimp = calculateTRIMP(avgHR: currentHR, duration: duration)

        return WorkoutLog(
            sessionId: session.id,
            startTime: start,
            endTime: end,
            totalDistanceMeters: distanceMeters,
            totalDurationSec: duration,
            avgHeartRate: currentHR,
            maxHeartRate: currentHR,
            trimp: trimp,
            segmentResults: []
        )
    }

    private func calculateTRIMP(avgHR: Double, duration: TimeInterval) -> Double {
        guard let profile = UserProfile.current, avgHR > 0 else { return 0 }
        let maxHR = 220.0 - Double(profile.age)
        let hrRatio = avgHR / maxHR
        let weight = 0.64 * exp(1.92 * hrRatio)
        return weight * (duration / 60.0)
    }
}

// MARK: - 用户画像简易访问（从 SwiftData 读取，暂用静态缓存）

struct UserProfile {
    var age: Int

    static var current: UserProfile? {
        UserProfile(age: 30)
    }
}
