# 架构决策记录

## ADR-001：双原生 target + 本地共享包（已接受）

背景：Mac 主工作区，iOS 后续采集与浏览；平台能力不同。
选择：两个入口、一份 SimuKit，业务/契约共享，执行与采集适配。
影响：平台编译可独立验证，避免 Process 泄漏移动端；维护两个最小入口。

## ADR-002：macOS14 / iOS17 + Swift6（已接受）

选择：基础 SwiftUI 导航与 Observation 兼容上述系统，并发检查完整。
影响：RealityView 等调用在实现时 availability 或改 renderer；提高系统版本同步 xcconfig、Package 与计划。

## ADR-003：外部 worker 与文件协议（已接受）

选择：不可变 run、JSON/JSONL、二进制场、Python 引擎 adapter。
影响：可复算、可缓存、可远程扩展；Mac sandbox/运行时打包需 P3 实证。

## ADR-004：稳定工况多保真度（已接受）

选择：比赛先 L0/L1/L2；单向边界；代理/瞬态后续。
影响：用户收到代表日与稳态位置评价；年度/降温时间需要另建数据和模型。

## ADR-005：占位明确不可用（已接受）

选择：空工作区、UnconfiguredSimulationClient 抛错、worker doctor 返回 not_configured。
影响：架构可开发，任何显示收益都要真实计算依据；人工 fixture 仅用于接口测试。

## ADR-006：组合与注册扩展（2026-10-02，已接受）

触发：P2-01 必须支持新增设备/几何而不修改项目聚合与中央类型分派。备选：中央 enum/大型设备基类、运行时插件、代码扩展注册。选择：强类型 payload + 稳定 kind/version 外壳，不可变、注入的分类注册表，纯校验规则集合。几何实现自身查询；不引入运行时动态插件或引擎依赖。影响：新增实现/schema 片段/注册项即可接入，新增必需语义仍需版本迁移。证据：独立 SimuExtensionTests 设备全流程与几何查询测试、Python 对应测试。

## ADR-007：未知扩展无损保留（2026-10-02，已接受）

触发：旧 App 打开新设备项目不能丢失数据或伪装可计算。备选：拒绝整份项目、忽略未知字段、保留扩展并阻断计算。选择：JSONValue/FrozenJSON 保存数值 token 与 JSON 结构；ProjectCodec 是唯一项目 wire I/O 边界。未知 kind/version 保留，已知非法 payload 和未来根版本拒绝。影响：字段编辑仅用于已注册类型，不承诺 JSON 空白/键序保留。证据：大整数/高精度、小版本未知、非法已知 payload 和跨语言往返检查。

## ADR-008：项目与不可变场景输入分离（2026-10-02，已接受）

触发：避免编辑覆盖运行输入，并给 P3 留出环境/求解设置和哈希边界。选择：共享几何 + 完整场景值；纯快照保留 project/scenario 身份，将物理输入与成本评价分开。快照尚不等于 RunInput。Swift 使用 let/值语义，Python 使用 frozen/tuple/不可变 JSON。影响：编辑采用新值，P3 加入真实运行身份和哈希；保存留 P2-04。证据：嵌套快照不随项目修改的测试。

## ADR-009：共享结构清单与生成契约（2026-10-02，已接受）

触发：两语言新增完整字段容易漂移。选择：model spec 生成 Python/Swift 结构声明，Python wire model + 注册 schema 生成 Draft2020-12；行为在两语言独立实现并通过真实双向交换验证。Core 打包同一 schema 的资源副本；check 模式拒绝漂移。影响：生成文件不可手工修改，Schema 是结构验证，语义/物理规则另行检查。Swift 的 schema 校验只支持生成器使用的子集，未知断言失败。证据：contracts 的生成漂移、独立 jsonschema 与两端校验一致性检查。

## 待决定

- P1：OpenFOAM 分支/版本/求解器/网格与湍流，EnergyPlus 版本与设备模型。
- P3：Mac helper/companion 运行时和权限桥接，事件/重启策略。
- P4：renderer 及各平台预算、舒适档案与边界。
- P5：PDF 实现与成本数据；P7：代理/远程/发布渠道。

每条新增决策记录触发原因、备选、选择、影响、验证证据与日期。
