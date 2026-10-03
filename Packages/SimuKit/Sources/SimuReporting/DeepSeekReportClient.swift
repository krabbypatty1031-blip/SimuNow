import Foundation
import Security
import SimuCore

/// DeepSeek official Chat Completions. The key is read at call time from the
/// environment or the keychain and is never written into the evidence pack.
public struct DeepSeekReportClient: ReportGenerator {
    public static let officialBaseURL = URL(string: "https://api.deepseek.com")!
    public static let officialModel = "deepseek-chat"

    public var baseURL: URL
    public var model: String
    public var language: AppLanguage
    public var keyProvider: @Sendable () -> String?
    public var log: @Sendable (String) -> Void
    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        baseURL: URL = DeepSeekReportClient.officialBaseURL,
        model: String = DeepSeekReportClient.officialModel,
        language: AppLanguage = .default,
        keyProvider: @escaping @Sendable () -> String? = DeepSeekReportClient.keyFromEnvironmentOrKeychain,
        log: @escaping @Sendable (String) -> Void = { _ in },
        transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.language = language
        self.keyProvider = keyProvider
        self.log = log
        self.transport = transport ?? Self.urlSessionTransport
    }

    /// Nil when neither `DEEPSEEK_API_KEY` nor `SIMUNOW_REPORT_API_KEY` is set.
    public static func configuredFromEnvironment(language: AppLanguage = .default) -> DeepSeekReportClient? {
        guard let key = keyFromEnvironmentOrKeychain(), !key.isEmpty else {
            return nil
        }
        return DeepSeekReportClient(language: language, keyProvider: { key })
    }

    public func generate(_ evidence: ReportEvidence) async -> GeneratedReport? {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            log("未配置 DeepSeek API 密钥，不能生成对比说明")
            return nil
        }
        do {
            var request = URLRequest(url: chatCompletionsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, evidence: evidence, language: language))
            let (data, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log("DeepSeek 请求失败，不能生成对比说明")
                return nil
            }
            guard let report = try? decodeReport(data), isUsable(report) else {
                log("DeepSeek 返回无法解析，不能生成对比说明")
                return nil
            }
            return report
        } catch {
            log("DeepSeek 请求失败，不能生成对比说明")
            return nil
        }
    }

    /// Environment first (`DEEPSEEK_API_KEY`, then `SIMUNOW_REPORT_API_KEY`),
    /// then keychain `app.simunow.report`, then the generic Application Support
    /// file `SimuNow/deepseek_api_key` so a GUI launch that does not inherit a
    /// LaunchAgent env can still find a local key. The value is never logged.
    public static func keyFromEnvironmentOrKeychain() -> String? {
        for name in ["DEEPSEEK_API_KEY", "SIMUNOW_REPORT_API_KEY"] {
            if let env = ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !env.isEmpty {
                return env
            }
        }
        return keychainKey(account: "DEEPSEEK_API_KEY")
            ?? keychainKey(account: "SIMUNOW_REPORT_API_KEY")
            ?? applicationSupportKeyFile()
    }

    /// Official path is `/chat/completions` on `api.deepseek.com`.
    var chatCompletionsURL: URL {
        var root = baseURL.absoluteString
        if root.hasSuffix("/") {
            root.removeLast()
        }
        return URL(string: root + "/chat/completions") ?? baseURL
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    private static func applicationSupportKeyFile() -> String? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SimuNow", isDirectory: true)
            .appendingPathComponent("deepseek_api_key", isDirectory: false)
        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func keychainKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.simunow.report",
            kSecAttrAccount as String: account,
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

    private func decodeReport(_ data: Data) throws -> GeneratedReport {
        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard var content = chat.choices.first?.message.content else {
            throw ReportDecodeError.empty
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```") {
            content = content.replacingOccurrences(of: "```json", with: "")
            content = content.replacingOccurrences(of: "```", with: "")
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            throw ReportDecodeError.notJSON
        }
        let slice = Data(content[start...end].utf8)
        return try JSONDecoder().decode(GeneratedReport.self, from: slice)
    }

    private func isUsable(_ report: GeneratedReport) -> Bool {
        !report.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !report.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var evidence: ReportEvidence
    var language: AppLanguage

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(0, forKey: .temperature)
        try container.encode(ResponseFormat(), forKey: .responseFormat)
        let evidenceJSON = String(decoding: try JSONEncoder().encode(evidence), as: UTF8.self)
        let messages = [
            ChatMessage(role: "system", content: ReportWriterSkill.systemPrompt(for: language)),
            ChatMessage(role: "user", content: evidenceJSON),
        ]
        try container.encode(messages, forKey: .messages)
    }

    private struct ResponseFormat: Encodable {
        var type = "json_object"
    }

    private enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case responseFormat = "response_format"
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

private enum ReportDecodeError: Error {
    case empty
    case notJSON
}
