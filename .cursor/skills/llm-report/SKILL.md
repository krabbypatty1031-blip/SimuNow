---
name: llm-report
description: >-
  Writes and maintains SimuNow DeepSeek HVAC comparison reports. Use when
  editing llm-report, ReportWriterSkill, DeepSeekReportClient, evidence PDF
  narration, report-evidence yearly totals, or user-facing scheme comparison
  reports that present EnergyPlus and OpenFOAM results.
---

# LLM 对比报告（顾问式）

用户可见的对比说明由 DeepSeek 根据冻结证据 JSON 写成建议报告（ADR-021：不再有代码分类的「说明卡」，方案整理交给 AI）。界面为英文时写英文报告，界面为中文时写中文报告。运行时提示词只放在 `Packages/SimuKit/Sources/SimuReporting/ReportWriterSkill.swift`，用 `systemPrompt(for:)` 按 `AppLanguage` 选择，不要另写一份会漂移的副本。

## 必须达成的效果

写给客户看的建议报告：每一节先给观点和结论，再用证据数字支撑，像顾问面对面交谈。不是数据罗列。

1. 先讲清用户做了什么：照抄 `pairDiff.inputChanges` 的 sentence；`basisMismatchReason` 非空时如实告诉用户差在哪；结尾给总判断（证据范围内哪个更值得选 / 差不多）。
2. 用电对比：先回答「电费上有没有值得在意的差别」；差值为零直说不用纠结；有差别讲一年电费单差多少、值不值得驱动选择。
3. 座位舒适对比：讲体感。差值很小告诉用户坐下来感觉不出；有座位不合适指出哪个座位、哪个方案能改善。
4. 建议下一步：顾问给看法——最值得先试什么、为什么；差距很小直说别在这两个方案间纠结。caveats 限可调项方向（窗户、出风口、设定温度、出风温度、出风速度风量、人数座位），不编预测数字。

观点、比较结论、方向性判断（哪个更值得选、某项不值得调、差值小到感觉不出）是模型该写的顾问职责；但数字和具体事实不能超出证据。把证据 JSON 里的数字当作真实结果直接陈述。不要另加「演示 / 非真实 / 不是全年 / 不是问卷 / 仅供参考」之类说明。

## 数字从哪来

`NarrationGuard` 只放行证据 JSON 里已有的数字。全年用电、全年电费、窗面积、室内平均温度、气流范围必须在 Swift 里算好，写进 `EvidenceRun`，再送给模型；方案差值由 `CandidateDiff` 在 Swift 里减好（half-up 两位）写进 `pairDiff`，AI 只照抄。

被守卫拒绝的段落直接丢掉，不要写成「叙述未采用」或任何英文等价句；PDF 仍保留证据附录。小节 heading 必须是四个规定标题之一，否则按序号换成对应标题，避免把提示词写进 PDF。

- EnergyPlus：`coolingW`、`electricPowerW`、`dayEnergyKWh`、`annualEnergyKWh`、`annualCost`、`windowCount`、`windowAreaM2`、设定/送风温度
- OpenFOAM：`indoorMeanC`、`indoorMinC`/`indoorMaxC`、`flowMinMps`/`flowMaxMps`、座位温度与风速
- 全年：`annualEnergyKWh` / `annualCost` = 代表日 × `occupiedDaysPerYear`（365）。不要改 L1 指标 `annual_kwh`（仍 omitted）
- 不要让模型自己乘没出现过的系数，也不要编回收期或设备报价

## 四节标题（原文，随界面语言）

中文：

1. `你的两个方案`（`candidates[0]` 是方案一，`candidates[1]` 是方案二）
2. `用电对比`
3. `座位舒适对比`
4. `建议下一步`

英文：

1. `Your two schemes`
2. `Energy comparison`
3. `Seat comfort comparison`
4. `What to try next`

必须写出 EnergyPlus 和 OpenFOAM 这两个名称。不要写 UUID、`inputHash`、L1、L2、z0、PMV。

## 改提示词时

改 `ReportWriterSkill.systemPrompt(for:)` 的中英两份，并同步本 skill 与 `NarratorGuardTests` 里对官方请求 system 消息的断言（默认语言是英文）。不要把免责声明写回提示词。
咨询助手 `ChatWriterSkill.systemPrompt(for:)` 同样跟界面语言，按钮名必须与当前语言 UI 一致。