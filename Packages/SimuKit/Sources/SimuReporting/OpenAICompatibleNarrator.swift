import Foundation
import Security
import SimuCore

/// OpenAI-compatible chat completions. The key is read at call time from the
/// environment or the keychain and is never written into the evidence pack.
public struct OpenAICompatibleNarrator: ReportNarrator {
    public var baseURL: URL
    public var model: String
    public var keyProvider: @Sendable () -> String?
    public var log: @Sendable (String) -> Void
    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        baseURL: URL,
        model: String = "unspecified",
        keyProvider: @escaping @Sendable () -> String? = OpenAICompatibleNarrator.keyFromEnvironmentOrKeychain,
        log: @escaping @Sendable (String) -> Void = { _ in },
        transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.keyProvider = keyProvider
        self.log = log
        self.transport = transport ?? Self.urlSessionTransport
    }

    /// Nil when `SIMUNOW_REPORT_BASE_URL` is unset. No vendor host is hardcoded.
    public static func configuredFromEnvironment() -> OpenAICompatibleNarrator? {
        guard let raw = ProcessInfo.processInfo.environment["SIMUNOW_REPORT_BASE_URL"],
              let url = URL(string: raw),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        let model = ProcessInfo.processInfo.environment["SIMUNOW_REPORT_MODEL"] ?? "unspecified"
        return OpenAICompatibleNarrator(baseURL: url, model: model)
    }

    public func narrate(_ evidence: ReportEvidence) async -> ReportNarration? {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            log("叙述器未配置 API 密钥，改为证据 PDF")
            return nil
        }
        do {
            var request = URLRequest(url: chatCompletionsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, evidence: evidence))
            let (data, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log("叙述器请求失败，改为证据 PDF")
                return nil
            }
            guard let narration = try? decodeNarration(data) else {
                log("叙述器返回无法解析，改为证据 PDF")
                return nil
            }
            return narration
        } catch {
            log("叙述器请求失败，改为证据 PDF")
            return nil
        }
    }

    /// Environment variable first, then a generic-password keychain item. Neither is logged.
    public static func keyFromEnvironmentOrKeychain() -> String? {
        if let env = ProcessInfo.processInfo.environment["SIMUNOW_REPORT_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return keychainKey()
    }

    private var chatCompletionsURL: URL {
        var root = baseURL.absoluteString
        if root.hasSuffix("/") {
            root.removeLast()
        }
        return URL(string: root + "/v1/chat/completions") ?? baseURL
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    private static func keychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.simunow.report",
            kSecAttrAccount as String: "SIMUNOW_REPORT_API_KEY",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func decodeNarration(_ data: Data) throws -> ReportNarration {
        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw NarratorDecodeError.empty
        }
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            throw NarratorDecodeError.notJSON
        }
        let slice = Data(content[start...end].utf8)
        return try JSONDecoder().decode(ReportNarration.self, from: slice)
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var evidence: ReportEvidence

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(0, forKey: .temperature)
        let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        let messages = [
            ChatMessage(role: "system", content: Self.systemPrompt),
            ChatMessage(role: "user", content: evidenceJSON),
        ]
        try container.encode(messages, forKey: .messages)
    }

    /// The model fills prose slots. It is told not to invent figures; the guard still checks.
    private static let systemPrompt = """
    你只写叙述。数字必须来自用户给出的证据 JSON，不要新增瓦数、比例、费用或节能百分比。\
    不要写全局最优、合规证书或实测满意率。\
    只返回 JSON：{"headline":"","cardProse":{"卡片 id":"段落"},"caveats":["限制"]}。
    """

    private enum CodingKeys: String, CodingKey {
        case model, temperature, messages
    }
}

private struct ChatMessage: Encodable {
    var role: String
    var content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}

private enum NarratorDecodeError: Error {
    case empty
    case notJSON
}
