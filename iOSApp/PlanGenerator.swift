import Foundation
import SwiftData

/// 根据用户画像 + 恢复状态 + 天气生成周计划，写入 SwiftData
@MainActor
final class PlanGenerator {

    let llm = LLMService()

    struct PlanInput {
        var profile: UserProfileSchema
        var recovery: RecoverySnapshot
        var weather: WeatherSnapshot?
        var recentSessions: [TrainingSessionSchema]
        var weekNumber: Int
    }

    /// 生成一周 7 天的训练计划
    func generateWeeklyPlan(input: PlanInput, context: ModelContext) async throws -> [TrainingSessionRecord] {
        // 计算训练配速区间
        let targetPaceSecPerKm = Double(input.profile.targetFinishTimeMin * 60) / input.profile.targetMarathonDistanceKm
        let easyPace = targetPaceSecPerKm * 1.25  // 轻松跑比目标配速慢 25%
        let thresholdPace = targetPaceSecPerKm * 1.05  // 阈值跑比目标配速慢 5%
        let intervalPace = targetPaceSecPerKm * 0.95  // 间歇跑比目标配速快 5%
        
        let systemPrompt = """
        你是专业马拉松教练。根据跑者数据和目标生成一周 7 天的马拉松训练计划。
        
        跑者目标：
        - 目标马拉松距离：\(input.profile.targetMarathonDistanceKm) km
        - 目标完赛时间：\(input.profile.targetFinishTimeMin) 分钟
        - 目标配速：\(PaceParser.fromSecondsPerKm(targetPaceSecPerKm)) /km
        
        配速区间（基于目标配速计算）：
        - 轻松跑 (Easy): \(PaceParser.fromSecondsPerKm(easyPace)) /km
        - 阈值跑 (Threshold): \(PaceParser.fromSecondsPerKm(thresholdPace)) /km
        - 间歇跑 (Interval): \(PaceParser.fromSecondsPerKm(intervalPace)) /km
        
        输出必须是严格 JSON，格式为 {"sessions": [...]}，每个 session 符合以下 Schema：
        {
          "id": "UUID 字符串",
          "sessionType": "LSD|interval|threshold|easy|rest|crossTraining",
          "title": "简短标题（如：轻松跑 8km、间歇跑 6x1km）",
          "totalDistanceKm": 数字或 null,
          "totalEstimatedTimeMin": 整数或 null,
          "segments": [{"segmentId":"UUID","segmentType":"distance|time","startKm":null,"endKm":null,"startTimeSec":null,"endTimeSec":null,"paceLow":"M:SS","paceHigh":"M:SS","hrLow":整数,"hrHigh":整数,"note":"说明"}],
          "weatherNote": "天气备注或 null",
          "wasDowngraded": false
        }
        
        马拉松训练规则：
        1. 一周 7 天安排：
           - 周一：休息 (rest)
           - 周二：轻松跑 (easy) 6-10km
           - 周三：间歇跑 (interval) 或 阈值跑 (threshold)
           - 周四：轻松跑 (easy) 6-8km
           - 周五：休息 (rest) 或 交叉训练 (crossTraining)
           - 周六：轻松跑 (easy) 8-12km
           - 周日：长距离跑 (LSD) 15-30km（根据训练周期调整）
        
        2. LSD 规则：
           - 距离不超过周跑量 40%
           - 配速用轻松跑配速 \(PaceParser.fromSecondsPerKm(easyPace)) /km
           - 心率区间：最大心率 65-75%
        
        3. 间歇跑规则：
           - 用间歇配速 \(PaceParser.fromSecondsPerKm(intervalPace)) /km
           - 心率区间：最大心率 85-95%
           - 例如：6x1km 间歇，每组 1km，组间休息 2-3 分钟
        
        4. 阈值跑规则：
           - 用阈值配速 \(PaceParser.fromSecondsPerKm(thresholdPace)) /km
           - 心率区间：最大心率 80-90%
           - 例如：20 分钟阈值跑 或 3x3km 阈值跑
        
        5. 轻松跑规则：
           - 用轻松跑配速 \(PaceParser.fromSecondsPerKm(easyPace)) /km
           - 心率区间：最大心率 65-75%
        
        6. 调整规则：
           - 如果 recovery.recoveryLevel 是 highFatigue，整体降强度 20%，减少距离
           - 如果 weather.riskLevel 是 high，户外跑改室内或降强度
           - 周跑量每周增加不超过 10%
        
        请根据跑者当前状态和目标，生成科学合理的马拉松训练计划。
        """

        let inputDoc = LLMInput(
            userProfile: input.profile,
            recoverySnapshot: input.recovery,
            loadSnapshot: LoadSnapshot(last7dTrimp: 0, last14dTrimp: 0, acwrSimple: 1.0),
            weatherSnapshot: input.weather,
            recentSessions: input.recentSessions,
            originalSession: nil,
            forceOriginal: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let userPrompt = "跑者数据：\(String(data: try encoder.encode(inputDoc), encoding: .utf8) ?? "")\n\n请生成本周（第 \(input.weekNumber) 周）计划。"

        struct PlanResponse: Decodable {
            let sessions: [TrainingSessionSchema]
        }

        let plan = try await llm.chatJSON(systemPrompt: systemPrompt, userPrompt: userPrompt, as: PlanResponse.self)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: today) + 1, to: today) ?? today

        var records: [TrainingSessionRecord] = []
        for (offset, session) in plan.sessions.enumerated() {
            let sessionDate = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? today
            let segEncoder = JSONEncoder()
            segEncoder.dateEncodingStrategy = .iso8601
            let segmentsJson = String(data: try segEncoder.encode(session.segments), encoding: .utf8) ?? "[]"

            let record = TrainingSessionRecord(
                id: session.id,
                date: sessionDate,
                sessionType: session.sessionType.rawValue,
                title: session.title,
                segmentsJson: segmentsJson,
                totalDistanceKm: session.totalDistanceKm,
                totalEstimatedTimeMin: session.totalEstimatedTimeMin,
                wasDowngraded: session.wasDowngraded,
                weatherNote: session.weatherNote
            )
            context.insert(record)
            records.append(record)
        }
        try context.save()
        return records
    }
}
