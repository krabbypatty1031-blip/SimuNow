---
name: llm-report
description: >-
  Writes and maintains SimuNow DeepSeek HVAC comparison reports. Use when
  editing llm-report, ReportWriterSkill, DeepSeekReportClient, evidence PDF
  narration, report-evidence yearly totals, or user-facing scheme comparison
  reports that present EnergyPlus and OpenFOAM results.
---

# LLM 对比报告

用户可见的对比说明由 DeepSeek 根据冻结证据 JSON 写成中文报告（ADR-021：不再有代码分类的「说明卡」，方案整理交给 AI）。运行时提示词只放在 `Packages/SimuKit/Sources/SimuReporting/ReportWriterSkill.swift`，不要另写一份会漂移的副本。

## 必须达成的效果

1. 先讲清楚用户做了什么：照抄 `pairDiff.inputChanges` 的 sentence；`basisMismatchReason` 非空时如实写。
2. 用电对比：各方案能耗与全年电费，差值照抄 `pairDiff` 里 dimension 为 energy 的 delta。
3. 座位舒适对比：座位温度、合适比例、风速的差值（comfort 与 flow 的 delta）。
4. 建议下一步：只给可调项方向（窗户、出风口、设定温度、出风温度、出风速度风量、人数座位），不编预测数字。

把证据 JSON 里的数字当作真实结果直接陈述。不要另加「演示 / 非真实 / 不是全年 / 不是问卷 / 仅供参考」之类说明。

## 数字从哪来

`NarrationGuard` 只放行证据 JSON 里已有的数字。全年用电、全年电费、窗面积、室内平均温度、气流范围必须在 Swift 里算好，写进 `EvidenceRun`，再送给模型；方案差值由 `CandidateDiff` 在 Swift 里减好（half-up 两位）写进 `pairDiff`，AI 只照抄。

- EnergyPlus：`coolingW`、`electricPowerW`、`dayEnergyKWh`、`annualEnergyKWh`、`annualCost`、`windowCount`、`windowAreaM2`、设定/送风温度
- OpenFOAM：`indoorMeanC`、`indoorMinC`/`indoorMaxC`、`flowMinMps`/`flowMaxMps`、座位温度与风速
- 全年：`annualEnergyKWh` / `annualCost` = 代表日 × `occupiedDaysPerYear`（365）。不要改 L1 指标 `annual_kwh`（仍 omitted）
- 不要让模型自己乘没出现过的系数，也不要编回收期或设备报价

## 四节标题（原文）

1. `你的两个方案`（`candidates[0]` 是方案一，`candidates[1]` 是方案二）
2. `用电对比`
3. `座位舒适对比`
4. `建议下一步`

必须写出 EnergyPlus 和 OpenFOAM 这两个名称。不要写 UUID、`inputHash`、L1、L2、z0、PMV。

## 改提示词时

改 `ReportWriterSkill.systemPrompt`，并同步本 skill 与 `NarratorGuardTests` 里对官方请求 system 消息的断言。不要把免责声明写回提示词。
