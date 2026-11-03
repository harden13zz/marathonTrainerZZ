import SwiftUI

struct SettingsView: View {
    @ObservedObject private var secure = SecureStore.shared
    @State private var healthTestResult = ""

    var body: some View {
        Form {
            Section("⚠️ 首次使用配置") {
                Text("请在下方填写七牛 API Key（从 https://portal.qiniu.com/ai-inference/api-key 获取）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API Key", text: $secure.llmAPIKey)
                Text("Base URL 和模型已自动配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("跑者档案") {
                TextField("年龄", text: $secure.runnerAge)
                    .keyboardType(.numberPad)
                TextField("身高 (cm)", text: $secure.runnerHeight)
                    .keyboardType(.decimalPad)
                TextField("体重 (kg)", text: $secure.runnerWeight)
                    .keyboardType(.decimalPad)
                Picker("性别", selection: $secure.runnerGender) {
                    Text("男").tag("male")
                    Text("女").tag("female")
                }
                TextField("目标马拉松距离 (km)", text: $secure.targetDistance)
                    .keyboardType(.decimalPad)
                TextField("目标完赛时间 (分钟)", text: $secure.targetTime)
                    .keyboardType(.numberPad)
                    .foregroundStyle(.secondary)
                Text("例如：270 分钟 = 4 小时 30 分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("天气与定位") {
                TextField("固定城市（留空则用定位）", text: $secure.fixedCity)
            }

            Section("训练安全") {
                TextField("心率安全上限", text: $secure.hrSafeMax)
                    .keyboardType(.numberPad)
                Toggle("语音提醒", isOn: $secure.voiceEnabled)
            }

            Section {
                Button("保存设置") {
                    secure.save()
                }
                .buttonStyle(.borderedProminent)
            }

            Section("健康数据") {
                Button("测试健康授权") {
                    Task {
                        healthTestResult = "正在请求授权..."
                        let service = LiveHeartRateService()
                        service.startMonitoring(workoutStart: Date())
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if service.currentHeartRate > 0 {
                            healthTestResult = "✅ 授权成功，心率：\(Int(service.currentHeartRate)) bpm"
                        } else if let err = service.error {
                            healthTestResult = "❌ 错误：\(err)"
                        } else {
                            healthTestResult = "⚠️  授权成功但暂无心率数据（确保 Apple Watch 正在测量）"
                        }
                        service.stopMonitoring()
                    }
                }
                .tint(.blue)

                if !healthTestResult.isEmpty {
                    Text(healthTestResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
    }
}
