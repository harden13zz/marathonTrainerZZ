import Foundation
import HealthKit

/// 恢复评估：HRV + 睡眠 + 静息心率 → 恢复等级
@MainActor
final class RecoveryAssessor {

    let hrService = LiveHeartRateService()

    struct RecoveryInputs {
        var hrvSdnn: Double?
        var sleepTotalMin: Double?
        var sleepDeepMin: Double?
        var restingHR: Double?
    }

    /// 从 HealthKit 读取今日恢复数据
    func fetchTodayRecovery() async -> RecoveryInputs {
        async let hrv = hrService.fetchMorningHRV()
        async let sleep = hrService.fetchSleepAnalysis()
        async let resting = hrService.fetchRestingHeartRate()

        let (hrvValue, sleepValue, restingValue) = await (hrv, sleep, resting)

        return RecoveryInputs(
            hrvSdnn: hrvValue,
            sleepTotalMin: sleepValue?.total,
            sleepDeepMin: sleepValue?.deep,
            restingHR: restingValue
        )
    }

    /// 评估恢复等级
    func assess(inputs: RecoveryInputs, baselineHrv: Double? = nil) -> RecoverySnapshot {
        var score = 0
        var reasons: [String] = []

        // HRV 评估
        if let hrv = inputs.hrvSdnn {
            if let baseline = baselineHrv {
                if hrv >= baseline * 0.9 { 
                    score += 2 
                } else if hrv >= baseline * 0.7 { 
                    score += 1
                    reasons.append("HRV 低于基线")
                } else {
                    reasons.append("HRV 显著低于基线")
                }
            } else {
                if hrv >= 50 { 
                    score += 2 
                } else if hrv >= 30 { 
                    score += 1
                    reasons.append("HRV 偏低 (\(Int(hrv))ms)")
                } else {
                    reasons.append("HRV 过低 (\(Int(hrv))ms)")
                }
            }
        } else {
            reasons.append("无 HRV 数据")
        }

        // 睡眠评估
        if let total = inputs.sleepTotalMin {
            if total >= 420 { 
                score += 2 
            } else if total >= 360 { 
                score += 1
                reasons.append("睡眠不足 (\(Int(total/60))h\(Int(total.truncatingRemainder(dividingBy: 60)))m)")
            } else {
                reasons.append("睡眠严重不足 (\(Int(total/60))h\(Int(total.truncatingRemainder(dividingBy: 60)))m)")
            }
        } else {
            reasons.append("无睡眠数据")
        }

        // 深睡比例
        if let total = inputs.sleepTotalMin, let deep = inputs.sleepDeepMin, total > 0 {
            let deepRatio = deep / total
            if deepRatio >= 0.2 { 
                score += 1 
            } else {
                reasons.append("深睡比例偏低")
            }
        }

        // 静息心率
        if let resting = inputs.restingHR {
            if resting <= 60 { 
                score += 1 
            } else if resting <= 70 { 
                score += 0 
            } else { 
                score -= 1
                reasons.append("静息心率偏高 (\(Int(resting))bpm)")
            }
        } else {
            reasons.append("无静息心率数据")
        }

        let level: RecoverySnapshot.RecoveryLevel
        switch score {
        case 0...2: level = .highFatigue
        case 3...4: level = .mildFatigue
        default: level = .normal
        }

        return RecoverySnapshot(
            morningHrvSdnn: inputs.hrvSdnn,
            restingHr: inputs.restingHR,
            sleepTotalMin: inputs.sleepTotalMin,
            sleepDeepMin: inputs.sleepDeepMin,
            recoveryLevel: level,
            recoveryReasons: reasons
        )
    }
}
