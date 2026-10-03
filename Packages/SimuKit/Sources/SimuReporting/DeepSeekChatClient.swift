import Foundation
import Security
import SimuCore

/// What the consult assistant is allowed to talk about, frozen at call time:
/// a plain-language summary of the live draft plus the pinned evidence pack.
/// The assistant never sees the mutable project object, only this snapshot.
public struct ChatContext: Equatable, Sendable {
    /// Current draft in plain language (room size, occupancy, setpoints,
    /// windows, tariff). Nil when no project is loaded.
    public var draftSummary: String?
    /// Frozen comparison evidence. Nil when nothing is pinned yet.
    public var evidence: ReportEvidence?

    public init(draftSummary: String? = nil, evidence: ReportEvidence? = nil) {
        self.draftSummary = draftSummary
        self.evidence = evidence
    }
}

/// Anything that can answer a consult turn. Production is DeepSeek; tests stub it.
public protocol ChatAssistant: Sendable {
    /// Nil means "could not answer" (no key, request failed, unusable reply).
    func respond(to history: [ChatTurn], context: ChatContext) async -> String?
}

/// System prompt for the consult assistant. Two jobs only: explain how to
/// use the app, and explain what the numbers mean — using the numbers the
/// context actually carries.
public enum ChatWriterSkill: Sendable {
    public static let contextHeading = "当前方案数据"

    public static let systemPrompt = """
    你是 SNer，SimuNow 的使用顾问，和正在用这个 App 配置房间空调的用户聊天。用户叫你 SNer。你只做两类事：

    一、解答怎么用 App（按真实按钮名讲流程）：
    - 「布置房间」页填写房间与空调：房间长宽高、人数、使用时间、设定温度、出风温度；右侧检查器可添加窗、门、家具、座位。「计算结果」页提交并查看代表日用电与座位冷热。
    - 家具布置入口是检查器「俯视图拖拽布置家具」：进俯视图后，在空白处按下拖入家具，按住已有家具可拖动换位置，松手时位置合法才生效（挡住送回风带、窗户、座位或压到别的家具会被拒绝并提示原因）。
    - 「布置房间」页 3D 视口顶部有「点击放置」工具条：选中窗户、门、送风口或回风口后在房间墙面上点击放置，选座位则点地面放置。
    - 家具影响口径：家具会进入气流计算，阻挡空气流动、影响座位温度与风速；家具不进入用电估算，制冷量与电费数字不受家具影响。
    - 「计算准备」选择本地引擎文件夹（需要 EnergyPlus 和 OpenFOAM）。
    - 「估算这一天用电」跑代表日能耗（制冷量、电功率、日电费）；「查看座位冷热分布」跑稳态气流（座位温度、风速、切片上色）。
    - 质量检查通过后才能看到座位温度；「加入对比」把当前方案冻结成候选；对比页两列并排；「导出对比说明」生成对比 PDF（需要配置 DeepSeek 密钥）。
    - 座位合适温度带是 23 至 26 °C；全年用电和电费 = 代表日 × 365 个占用日。

    二、解释数值是什么意思、单位是什么、怎么算出来的（制冷量 W、电功率 W、代表日用电 kWh、电费、座位温度、风速、冷热是否合适即 PMV、不满意比例 PPD）。解释具体方案时只能引用「\(contextHeading)」块里的数字；概念定义可以用公认常识（例如 COP 是制冷量除以电功率），但行业一般情况用「一般、常见、较高、偏低」这类程度词表述，不要写具体数字范围；不要对用户方案做任何数字预测。

    风格：中文口语短句，像客服面对面聊天；先回答问题，再补一句为什么。不操作任何东西，只解释。不确定这个版本有没有的功能，就直说还没有。

    硬性规则：
    - 所有跟方案有关的数字必须来自「\(contextHeading)」块，保持原值，不要自己另算。举例说明算法时也只用「\(contextHeading)」块里的真实数字，不要用假设的数字举例（比如不要说「假如一天用 20 度」）。
    - 不要在回答里写「注：」开头的提示行或免责声明；需要标注的地方由 App 自动加，你自己不要加。
    - 引用成对的数字（比如出风高度、温度带的两个边界）时按字段原意并列写出（「从 X 到 Y」），不要自己加「最高、最低、上限、下限」这类排序说法；分不清先后就只并列，不排序。
    - 不要编造 App 没有的按钮、选项或功能。
    - 不要写 UUID、inputHash、L1、L2、z0 这类内部词。
    - 不要编设备价格、回收期或新的百分比。
    """
}

/// Free-text guard for chat replies. Concept questions ("what is COP?")
/// legitimately carry industry-typical figures that no project holds, so
/// unlike the PDF guard a foreign number does not delete the reply: the
/// reply ships with a transparent caution line naming the non-project
/// figures. Project figures must still come from the context (evidence +
/// draft summary); the user's own question and comfort-model constants
/// count as allowed.
public enum ChatGuard: Sendable {
    /// Appended (not substituted) when the reply carries figures the
    /// project does not hold — concept or industry-typical numbers.
    public static let cautionNote = "注：这条回答里有的数字是一般情况或概念口径，不是你方案的计算结果；你方案的数字以对比页和检查器为准。"

    /// Comfort-model constants that are common knowledge, not project data:
    /// PMV/PPD comfort band 0.5, 1 met = 58.15 W/m², seated office 70 W/m².
    static let conceptConstants: Set<Decimal> = [0.5, 58.15, 70]
    /// Skill-stated accounting figures the system prompt itself quotes: the
    /// 365 occupied days, the 23–26 °C seat band and the percent factor.
    static let skillConstants: Set<Decimal> = [365, 23, 26, 100]

    public static func screen(_ reply: String, history: [ChatTurn], context: ChatContext) -> String {
        guard !reply.isEmpty else { return reply }
        var allowed: Set<Decimal> = conceptConstants.union(skillConstants)
        if let evidence = context.evidence {
            allowed.formUnion(NarrationGuard.numericValues(in: evidence))
        }
        if let draftSummary = context.draftSummary {
            // The draft summary is real user input; its figures are fair game.
            allowed.formUnion(NarrationGuard.numberTokens(in: draftSummary))
        }
        // Whatever the user typed is theirs to ask about (e.g. "COP 一般是 3 以上吗").
        for turn in history where turn.role == .user {
            allowed.formUnion(NarrationGuard.numberTokens(in: turn.text))
        }
        let hasForeign = NarrationGuard.numberTokens(in: reply).contains { !allowed.contains($0) }
        // Transparent labelling, not deletion: a concept answer must not be
        // destroyed for quoting industry-typical figures, but the user must
        // always be able to tell project numbers from general ones.
        // Idempotent: the client screens once and the store screens again
        // (belt and braces, 2026-10-04 live hand-test showed the double
        // append); a reply already carrying the note keeps exactly one.
        if hasForeign, !reply.contains(cautionNote) {
            return reply + "\n\n" + cautionNote
        }
        return reply
    }
}

/// DeepSeek chat without the JSON-object mode: consult replies are prose.
/// Same key resolution as the report client, so one keychain item serves both.
public struct DeepSeekChatClient: ChatAssistant {
    public static let officialBaseURL = DeepSeekReportClient.officialBaseURL
    public static let officialModel = DeepSeekReportClient.officialModel

    public var baseURL: URL
    public var model: String
    public var keyProvider: @Sendable () -> String?
    public var log: @Sendable (String) -> Void
    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        baseURL: URL = DeepSeekChatClient.officialBaseURL,
        model: String = DeepSeekChatClient.officialModel,
        keyProvider: @escaping @Sendable () -> String? = DeepSeekReportClient.keyFromEnvironmentOrKeychain,
        log: @escaping @Sendable (String) -> Void = { _ in },
        transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.keyProvider = keyProvider
        self.log = log
        self.transport = transport ?? { try await URLSession.shared.data(for: $0) }
    }

    /// Nil when no key is configured; no network call happens.
    public static func configuredFromEnvironment() -> DeepSeekChatClient? {
        guard let key = DeepSeekReportClient.keyFromEnvironmentOrKeychain(), !key.isEmpty else {
            return nil
        }
        return DeepSeekChatClient(keyProvider: { key })
    }

    public func respond(to history: [ChatTurn], context: ChatContext) async -> String? {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            log("未配置 DeepSeek API 密钥，不能回答咨询")
            return nil
        }
        // Guard before the network: no point asking when the reply would be
        // screened anyway; and guard after, so no invented figure slips through.
        do {
            var request = URLRequest(url: chatCompletionsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(ChatWireRequest(model: model, messages: messages(history: history, context: context)))
            let (data, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log("DeepSeek 咨询请求失败")
                return nil
            }
            let reply = try decodeReply(data)
            guard !reply.isEmpty else {
                log("DeepSeek 咨询返回空回复")
                return nil
            }
            return ChatGuard.screen(reply, history: history, context: context)
        } catch {
            log("DeepSeek 咨询请求失败")
            return nil
        }
    }

    /// System message = skill prompt + frozen context block.
    func messages(history: [ChatTurn], context: ChatContext) -> [ChatWireMessage] {
        var system = ChatWriterSkill.systemPrompt
        system += "\n\n\(ChatWriterSkill.contextHeading)：\n"
        if let draftSummary = context.draftSummary {
            system += draftSummary
        } else {
            system += "还没有打开项目。"
        }
        if let evidence = context.evidence {
            if let json = try? JSONEncoder().encode(evidence), let text = String(data: json, encoding: .utf8) {
                system += "\n已冻结的对比证据（数字以此为准）：\n" + text
            }
        } else {
            system += "\n还没有加入对比的方案。"
        }
        var all = [ChatWireMessage(role: "system", content: system)]
        for turn in history {
            all.append(ChatWireMessage(role: turn.role.rawValue, content: turn.text))
        }
        return all
    }

    var chatCompletionsURL: URL {
        var root = baseURL.absoluteString
        if root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + "/chat/completions") ?? baseURL
    }

    private func decodeReply(_ data: Data) throws -> String {
        struct Wire: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        return wire.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private struct ChatWireRequest: Encodable {
        var model: String
        var messages: [ChatWireMessage]
        var stream = false
    }
}

struct ChatWireMessage: Encodable {
    var role: String
    var content: String
}
