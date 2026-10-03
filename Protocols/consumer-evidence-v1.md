# N5/N6 固定证据 v1

新增独立 sidefile / 导出协议，不改变 project v2、包 v1 或既有 native 方法版本。由 `generate_consumer_schemas.py` 同步生成 `Protocols/Schemas` 与 Core 资源。Python `models.consumer_evidence.decode` 负责开发解析；消费者 App 不依赖 Python。

## 文件与身份

| 路径/格式 | 限制与检查 |
|---|---|
| `analysis/comparisons/<comparison-id>.json` | owner `com.simunow.comparison`、recordVersion 1、2–3 独立方案/run、固定 snapshot、input/result SHA-256；单份 ≤256 KiB |
| `measurements/<dataset-id>/data.json` / `manifest.json` | owner `com.simunow.measurements`、dataset/artifactVersion 1；原来源 SHA-256、实际 data hash/字节数、project/dataset UUID；data ≤8 MiB、manifest ≤4 KiB；CSV ≤4 MiB、10000 行 |
| `analysis/calibrations/<id>.json` | calibrationVersion 1、独立 experimental finiteJet 方法；dataset SHA/ID、房间几何 SHA、设备、安装 origin/direction、实测风档、训练/验证 IDs、误差、实际测距范围与门槛；≤256 KiB |
| `captures/<capture-id>/geometry.json` / `roomplan.json` / `manifest.json` | captureVersion 1、米制右手 Z-up、Apple 世界原点转换、矩形尺寸与 ≤128 家具盒体；geometry ≤256 KiB、原 RoomPlan JSON ≤8 MiB；两文件 SHA、本地 project/capture 身份 |
| `redacted-report` / `redacted-measurements` JSON | exportVersion 1、owner、hashFormat、exportHash、snapshot；派生摘要，不能代替可复算原输入 |
| `professional-review-configuration` / `professional-review-receipt` | 独立 version 1 严格字段；配置不含 token；receipt 必须匹配每次请求身份、预期引擎/版本、质量与基准；≤2 MiB 响应 |

已识别配置、运行、费用、比较、测量和校准累计 ≤32 MiB，仍满足原整包预算。未知/未来附件保留，不能变成有效证据或被自动删除。原扫描同时受整包限制。

## Hash 与冻结

`ComparisonRecord.bodyHash` 对编码 record 移除 bodyHash 后，用既有 `simunow.native.canonical.v1` 的无 schema 数值 token 模式取 SHA-256。读取时同时复核真实父 input/result 字节 SHA、费用引用并重建比较口径，不能只核对 bodyHash。指标计算仍在 Simulation，Reporting 只读取冻结值。

报告 hashFormat 为 `sha256.sorted-json.iso8601.v1`：UTF-8 JSONEncoder sortedKeys/withoutEscapingSlashes，Date 为 ISO 8601，对 **snapshot 单独编码的字节**取 SHA-256。测量摘要为 `sha256.sorted-json.v1`，同样对 snapshot 字节取 hash。第三方校验必须保持数值 token、排序与字符串编码；独立 Python 检查真实 Swift 输出。源 inputHash/sourceSHA256 是追溯值，不能从删减摘要重算原输入/来源文件。

默认报告不含个人名称、房间完整几何、照片、私有来源、路径或自由备注。测量摘要进一步删除位置、绝对时间、UUID、仪表备注/标识和风档名称，使用稳定别名；保留数量值、SI 单位、质量/分组及门窗观察。无空间与时间的匿名测量摘要不能进入校准。

## 质量与适用范围

measurement 数量类型绑定 SI 单位；严格有限值/物理范围/唯一 record UUID；时间需有效 Gregorian 日期与显式 Z/偏移。有效质量需数值；missing 保留 null；非 valid 必须有原因。CSV 仅按明确类型做 K/degF/kW/kmh/Ls/m3h 转换，坏行隔离并记录，不能自动填零。

有限射流仅使用有仪表范围/校准依据、同设备/风档、关闭门窗的有效记录。出口速度来自 calibration 分组；至少 6 个训练与 3 个独立验证点。验证数据不选择参数，位置+同一实际瞬间不能跨组泄漏；范围端点最优、超误差或比原参数更差均保留失败证据。`ScopedFiniteJetModel.verified` 对固定原 dataset 再拟合复核；预测还必须匹配 project/device/geometry/fan 与**当前出口 origin/direction**并位于实测轴向/径向范围。它从不注册为原规则方法，也不升级 basis。

动态 RC/CO₂、2D CPU 网格与节点适配为独立研究 API。旧 run 永不重标 `validated`；未收敛、CFL 越界、节点版本/质量/授权失败不能出有效产品结论。

## 迁移与文档事务

旧包无需迁移。没有新增 sidefile 时行为不变；旧客户端按未知附件保留新记录。原生包开启新的 documentInstanceID；正常值事务保留 instanceID，侧文件修改产生独立 revision。异步封装捕获实例，完成后以最新 DocumentGroup binding 原子合并；重开解析还核对侧文件 revision。原 run 只追加，输入 undo 不删新证据；历史引用缺失则不可用，禁止用现输入补旧快照。

外部节点未接 App 启动或消费者界面；配置与每次确认参数必须由未来平台入口显式给出。认证只存在请求内存，不写项目；拒绝重定向，HTTPS 结果引用同 host/port 且无内嵌凭据。实际机构数据政策、sandbox 网络权限与基准需独立验收后才能启用。
