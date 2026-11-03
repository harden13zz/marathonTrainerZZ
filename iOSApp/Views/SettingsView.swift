import SwiftUI

struct SettingsView: View {
    @ObservedObject private var secure = SecureStore.shared

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
        }
        .navigationTitle("设置")
    }
}
