//
//  WatchContentView.swift
//  watchOS —— Step 0 验证页
//
//  验证目标：
//  1. Watch App 能被 Sideloadly / 覆盖重签安装到手表并打开；
//  2. 手表能收到 iPhone 下发的测试包，并能回执；
//  3. HKWorkoutSession 能在手表上启动、拿到实时心率、结束并写入健康库。
//
//  Task 7 会把这个页面替换成「课表状态机」：分段倒计时 / 距离进度、
//  配速与心率区间判定、震动 + 语音提醒。
//

import SwiftUI

struct WatchContentView: View {

    @StateObject private var connectivity = WatchConnectivityClient()
    @StateObject private var workout = WorkoutService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {

                // MARK: 连接状态
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivity.isReachable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(connectivity.isReachable ? "手机可达" : "手机暂不可达")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // MARK: 收到的消息
                VStack(alignment: .leading, spacing: 2) {
                    Text("来自手机")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(connectivity.lastIncomingText)
                        .font(.footnote)
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

                // MARK: 运动指标
                Group {
                    WatchMetricRow(label: "时长", value: workout.elapsedText)
                    WatchMetricRow(label: "心率", value: NumberFormat.heartRate(workout.heartRate) + " bpm")
                    WatchMetricRow(label: "距离", value: NumberFormat.distance(workout.distanceMeters))
                    WatchMetricRow(label: "消耗", value: NumberFormat.calories(workout.activeCalories))
                }
                .padding(.vertical, 2)

                // MARK: 控件
                switch workout.state {
                case .idle:
                    Button {
                        workout.start()
                    } label: {
                        Label("开始跑步", systemImage: "figure.run")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                case .running:
                    HStack {
                        Button {
                            workout.pause()
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .tint(.yellow)
                        Button {
                            workout.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .tint(.red)
                    }

                case .paused:
                    HStack {
                        Button {
                            workout.resume()
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .tint(.green)
                        Button {
                            workout.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .tint(.red)
                    }

                case .finished:
                    Text("已结束，运动记录已写入健康库")
                        .font(.caption2)
                        .foregroundStyle(.green)

                case .failed(let message):
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                // MARK: 回执按钮
                Button {
                    let elapsed = workout.state == .idle ? "idle" : workout.elapsedText
                    let hr = NumberFormat.heartRate(workout.heartRate)
                    connectivity.sendReply(text: "watch: \(elapsed) HR=\(hr)")
                } label: {
                    Label("回执手机", systemImage: "arrow.up.message")
                }
                .buttonStyle(.bordered)
                .font(.caption)

                // MARK: 日志
                if !connectivity.log.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日志")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(Array(connectivity.log.prefix(6).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .onAppear {
            connectivity.activate()
        }
    }
}

#if DEBUG
#Preview {
    WatchContentView()
}
#endif
