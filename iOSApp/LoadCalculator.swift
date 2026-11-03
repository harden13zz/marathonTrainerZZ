import Foundation

/// 训练负荷计算：TRIMP + 7 日/14 日负荷 + ACWR
enum LoadCalculator {

    /// 计算单次训练的 TRIMP（Training Impulse）
    /// TRIMP = duration(min) × HR_ratio × 0.64 × e^(1.92 × HR_ratio)
    /// HR_ratio = (avgHR - restingHR) / (maxHR - restingHR)
    static func trimp(avgHR: Double, restingHR: Double, maxHR: Double, durationMin: Double) -> Double {
        guard maxHR > restingHR, durationMin > 0 else { return 0 }
        let hrRatio = (avgHR - restingHR) / (maxHR - restingHR)
        let clampedRatio = min(max(hrRatio, 0.5), 0.95)
        let weight = 0.64 * exp(1.92 * clampedRatio)
        return durationMin * weight
    }

    /// 计算 N 日内的总 TRIMP
    static func totalTrimp(logs: [TrainingLogRecord], days: Int) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return logs.filter { $0.startTime >= cutoff }.reduce(0) { $0 + $1.trimp }
    }

    /// ACWR（Acute:Chronic Workload Ratio）= 7 日负荷 / 14 日负荷 × 2
    /// 理想范围 0.8-1.3，>1.5 受伤风险高
    static func acwr(logs: [TrainingLogRecord]) -> Double {
        let acute = totalTrimp(logs: logs, days: 7)
        let chronic = totalTrimp(logs: logs, days: 14)
        guard chronic > 0 else { return 1.0 }
        return (acute / chronic) * 2
    }

    /// 负荷等级
    enum LoadLevel {
        case undertraining
        case optimal
        case risky
        case dangerous

        static func from(acwr: Double) -> LoadLevel {
            switch acwr {
            case ..<0.8: return .undertraining
            case 0.8..<1.3: return .optimal
            case 1.3..<1.5: return .risky
            default: return .dangerous
            }
        }
    }
}
