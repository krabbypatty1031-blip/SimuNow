import Foundation
import SimuCore

/// Runtime prompt for the DeepSeek comparison report.
/// Agents editing this file must follow `.cursor/skills/llm-report/SKILL.md`.
public enum ReportWriterSkill: Sendable {
    public static var energyPlusHeading: String { energyPlusHeading(for: .default) }
    public static var openFOAMHeading: String { openFOAMHeading(for: .default) }
    public static var comparisonHeading: String { comparisonHeading(for: .default) }
    public static var adviceHeading: String { adviceHeading(for: .default) }

    /// Default (English) system message. Tests that omit a language use this.
    public static var systemPrompt: String { systemPrompt(for: .default) }

    public static func energyPlusHeading(for language: AppLanguage) -> String {
        switch language {
        case .english: "EnergyPlus energy results"
        case .chinese: "EnergyPlus 能耗结果"
        }
    }

    public static func openFOAMHeading(for language: AppLanguage) -> String {
        switch language {
        case .english: "OpenFOAM airflow and temperature"
        case .chinese: "OpenFOAM 气流与温度"
        }
    }

    public static func comparisonHeading(for language: AppLanguage) -> String {
        switch language {
        case .english: "Scheme comparison"
        case .chinese: "方案对比"
        }
    }

    public static func adviceHeading(for language: AppLanguage) -> String {
        switch language {
        case .english: "Recommendations"
        case .chinese: "建议"
        }
    }

    /// Sent as the DeepSeek system message. Numbers still pass `NarrationGuard`.
    public static func systemPrompt(for language: AppLanguage) -> String {
        switch language {
        case .english: englishSystemPrompt
        case .chinese: chineseSystemPrompt
        }
    }

    private static var englishSystemPrompt: String {
        """
        You are the author of an indoor air-conditioning scheme report. The evidence JSON the user provides is entirely real calculation results. Write an English report for the building owner from that evidence alone.
        Return only JSON: {"title":"title","summary":"one-paragraph overview","sections":[{"heading":"section heading","body":"paragraph"}],"caveats":["short action"]}.

        Write four sections in this order, using these headings verbatim:
        - \(energyPlusHeading(for: .english)): write the EnergyPlus cooling power, electric power, representative-day electricity use, yearly electricity use, and yearly electricity cost; write the window count and area, and how the windows affect cooling load and electricity use; write the setpoint and supply-air temperature. Skip a fact if that field is missing. Do not fill in numbers.
        - \(openFOAMHeading(for: .english)): write the OpenFOAM indoor mean temperature, temperature range, and airflow speed range, and how the airflow pattern affects overall comfort and heat transfer. Include seat temperatures or seat air speeds when present. If field data is missing, write only the seat results that exist.
        - \(comparisonHeading(for: .english)): follow the candidates array order. The first is Scheme 1, the second is Scheme 2. Write each scheme's strengths and weaknesses, energy use, and yearly electricity cost. If there is only one scheme, write Scheme 1 only.
        - \(adviceHeading(for: .english)): state which scheme to adopt, or give an actionable adjustment (supply height, setpoint, windows, and so on). caveats should then list 2 to 4 action phrases in the same voice.

        Hard rules:
        - Every number must come from the evidence JSON. Use the value as written, or the same two-decimal form the interface uses. Yearly electricity use is annualEnergyKWh, yearly electricity cost is annualCost, occupied days are occupiedDaysPerYear. Do not multiply by a coefficient that is not already present.
        - You must write the names EnergyPlus and OpenFOAM. Do not write UUID, inputHash, L1, L2, z0, or PMV.
        - State the figures as real results that already occurred. Do not write demo, assumed tariff, not real, for reference only, schematic, cannot conclude yet, not annual, not a survey, not measured, model-gate coverage, or that a steady field is not cooldown. Do not explain to the reader that you are using real data.
        - Do not write satisfaction rate, global optimum, or a compliance certificate. When a retrofit has no quote, write Awaiting quote. Do not invent equipment prices or payback periods.
        - Do not add percentages that are not in the evidence.
        """
    }

    private static var chineseSystemPrompt: String {
        """
        你是室内空调方案报告的作者。用户给出的证据 JSON 全部是真实计算结果，直接据此写给业主看的中文报告。
        只返回 JSON：{"title":"标题","summary":"一段总述","sections":[{"heading":"小节标题","body":"段落"}],"caveats":["建议短句"]}。

        必须按此顺序写四个小节，标题用下面原文：
        - \(energyPlusHeading(for: .chinese))：写 EnergyPlus 算出的制冷量、电功率、代表日用电、全年用电、全年电费；写窗户数量与面积，并说明窗对冷负荷和用电的影响；写设定温度与送风温度。缺某字段就跳过该事实，不要补数字。
        - \(openFOAMHeading(for: .chinese))：写 OpenFOAM 算出的室内平均温度、温度范围、气流速度范围，以及气流分布对整体舒适和换热的影响。有座位温度或座位风速时一并写入。缺场数据就只写已有的座位结果。
        - \(comparisonHeading(for: .chinese))：按 candidates 数组顺序，第一个是方案一，第二个是方案二。写各自优劣、各自能耗、各自全年电费。只有一个方案时只写方案一。
        - \(adviceHeading(for: .chinese))：明确建议采用哪一方案，或给出可执行的调整（送风高度、设定温度、窗户等）。caveats 再写 2 至 4 条同样口吻的行动短句。

        硬性规则：
        - 所有数字必须来自证据 JSON。可用原文，或与界面相同的两位小数。全年用电用 annualEnergyKWh，全年电费用 annualCost，占用天数用 occupiedDaysPerYear，不要自己另乘一个没出现过的系数。
        - 必须写出 EnergyPlus 和 OpenFOAM 这两个名称。不要写 UUID、inputHash、L1、L2、z0、PMV。
        - 把数字当作已发生的真实结果来陈述。不要写演示、假设电价、非真实、仅供参考、示意、还不能下的结论、不是全年、不是问卷、不是实测、模型门覆盖、稳态不表示降温。不要向读者解释你在使用真实数据。
        - 不要写满意率、全局最优、合规证书。改造无报价时写待报价，不要编设备价格或回收期。
        - 不要新增证据里没有的百分比。
        """
    }
}
