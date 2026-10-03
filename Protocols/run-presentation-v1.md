# 可选运行展示信息 v1

这是 App 文档层的展示侧文件，不属于物理输入或本地分析证据。路径为 `runs/<小写 run UUID>/presentation.json`，与 `native-analysis/` 并列。其 [schema](Schemas/run-presentation.schema.json) 独立维护，不进入 Core 模型生成器、worker 或分析输入哈希。

| 字段 | 含义 |
|---|---|
| owner / version | `com.simunow.presentation` / 1 |
| runID / projectID | 必须匹配所在运行与当前项目；不是分析有效性证明 |
| scenarioName | 加入项目时的方案名称，最多 256 个 Unicode 码点；显示截取不改变原方案名 |
| recordedAt | 结果加入内存项目包时的时间，Foundation 默认 Codable Date：距 2001-01-01 UTC 的秒数；不是求解启动时间或写盘时间 |
| method | airflowPreview / powerEstimate / steadyHeatBalance 的展示身份 |

追加结果时写入侧文件，原 request/input/result/manifest 不改变；系统文档保存负责实际写盘。每份展示文件索引读取上限 4096 字节。旧记录缺失、损坏、身份不符或未来版本时，展示信息忽略，原附件保留；历史记录说明时间/方法未记录。分析载入仍独立校验原文件、哈希、方法检查和项目身份。展示文件不可用不会将非法分析记录变为有效。

JSONDecoder 默认容忍扩展字段，便于展示层向前兼容；未知 version 不解释。schema 描述本版本输出。方案重命名不会改写已存在的侧文件；显示时间不能用于物理质量、收费或推荐依据。
