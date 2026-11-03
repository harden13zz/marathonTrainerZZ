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
        let systemPrompt = """
        你是专业马拉松教练。根据跑者数据生成一周 7 天的训练计划。
        输出必须是严格 JSON，格式为 {"sessions": [...]}，每个 session 符合以下 Schema：
        {
          "id": "UUID 字符串",
          "sessionType": "LSD|interval|threshold|easy|rest|crossTraining",
          "title": "简短标题",
          "totalDistanceKm": 数字或 null,
          "totalEstimatedTimeMin": 整数或 null,
          "segments": [{"segmentId":"UUID","segmentType":"distance|time","startKm":null,"endKm":null,"startTimeSec":null,"endTimeSec":null,"paceLow":"M:SS","paceHigh":"M:SS","hrLow":整数,"hrHigh":整数,"note":"说明"}],
          "weatherNote": "天气备注或 null",
          "wasDowngraded": false
        }
        规则：
        - 一周 7 天，至少 2 天休息或交叉训练
        - LSD 安排在周末，距离不超过周跑量 40%
        - 间歇/阈值跑安排在周中，配速按 VO2max 估算
        - 如果 recovery.recoveryLevel 是 highFatigue，整体降强度 20%
        - 如果 weather.riskLevel 是 high，户外跑改室内或降强度
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
