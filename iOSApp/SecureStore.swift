import Foundation
import Security

enum SecureKey: String {
    case llmBaseURL = "mt_llm_base_url"
    case llmAPIKey = "mt_llm_api_key"
    case llmModel = "mt_llm_model"
    case fixedCity = "mt_fixed_city"
    case hrSafeMax = "mt_hr_safe_max"
    case voiceEnabled = "mt_voice_enabled"
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
    }

    private func loadAll() {
        llmBaseURL = get(.llmBaseURL) ?? "https://api.qnaigc.com/v1"
        llmAPIKey = get(.llmAPIKey) ?? ""
        llmModel = get(.llmModel) ?? "deepseek/deepseek-v4-flash-20260731"
        fixedCity = get(.fixedCity) ?? ""
        hrSafeMax = get(.hrSafeMax) ?? "190"
        voiceEnabled = (get(.voiceEnabled) ?? "1") == "1"
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
}
