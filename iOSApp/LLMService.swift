import Foundation

/// OpenAI 兼容的 LLM 客户端，支持 DeepSeek / 通义 / Kimi / OpenAI
@MainActor
final class LLMService: ObservableObject {

    @Published var isLoading = false
    @Published var lastError: String?

    private let secure = SecureStore.shared

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let response_format: ResponseFormat?

        struct ResponseFormat: Codable {
            let type: String
        }
    }

    struct ChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: ChatMessage
        }
    }

    /// 调用 LLM，返回 assistant 的文本回复
    func chat(systemPrompt: String, userPrompt: String) async throws -> String {
        guard !secure.llmBaseURL.isEmpty, !secure.llmAPIKey.isEmpty else {
            throw LLMError.notConfigured
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let url = URL(string: secure.llmBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(secure.llmAPIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatRequest(
            model: secure.llmModel.isEmpty ? "deepseek-chat" : secure.llmModel,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.3,
            response_format: ChatRequest.ResponseFormat(type: "json_object")
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("无 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.api(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let reply = decoded.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }
        return reply
    }

    /// 调用 LLM 并解析为指定 Codable 类型
    func chatJSON<T: Decodable>(systemPrompt: String, userPrompt: String, as type: T.Type) async throws -> T {
        let text = try await chat(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let data = text.data(using: .utf8) ?? Data()
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LLMError.parseFailed(text.prefix(500).description)
        }
    }

    enum LLMError: LocalizedError {
        case notConfigured
        case network(String)
        case api(Int, String)
        case emptyResponse
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "LLM 未配置：请在设置页填写 Base URL 和 API Key"
            case .network(let msg): return "网络错误：\(msg)"
            case .api(let code, let body): return "API 返回 \(code)：\(body.prefix(200))"
            case .emptyResponse: return "LLM 返回空回复"
            case .parseFailed(let snippet): return "JSON 解析失败：\(snippet)"
            }
        }
    }
}
