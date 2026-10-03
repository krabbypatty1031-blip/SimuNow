---
name: llm-report
description: >-
  Writes and maintains SimuNow DeepSeek HVAC comparison reports. Use when
  editing llm-report, ReportWriterSkill, DeepSeekReportClient, evidence PDF
  narration, report-evidence yearly totals, or user-facing scheme comparison
  reports that present EnergyPlus and OpenFOAM results.
---

# LLM 对比报告

用户可见的对比说明由 DeepSeek 根据冻结证据 JSON 写成中文报告。运行时提示词只放在 `Packages/SimuKit/Sources/SimuReporting/ReportWriterSkill.swift`，不要另写一份会漂移的副本。

## 必须达成的效果

1. 展示 EnergyPlus / OpenFOAM 的计算结果，例如窗户大小、室内平均温度、气流分布对整体的影响。
2. 展示方案一和方案二的优劣、各自能耗、以及全年电费。
3. 向用户提出建议。

把证据 JSON 里的数字当作真实结果直接陈述。不要另加「演示 / 非真实 / 不是全年 / 不是问卷 / 仅供参考」之类说明。

## 数字从哪来

`NarrationGuard` 只放行证据 JSON 里已有的数字。全年用电、全年电费、窗面积、室内平均温度、气流范围必须在 Swift 里算好，写进 `EvidenceRun`，再送给模型。

- EnergyPlus：`coolingW`、`electricPowerW`、`dayEnergyKWh`、`annualEnergyKWh`、`annualCost`、`windowCount`、`windowAreaM2`、设定/送风温度
- OpenFOAM：`indoorMeanC`、`indoorMinC`/`indoorMaxC`、`flowMinMps`/`flowMaxMps`、座位温度与风速
- 全年：`annualEnergyKWh` / `annualCost` = 代表日 × `occupiedDaysPerYear`（365）。不要改 L1 指标 `annual_kwh`（仍 omitted）
- 不要让模型自己乘没出现过的系数，也不要编回收期或设备报价

## 四节标题（原文）

1. `EnergyPlus 能耗结果`
2. `OpenFOAM 气流与温度`
3. `方案对比`（`candidates[0]` 是方案一，`candidates[1]` 是方案二）
4. `建议`

必须写出 EnergyPlus 和 OpenFOAM 这两个名称。不要写 UUID、`inputHash`、L1、L2、z0、PMV。

## 改提示词时

改 `ReportWriterSkill.systemPrompt`，并同步本 skill 与 `NarratorGuardTests` 里对官方请求 system 消息的断言。不要把免责声明写回提示词。
