import Foundation
import Security

enum SecureKey: String {
    case llmBaseURL = "mt_llm_base_url"
    case llmAPIKey = "mt_llm_api_key"
    case llmModel = "mt_llm_model"
    case fixedCity = "mt_fixed_city"
    case hrSafeMax = "mt_hr_safe_max"
    case voiceEnabled = "mt_voice_enabled"
    case runnerAge = "mt_runner_age"
    case runnerHeight = "mt_runner_height"
    case runnerWeight = "mt_runner_weight"
    case runnerGender = "mt_runner_gender"
    case targetDistance = "mt_target_distance"
    case targetTime = "mt_target_time"
}

@MainActor
final class SecureStore: ObservableObject {

    static let shared = SecureStore()

    @Published var llmBaseURL: String = ""
    @Published var llmAPIKey: String = ""
    @Published var llmModel: String = ""
    @Published var fixedCity: String = ""
    @Published var hrSafeMax: String = "190"
    @Published var voiceEnabled: Bool = true
    @Published var runnerAge: String = "30"
    @Published var runnerHeight: String = "175"
    @Published var runnerWeight: String = "70"
    @Published var runnerGender: String = "male"
    @Published var targetDistance: String = "42.195"
    @Published var targetTime: String = "270"

    private let service = "com.zhangzhen.marathontrainer"

    private init() {
        loadAll()
    }

    func save() {
        set(llmBaseURL, for: .llmBaseURL)
        set(llmAPIKey, for: .llmAPIKey)
        set(llmModel, for: .llmModel)
        set(fixedCity, for: .fixedCity)
        set(hrSafeMax, for: .hrSafeMax)
        set(voiceEnabled ? "1" : "0", for: .voiceEnabled)
        set(runnerAge, for: .runnerAge)
        set(runnerHeight, for: .runnerHeight)
        set(runnerWeight, for: .runnerWeight)
        set(runnerGender, for: .runnerGender)
        set(targetDistance, for: .targetDistance)
        set(targetTime, for: .targetTime)
    }

    private func loadAll() {
        llmBaseURL = get(.llmBaseURL) ?? "https://api.qnaigc.com/v1"
        llmAPIKey = get(.llmAPIKey) ?? ""
        llmModel = get(.llmModel) ?? "deepseek/deepseek-v4-flash-20260731"
        fixedCity = get(.fixedCity) ?? ""
        hrSafeMax = get(.hrSafeMax) ?? "190"
        voiceEnabled = (get(.voiceEnabled) ?? "1") == "1"
        runnerAge = get(.runnerAge) ?? "30"
        runnerHeight = get(.runnerHeight) ?? "175"
        runnerWeight = get(.runnerWeight) ?? "70"
        runnerGender = get(.runnerGender) ?? "male"
        targetDistance = get(.targetDistance) ?? "42.195"
        targetTime = get(.targetTime) ?? "270"
    }

    private func get(_ key: SecureKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func set(_ value: String, for key: SecureKey) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    var userProfile: UserProfileSchema {
        UserProfileSchema(
            age: Int(runnerAge) ?? 30,
            heightCm: Double(runnerHeight) ?? 175,
            weightKg: Double(runnerWeight) ?? 70,
            gender: runnerGender,
            vo2maxEstimate: nil,
            targetMarathonDistanceKm: Double(targetDistance) ?? 42.195,
            targetFinishTimeMin: Int(targetTime) ?? 270
        )
    }
}
