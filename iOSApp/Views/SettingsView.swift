import SwiftUI

struct SettingsView: View {
    @ObservedObject private var secure = SecureStore.shared
    @State private var healthTestResult = ""

    var body: some View {
        Form {
            Section("大模型 API") {
                TextField("Base URL", text: $secure.llmBaseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $secure.llmAPIKey)
                TextField("模型名称", text: $secure.llmModel)
                    .autocorrectionDisabled()
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
