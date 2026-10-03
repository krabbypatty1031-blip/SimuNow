---
name: llm-report
description: >-
  Writes and maintains SimuNow DeepSeek HVAC comparison reports. Use when
  editing llm-report, ReportWriterSkill, DeepSeekReportClient, evidence PDF
  narration, report-evidence yearly totals, or user-facing scheme comparison
  reports that present EnergyPlus and OpenFOAM results.
---

# LLM 对比报告

用户可见的对比说明由 DeepSeek 根据冻结证据 JSON 写成报告，语言跟随界面：`AppLanguage.english`（默认）写英文，`chinese` 写中文。运行时提示词只放在 `Packages/SimuKit/Sources/SimuReporting/ReportWriterSkill.swift` 的 `systemPrompt(for:)`，不要另写一份会漂移的副本。导出时 `DeepSeekReportClient` 使用 `WorkspaceStore.copy.language`。

## 必须达成的效果

1. 展示 EnergyPlus / OpenFOAM 的计算结果，例如窗户大小、室内平均温度、气流分布对整体的影响。
2. 展示方案一和方案二（Scheme 1 / Scheme 2）的优劣、各自能耗、以及全年电费。
3. 向用户提出建议。

把证据 JSON 里的数字当作真实结果直接陈述。不要另加「演示 / 非真实 / 不是全年 / 不是问卷 / 仅供参考」或对应英文 disclaimer。

## 数字从哪来

`NarrationGuard` 只放行证据 JSON 里已有的数字。全年用电、全年电费、窗面积、室内平均温度、气流范围必须在 Swift 里算好，写进 `EvidenceRun`，再送给模型。

- EnergyPlus：`coolingW`、`electricPowerW`、`dayEnergyKWh`、`annualEnergyKWh`、`annualCost`、`windowCount`、`windowAreaM2`、设定/送风温度
- OpenFOAM：`indoorMeanC`、`indoorMinC`/`indoorMaxC`、`flowMinMps`/`flowMaxMps`、座位温度与风速
- 全年：`annualEnergyKWh` / `annualCost` = 代表日 × `occupiedDaysPerYear`（365）。不要改 L1 指标 `annual_kwh`（仍 omitted）
- 不要让模型自己乘没出现过的系数，也不要编回收期或设备报价

## 四节标题（原文，按语言）

英文（默认）：

1. `EnergyPlus energy results`
2. `OpenFOAM airflow and temperature`
3. `Scheme comparison`（`candidates[0]` 是 Scheme 1，`candidates[1]` 是 Scheme 2）
4. `Recommendations`

中文：

1. `EnergyPlus 能耗结果`
2. `OpenFOAM 气流与温度`
3. `方案对比`（`candidates[0]` 是方案一，`candidates[1]` 是方案二）
4. `建议`

必须写出 EnergyPlus 和 OpenFOAM 这两个名称。不要写 UUID、`inputHash`、L1、L2、z0、PMV。改造无报价时英文写 `Awaiting quote`，中文写 `待报价`。

## 改提示词时

改 `ReportWriterSkill.systemPrompt(for:)` 的对应语言文本，并同步本 skill 与 `NarratorGuardTests` 里对官方请求 system 消息的断言（默认英语；中文另测 `language: .chinese`）。不要把免责声明写回提示词。
