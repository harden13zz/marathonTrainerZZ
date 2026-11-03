//
//  WatchConnectivityClient.swift
//  watchOS —— WCSession 手表端封装（Step 0）
//
//  与 iOS 侧 PhoneConnectivity 对称：接收手机下发、回执给手机。
//  Task 6 会在此基础上增加：接收课表 → 写入本地文件缓存 → 训练结束后回传日志。
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject {

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastIncomingText: String = "（尚未收到手机消息）"
    @Published private(set) var lastIncomingAt: Date?
    @Published private(set) var log: [String] = []

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    func activate() {
        guard let session else {
            append("本机不支持 WatchConnectivity")
            return
        }
        if session.activationState == .activated {
            isReachable = session.isReachable
            return
        }
        session.delegate = self
        session.activate()
        append("正在激活 WCSession…")
    }

    // MARK: - 回执给手机

    /// 把手表当前的「测试包 + 运动会话摘要」回传给手机
    func sendReply(text: String) {
        guard let session, session.activationState == .activated else {
            append("回执失败：会话未激活")
            return
        }
        let payload = OutreachPayload.ping(text: text)
        do {
            try session.updateApplicationContext(payload.makeDictionary())
            append("已排队回执 applicationContext")
        } catch {
            append("回执 updateApplicationContext 失败：\(error.localizedDescription)")
        }

        if session.isReachable {
            session.sendMessage(payload.makeDictionary(), replyHandler: nil) { error in
                Task { @MainActor in
                    self.append("回执即时投递失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 日志

    func append(_ line: String) {
        let stamp = Self.formatter.string(from: Date())
        log.insert("[\(stamp)] \(line)", at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - WCSessionDelegate

extension WatchConnectivityClient: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.append("激活完成：\(activationState == .activated ? "已激活" : "未激活")\(error.map { "，错误：\($0.localizedDescription)" } ?? "")")
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.append("可达性变化：\(reachable ? "可达" : "不可达")")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let payload = OutreachPayload.from(dictionary: message) else { return }
        Task { @MainActor in
            self.lastIncomingText = payload.text
            self.lastIncomingAt = Date()
            self.append("收到手机消息：\(payload.text)")
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = OutreachPayload.from(dictionary: applicationContext) else { return }
        Task { @MainActor in
            self.lastIncomingText = payload.text
            self.lastIncomingAt = Date()
            self.append("收到手机 applicationContext：\(payload.text)")
        }
    }
}
