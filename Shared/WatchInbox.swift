//
//  WatchInbox.swift
//  Shared —— WatchConnectivity 的数据契约（Step 0 版）
//
//  两个 target 共用同一个文件、同一套 key 常量，避免「手机发的 key 和
//  手表读的 key 拼写不一致」这类只在真机上才暴露的低级 bug。
//
//  当前载荷是一个最小的「测试包」：一句话 + 时间戳。
//  Step 1 之后会替换为：课表 DistributionPackage、训练日志 WorkoutLogPackage、
//  以及可选的天气提示 WeatherNotePackage。扩展时保持 key 常量集中在本文件。
//

import Foundation

enum WatchInboxKey {
    /// 测试文本（下发的整包 JSON 字符串）
    static let payload = "payload"
    /// 载荷类型标识，用于后续扩展多消息类型而不破坏兼容性
    static let kind = "kind"
    /// 发送时间戳
    static let sentAt = "sentAt"
}

/// 载荷类型
enum WatchInboxKind: String {
    case ping = "ping"            // Step 0：连通性测试
    case plan = "plan"            // Task 6：课表下发
    case weatherNote = "weather"  // Task 4/6：开跑前天气提醒
}

/// 手机 → 手表的一包数据
struct OutreachPayload: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var text: String
    var sentAt: Date

    static func ping(text: String) -> OutreachPayload {
        OutreachPayload(
            id: UUID().uuidString,
            kind: WatchInboxKind.ping.rawValue,
            text: text,
            sentAt: Date()
        )
    }

    /// 打包成 WatchConnectivity 可用的字典（尽量用 plist 原生类型）
    func makeDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            WatchInboxKey.kind: kind,
            WatchInboxKey.sentAt: sentAt.timeIntervalSince1970,
        ]
        if let data = try? JSONEncoder().encode(self),
           let json = String(data: data, encoding: .utf8) {
            dict[WatchInboxKey.payload] = json
        }
        return dict
    }

    /// 从 WatchConnectivity 字典解包；失败返回 nil，由调用方记日志
    static func from(dictionary: [String: Any]) -> OutreachPayload? {
        if let json = dictionary[WatchInboxKey.payload] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OutreachPayload.self, from: data) {
            return decoded
        }
        // 兜底：老版本 / 手工调试时只传了 kind + sentAt
        guard let kind = dictionary[WatchInboxKey.kind] as? String else { return nil }
        let sentAt = dictionary[WatchInboxKey.sentAt] as? Double ?? Date().timeIntervalSince1970
        return OutreachPayload(
            id: UUID().uuidString,
            kind: kind,
            text: "",
            sentAt: Date(timeIntervalSince1970: sentAt)
        )
    }
}
