# 数据与文件契约

## 当前实现与扩展边界

P0 Swift 模型和 `Protocols/Schemas` 仅覆盖 ProjectDraft、SimulationRequest、RunReceipt。Draft 不包含几何，不能提交数值求解。完整模型在 P2 / P3 扩展并版本化；不要静默复用 draft 做 solver input。
协议文件是数值边界的唯一依据；display USDZ 只做展示，求解器使用经过简化和验证的几何。

## 项目包

```text
Project.simunow/
  project.json                  当前项目、schema 与参数来源
  geometry/                     语义面、障碍物、坐标转换
  assets/room.usdz               可选展示资产
  scenarios/<scenario-id>.json   设计变量和约束覆盖
  measurements/                 匿名温湿度/风速/CO2/功率
  runs/<run-id>/
    input.json                  不可变物理输入快照
    status.json                 状态快照
    events.jsonl                单行事件流
    results.json                有单位指标、质量与假设
    logs/                       原始求解与异常日志
    fields/header.json          网格与格式说明
    fields/*.bin                float32 场与掩码
```

上面是目标格式，P0 未实现保存/导入。P2 建立迁移、原子写入和损坏检测。

## 完整模型设计

| 实体 | 必需信息 | 校验 |
|---|---|---|
| Project | schema、ID、坐标、长度单位、模板 | 支持版本、唯一 ID |
| Room | 墙门窗、封闭边界、高度、朝向、室外关系 | 法线、相交、开口归属 |
| Obstacle | 简化几何、位置、材料或热条件 | 不穿墙、最小特征尺寸 |
| HVAC | 设备型式、送回风口、风量、容量、功率、性能来源 | 流量、方向、范围与数量 |
| Control | 设定、传感位置、时间表、控制模式 | 不把设定当送风温度 |
| Occupant | 座位、人数、met、clo、显潜热、时间表 | 采样点在流体域 |
| Envelope | 构造、U 值、玻璃 SHGC、遮阳 | SHGC 与透光率分开 |
| Ventilation | 新风、排风、渗风、门窗 | 循环风与室外交换分开 |
| Environment | 天气、代表日、时区、户外参数 | 文件哈希、日期与工况 |
| Cost | 电价、时段、币种、设备/安装报价来源 | 缺失不填零费用 |

每个不确定物理值带 value / unit / source / reference / uncertainty；区间必须有含义和来源。

## 任务事件

协议 version、run_id、scenario_id、input_hash、sequence、timestamp、event_type、stage、payload。
事件类型：accepted、progress、log、quality、completed、failed、cancelled。求解阶段用 iteration 与监测量，不把残差当总进度百分比。
stdout 只发 JSONL；stderr 发诊断。事件写入先完成单行再刷新。客户端拒绝错 run、过期 sequence、未知 schema；未知可选字段采用明确兼容策略。
Request 引用项目快照相对路径与内容哈希。取消幂等；拒绝新任务和取消执行中任务分开；不吞异常。

## 结果格式

指标保存 name、value 或 missing、unit、aggregation、sample_ids、method、fidelity、quality、assumptions。null/缺失不作为 0。
舒适位置指标、代表日电耗和费用附各自时间范围；跨口径结果不能直接求节省百分比。
报告引用 run，而不是读取不断变化的编辑对象。

## 场数据格式

Header 至少包含 version、origin_m、spacing_m、dimensions、axis_order、coordinate_system、channels、units、dtype、endianness、validity_mask、payload_bytes、checksum。
约定 float32 little-endian；展平顺序 i + nx*(j + ny*k)，x 变化最快；channel 的交错/独立布局必须明确。温度显示格式统一 °C，OpenFOAM K 只在 adapter 内转换。
向量转换同时处理位置、方向与重力；invalid mask 排除实体和域外。加载前核对文件长度与校验和。
显示网格用于渲染；定量座位指标源于原始求解网格，避免显示降采样改变量化结果。

## 版本与哈希

规范化序列化物理输入，再生成 SHA-256；排除相机、色标、更新时间等展示字段。加入天气、设备曲线、solver 设置和版本。
新增必须字段或语义变化升 schema；同时保留 migration 和旧夹具。不能只改 Swift 模型忘记 Python 与协议。
