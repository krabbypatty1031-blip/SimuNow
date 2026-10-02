# P2-01：项目模型 v2

实现：`SimuCore/Project`、`Backend/src/simunow_worker/models`。本契约只描述输入；没有求解器、运行哈希、数值结果或报告。结构可解析、项目完整性通过、计算输入要求通过和引擎可用是不同条件。

## 结构与字段归属

| 对象 | 内容 | 必需性 |
|---|---|---|
| ProjectDocument | schemaVersion=2、UUID、名称、空间类型、m、rightHandedZUp、geometry、scenarios | 结构必需；数组允许空，表示未完成 |
| ProjectGeometry | rooms、obstacles | 结构必需；每个场景共享同一几何 |
| Room | ID、name、shape、northAngle、surfaces、openings | 北向允许显式未知；首个配置支持矩形单房间 |
| Obstacle | ID、roomID、name、shape | 首版轴对齐盒体 |
| Scenario | ID、name、完整 inputs、evaluation | 完整值，不采用补丁、继承或合并优先级 |
| ScenarioInputs | usage、hvac、controls、envelope、ventilation、environment | 各对象/数组结构必需；数据缺失使用未知或可选字段 |
| Usage | seats、occupants、equipment | 稳定身份；人数由人员记录及其时间表决定 |
| HeatGain | sensible、convectiveFraction、latent | 对流=sensible×fraction；辐射=sensible×(1−fraction)；不重复保存三份显热 |
| HVACDevice | ID、roomID、name、position、definition、ports、supplyTemperature | 设备性能与运行送风状态分开 |
| AirPort | ID、role、position、direction、area、volumeFlow、speed、density | 供回风各自声明；质量检查需要密度依据 |
| Control | ID、deviceID、setpoint、sensorPosition、schedule | 设定温度不等于送风温度 |
| Envelope | 表面配置、窗配置 | 引用 geometry 中的稳定表面/开口 ID |
| RoomVentilation | roomID、outdoorAir、exhaustAir、infiltration、exfiltration、density、openings | 四项均为明确的室外交换；密度是该组体积流量共同换算依据 |
| Environment | 代表日、时区、天气引用、室外温湿度、室内湿度 | 代表日/时区/天气可省略；物理参数允许未知 |
| EvaluationInputs | CostInputs | 不属于物理输入；后续哈希投影应分开处理 |
| CostInputs | currency、tariffs、quotes | 缺失费用不填 0；已知报价/电价必须有币种 |

完整字段声明以 `Backend/src/simunow_worker/models/spec.py` 为结构源，生成 Python 强类型类及 Swift 值类型；行为分别实现，不由生成器推导。禁止直接编辑生成文件。

## 单位、未知与来源

已知参数：`{state:"known", value:<有限数>, unit:<固定单位>, source:{kind,reference?,note?}, uncertainty?:{lower,upper,meaning}}`。
未知参数：`{state:"unknown", reason:<非空说明>}`。未知状态不能同时携带 value/unit/source。

数量类型包括 m、m2、degC、W、m3/s、m/s、Pa、deg、1、met、clo、kg/m3、W/(m2.K)、W/m2、currency、currency/kWh。显示层可显示 m²、°C 等；wire 使用上述 ASCII 单位。ThermalPower 与 ElectricalPower 在两种语言中使用不同已知类型，单位同为 W。

比例的范围依语义判断：湿度、SHGC、遮阳、开口比例、时间表比例、对流比例为 0…1；COP 是正的无量纲性能系数，不能限制为 0…1。热流允许有符号，其他功率/流量非负。温度不得低于绝对零度。

所有已知物理参数必须声明 scan/measured/manufacturer/user/preset/assumed 来源。计算准备时 measured/manufacturer/preset 要有 reference，assumed 要有 note。不确定性上下界须包含数值并说明含义，不能当作统计置信度。

可选字段 null/缺失统一重新编码为省略；数组必须存在。不自动填尺寸、人数、送风状态、价格或性能。`ProjectDocument.unfinished` / Python `unfinished_project` 生成空项目；`Scenario.unfinished` / `unfinished_scenario` 的气象物理参数为显式未知。

## 坐标、几何与时间

坐标为米制、右手 Z-up，原点在矩形底角，X=width，Y=depth，Z=height。北向为水平面从 +Y 顺时针到真北的角度，范围 [0,360)。所有位置及方向均在房间计算坐标中。当前配置仅允许一个房间；多房间不丢数据，但阻断计算准备。

六个面为 xMin/xMax/yMin/yMax/floor/ceiling。开口局部 U/V：X 面沿 +Y/+Z，Y 面沿 +X/+Z，地板/天花板沿 +X/+Y；开口 offset 对应其最小角。首版输入查询为轴对齐矩形/盒体，不代表网格已经生成或通过质量检查。

显示坐标转换集中在 SimuVisualization.CoordinateTransform：`(x,y,z) → (x,z,-y)`，逆变换 `(x,y,z) → (x,-z,y)`。位置、方向、位移和重力用同一旋转。几何容差为 1e-6 m；端口 direction 必须单位化，实际速度方向：送风指向房间，回风指向室内机。端口与求解 patch 法线的关系由 P1/P3 adapter 验证。

DailySchedule 的区间是代表日本地时间的 [startMinute,endMinute)，范围 0…1440，按时间排序、不重叠；首个物理输入配置要求人员、设备热源和控制时间表完整覆盖一天。停用时段显式设置 fraction=0；跨午夜拆段。日期为 YYYY-MM-DD，时区为 IANA 标识；DST 时长转换在 L1 adapter 中处理，本层不把本地一天固定当成 24 个实际小时。

身份在 geometry 及每个场景作用域唯一。各场景可沿用相同座位、人员或设备 ID 表达相同对象；场景 ID 全项目唯一。引用必须在正确作用域，开口所属房间、窗配置引用窗而非门。ID 不因数组排序或名称变化而改变。

## OCP 扩展

扩展外壳为 `{kind,payloadVersion,payload}`，kind 使用命名空间标识，payloadVersion 是正整数，payload 是 JSON 对象。

内置：

| 类别 | kind | version |
|---|---|---|
| room | simunow.geometry.rectangularRoom | 1 |
| obstacle | simunow.geometry.box | 1 |
| hvac | simunow.hvac.singleSplit | 1 |

新增 Swift 设备：实现 ModelPayload，提供 Codable/Sendable 数据、schema 片段和可选 validate；以 ModelRegistration 在应用组装处注册。几何实现 GeometryPayload，负责 containment、surfaceExtent 和 intersects；AxisAlignedGeometryPayload 是显式可复用策略。Python 对应新增 WireModel + Registration；几何提供 Bounds 与 GeometryQueries，设备附加规则通过 Registration.rules 注入。

注册表组装后不可变、重复键立即失败。识别键是 category/kind/version，没有中央设备枚举或新增类型 switch。测试扩展位于独立 SimuExtensionTests target 和 Backend/tests，不进入生产注册表。

已知非法 payload 是契约错误；已知类型出现在错误类别也拒绝。未知 kind 或未知 payloadVersion 保留，ProjectValidator 返回 unsupported_type，只阻断计算准备。未知 payload 不能通过已知类型解析进入参数编辑；编辑入口须查询注册表。ExtensionRecord 本身不可变，已知字段编辑后以强类型构造新记录。

Swift 项目/快照 I/O 必须使用 ProjectCodec，内部由 JSONTreeCoding 驱动 Codable；不能用 Foundation JSONEncoder/JSONDecoder 替代无损 wire 边界。JSONValue / Python FrozenJSON 保留未知数值 token、null、对象及数组；不承诺空白/键顺序。重复键、非 JSON 的 NaN/Infinity、无效 UTF-8、损坏 JSON 被拒绝。公共数量使用有限 Double/float，身份使用规范 UUID，整数范围为 signed int64。

新增类型允许新增 schema 定义与注册项，不改变项目聚合结构。既有语义/必需结构变化升级根 schema 并提供迁移；当前 v2 中的未知扩展能保留，不意味着未知未来根版本可以解释。

## 校验、迁移、快照

ProjectCodec 检查结构、单位、版本和已知 payload；ProjectValidator 组合 ParameterRule、IdentityRule、GeometryRule、PhysicsRule，允许注入附加规则。错误含 code/path/entityID?/severity/blocks/message，path 为 JSON Pointer。projectIntegrity 与 inputPreparation 独立，用户修复可定位具体字段。

默认计算准备配置要求单房间、单台设备、送回风口、完整围护/窗/控制/通风配置、采样点、代表日与天气。没有密度或流量依据不能判定质量平衡；输入一致性容差为相对 1e-6，不是 CFD 的收敛/守恒验收门槛。

InputRequirements 声明 adapter 的 requiredPaths/fullDaySchedulePaths，未来 L1/L2 可以增加需求；不能用通用输入配置替代真实 adapter 能力检查。天气文件是否存在、哈希是否匹配实际文件，以及引擎/设备曲线适用性在后续 adapter 阶段验证。人工 fixture 的假天气引用不能提交真实计算。

v1 → v2 迁移仅保留 ID/name/spaceType/单位与坐标，返回说明和未完成项目；不写回原文件，不补造房间/场景。ProjectCodec 拒绝 v1 和未来根版本，v1 必须显式经过 ProjectMigrator。

ScenarioSnapshotBuilder 按 scenario ID 捕获独立输入，保留 projectID/scenarioID；不包含项目/场景显示名称、UI 选择等编辑状态。Swift 顶层 let + 嵌套值语义；Python 冻结模型 + tuple + FrozenJSON。evaluation 与物理 inputs 分开，P3 再加入环境/求解器/网格版本及哈希；本快照不是 RunInput。

## 生成与验证

```bash
python3 -m venv Backend/.venv
Backend/.venv/bin/python -m pip install -r Backend/requirements-dev.lock
PYTHONPATH=Backend/src Backend/.venv/bin/python Scripts/generate_domain_models.py
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker.models.schema
Scripts/check.sh contracts
Scripts/check.sh mac
Scripts/check.sh ios
```

contracts 检查结构生成漂移、schema 漂移、独立 Draft202012Validator、Python 单测、Swift 单测，以及 Swift→Python→Swift 和 Python→Swift→Python 的真实数据交换。Core 打包一份相同 schema 资源；本机无远程 Swift 依赖。Swift WireSchema 只支持当前生成器使用的 Draft 2020-12 子集，遇到未知断言关键字失败；不声明为通用 schema 引擎。

可通过 SIMUNOW_PYTHON 指定其他已安装锁定依赖的独立虚拟环境。测试交换数据放临时目录，结束清理。App 不自动下载任何依赖。
