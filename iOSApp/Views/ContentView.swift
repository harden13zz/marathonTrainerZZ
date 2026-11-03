//
//  ContentView.swift
//  iOS App —— Step 0 验证页
//
//  验证目标：
//  1. iPhone 与 Apple Watch 的配对 / 授权链路可用；
//  2. WatchConnectivity 双向通信可用（发出 ping，收手表回执）；
//  3. HealthKit 读权限申请不崩（Step 2 才做真实数据）。
//
//  ⚠️ 该文件只用于 Step 0，Step 1 开始由首页 / 历史 / 设置 TabView 替换。
//

import SwiftUI

struct ContentView: View {

    @StateObject private var connectivity = PhoneConnectivity()
    @State private var hkStatus: String = "未申请"
    @State private var pingText: String = "hello from iPhone"

    var body: some View {
        NavigationStack {
            List {

                // MARK: 1. 连接状态
                Section {
                    HStack {
                        Circle()
                            .fill(connectivity.isReachable ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(connectivity.isReachable ? "手表可达（App 在前台）" : "手表暂不可达")
                    }
                    if !connectivity.pairedDevices.isEmpty {
                        Text("已配对：\(connectivity.pairedDevices.joined(separator: "、"))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("WatchConnectivity")
                } footer: {
                    Text("「不可达」是正常的：手表 App 没打开或 iPhone 在后台时，消息会排队，手表下次打开时送达。")
                        .font(.footnote)
                }

                // MARK: 2. 发送测试
                Section("发送测试包") {
                    TextField("测试文本", text: $pingText)
                    Button {
                        connectivity.sendPing(pingText)
                    } label: {
                        Label("发送到手表", systemImage: "paperplane")
                    }
                }

                // MARK: 3. 回执
                Section("从手表收到的回执") {
                    if connectivity.replies.isEmpty {
                        Text("暂无")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(connectivity.replies) { reply in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reply.payload.text)
                                    .font(.body)
                                Text(reply.receivedAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: 4. HealthKit
                Section("HealthKit") {
                    HStack {
                        Text("授权状态")
                        Spacer()
                        Text(hkStatus)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task {
                            hkStatus = await HealthKitService.shared.requestAuthorization()
                        }
                    } label: {
                        Label("申请 HealthKit 权限", systemImage: "heart.text.square")
                    }
                }

                // MARK: 5. 日志
                Section("事件日志") {
                    if connectivity.log.isEmpty {
                        Text("暂无事件")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(connectivity.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("MarathonTrainer")
        }
        .onAppear {
            connectivity.activate()
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
