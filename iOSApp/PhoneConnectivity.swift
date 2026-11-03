//
//  PhoneConnectivity.swift
//  iOS —— WCSession 手机端封装（Step 0）
//
//  设计要点（也是 Task 6 的地基）：
//  - 全部状态在 MainActor 上维护，UI 直接观察 ObservableObject；
//  - 用 updateApplicationContext 而不是 sendMessage 做「下发」：
//    sendMessage 要求对方 App 正在前台，自用场景基本不成立；
//    updateApplicationContext 会排队，手表下次启动时自动送达。
//  - 所有回调都打日志，Step 0 的验收就是「跑通一次并看到日志」。
//

import Foundation
import WatchConnectivity

/// 手机端收到的一条回执
struct PhoneInboxEntry: Identifiable, Equatable {
    let id = UUID()
    let payload: OutreachPayload
    let receivedAt: Date
}

@MainActor
final class PhoneConnectivity: NSObject, ObservableObject {

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var pairedDevices: [String] = []
    @Published private(set) var log: [String] = []
    @Published private(set) var replies: [PhoneInboxEntry] = []

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    // MARK: - 生命周期

    /// 在 App 启动 / 页面出现时调用，激活会话
    func activate() {
        guard let session else {
            append("本机不支持 WatchConnectivity")
            return
        }
        if session.activationState == .activated { refreshFlags(); return }

        session.delegate = self
        session.activate()
        append("正在激活 WCSession…")
    }

    private func refreshFlags() {
        guard let session else { return }
        isReachable = session.isReachable
        isPaired = session.isPaired
        pairedDevices = session.isPaired ? ["Apple Watch"] : []
    }

    // MARK: - 发送

    func sendPing(_ text: String) {
        guard let session, session.activationState == .activated else {
            append("发送失败：会话未激活")
            return
        }

        let payload = OutreachPayload.ping(text: text)
        do {
            try session.updateApplicationContext(payload.makeDictionary())
            append("已排队下发 applicationContext（手表下次打开时送达）")
        } catch {
            append("updateApplicationContext 失败：\(error.localizedDescription)")
        }

        // 如果手表正好在跑 App，再补一条即时消息，减少等待
        if session.isReachable {
            session.sendMessage(payload.makeDictionary(), replyHandler: nil) { error in
                Task { @MainActor in
                    self.append("sendMessage 即时投递失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 日志

    func append(_ line: String) {
        let stamp = Self.formatter.string(from: Date())
        log.insert("[\(stamp)] \(line)", at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - WCSessionDelegate

extension PhoneConnectivity: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let stateText: String
        switch activationState {
        case .activated: stateText = "已激活"
        case .inactive: stateText = "非活跃"
        case .notActivated: stateText = "未激活"
        @unknown default: stateText = "未知"
        }
        Task { @MainActor in
            self.append("激活完成：\(stateText)\(error.map { "，错误：\($0.localizedDescription)" } ?? "")")
            self.refreshFlags()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.append("会话进入非活跃（切换手表）") }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.append("会话失效，重新激活")
            session.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.append("可达性变化：\(reachable ? "可达" : "不可达")")
        }
    }

    /// 手表 → 手机：即时消息
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let payload = OutreachPayload.from(dictionary: message) else { return }
        Task { @MainActor in
            self.replies.insert(PhoneInboxEntry(payload: payload, receivedAt: Date()), at: 0)
            self.append("收到手表消息：\(payload.text)")
        }
    }

    /// 手表 → 手机：applicationContext（手表在后台时也会送达）
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = OutreachPayload.from(dictionary: applicationContext) else { return }
        Task { @MainActor in
            self.replies.insert(PhoneInboxEntry(payload: payload, receivedAt: Date()), at: 0)
            self.append("收到手表 applicationContext：\(payload.text)")
        }
    }
}
