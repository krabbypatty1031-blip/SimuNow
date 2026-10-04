# SimuNow AI Agent 工作指南

## 项目与优先级

SimuNow 是 Mac 优先、尽可能兼容 iOS / iPadOS 的室内空调配置与运行分析工具。用统一模型连接 EnergyPlus 能耗与 OpenFOAM 气流，评价位置级舒适、用电和成本。
团队 3–4 人；比赛 48–72 小时；之后按 6–8 周路线完善。首个场景为单房间办公室或教室。
当前比赛交付已闭环到 **P5**：房间编辑、EnergyPlus L1 代表日、OpenFOAM L2 座位场、同口径对比、守卫 PDF。数值引擎只在 **Mac Debug** 本机执行。不要把未交付能力写成已实现：Release 沙盒 exec、iOS 本机求解、RoomPlan、L0 / L3、全年 EnergyPlus、设备报价与回收期。

## 开工阅读顺序

1. `README.md`、`Plans/README.md`、`Plans/Delivery/status.md`。
2. `Plans/References/01-product-scope.md`、`Plans/References/02-architecture.md`。
3. 本次任务相关的设计、协议、物理计划及 `Plans/Phases/P*/*.md`。
4. 修改公开接口时读 `Protocols/README.md`；平台能力读 `Plans/Delivery/platform-and-release.md`。

用户当次明确要求优先于仓库建议。仓库采用单任务工作默认值；需要多个 agent 同时改文件时先确认当前会话已有授权，明确文件归属，避免共享文件冲突。

## 模块归属与依赖

- `Apps/SimuNowMac`：macOS 入口、生命周期；Debug 本机 Process 跑 Python worker。Release 仍沙盒，生产 exec 走签名 helper（未交付），不以全局关 sandbox 当默认修复。
- `Apps/SimuNowiOS`：iPhone / iPad 入口，用于编辑与查看。不跑本地 EnergyPlus / OpenFOAM / Docker。RoomPlan 未做。
- `SimuCore`：Foundation-only Codable / Sendable 数据模型；不得依赖 UI 或外部引擎。
- `SimuSimulation`：跨平台异步任务协议；不将 Process、Docker 或 macOS 路径泄漏给 iOS。
- `SimuDesignSystem`：语义颜色、排版、空状态与可访问性组件。
- `SimuVisualization`：显示接口与场数据适配；不计算热负荷或推荐。
- `SimuReporting`：报告接口与证据要求；不重算指标。
- `SimuWorkspace`：共享状态、导航与业务工作流；通过依赖注入访问任务和报告。
- `Backend`：Python 编排、引擎转换、网格、后处理、质量与候选搜索。

坚持依赖方向：Core 在底层；Workspace 在顶层；平台入口组装适配器。计算引擎与渲染器各自可替换。

## Swift 与界面规范

使用 Swift 6、明确 Sendable 边界、UI 状态 MainActor。耗时任务不运行在主线程；不为消除编译错误随意增加 `@unchecked Sendable` 或关闭并发检查。
共享 View 使用 SwiftUI，平台差异封装在适配器、availability 或小范围 `#if os(...)`。macOS 14 / iOS 17 是当前最低版本；新增 API 先核对 SDK 可用性。
Mac 使用工作区与 inspector，iPad 自适应分栏，iPhone 保持导航可达。界面必须兼容深浅色、动态字号、VoiceOver，并用文字辅助状态颜色。
不建立没有功能的可点击按钮；未实现功能使用空状态或明确不可用状态。

## 物理与结果的硬约束

1. 设定温度、送风温度、制冷量、电功率、风量和速度必须分别建模与标注单位。
2. 公共模型为米制、右手 Z-up；Apple 到计算坐标转换集中管理。
3. 回风循环与室外新风分开；送回风质量平衡；CO2 源与室外交换守恒。
4. 人员与设备热源在 L1 / L2 中同口径；辐射与对流部分避免重复计入。
5. L0 平均估算不得包装为逐点 CFD；L3 预测不得包装为 L2 复核结果。
6. 稳态场不能推出开机降温时间；场动画依赖计算结果或清晰标注示意。
7. 质量检查未通过、未收敛、无有效采样的数据不能用于有效报告或推荐。
8. 舒适需要温度、辐射、速度、湿度、衣着与活动等依据；超模型范围显示不可评价。
9. 一天模拟不能直接推算全年节能；没有价格来源不编造设备费用与回收期。
10. 不把“达标座位比例”称为实测满意率，不生成未经统计校准的置信度百分比。

## 数据与任务规范

每次运行保存不可变输入快照、run ID、scenario ID、输入哈希、引擎版本、求解设置、网格与质量记录。
旧任务完成后只进入其所属运行；不覆盖当前方案。任务成功、质量通过、结果新鲜度是独立状态。
共享 JSON 接口改动同步更新 Swift Codable、Python 解析、schema、迁移说明和相应契约验证。当前契约覆盖 project-draft v2、request / event / receipt、L1 / L2 result、field-slice、field-flow、report-evidence。缺分区的草稿不能当作可求解项目；有草稿也不等于质量门已通过。
二进制场写清坐标、单位、float 格式、endian、轴序、有效掩码与哈希。墙和家具内部无效数据不能按 0 参与统计。
路径以项目根或项目包为基准；禁止硬编码开发者 Desktop / Downloads 路径。

## 构建与验证

```bash
Scripts/check.sh test
Scripts/check.sh mac
Scripts/check.sh ios
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
```

共享模型改动执行相关契约测试；共享 UI 改动编译两端并按条件做显示检查；引擎改动执行对应物理验证与守恒检查。
文档或低影响外观改动做相应检查，不添加只重复实现的测试。构建成功、模拟器运行成功和物理验证成功分别记录，不能互相代替。
App schemes 当前无 UI 测试 target；共享单测通过 SwiftPM 执行。

## 项目文件与依赖

新增包内源码无需改 pbxproj。App target / 资源 / 配置变动维护 `Scripts/generate_project.py`；生成后检查 scheme 与平台编译。
不自动安装大型计算软件，不在 App 启动时下载依赖。已锁定 **EnergyPlus 25.2.0** 与 **OpenFOAM v2512**（`linux/arm64`，求解器 `buoyantBoussinesqSimpleFoam`）；安装脚本在 `test/engines/`，二进制不入库。
不提交 build、场数据、原始房间照片、密钥、开发者证书或签名资料。匿名基准夹具应带来源；真实房间资料默认本地。
Mac Debug 为跑引擎可关 sandbox（见 entitlements）；Release 保持沙盒与 library validation。接入 Process / helper / 容器时先按部署计划验证权限与打包。

## 完成与记录

以用户授权范围完成可审查的结果。提交或交接前更新 `Plans/Delivery/status.md` 的任务状态与证据；重大选择记录到 `Plans/Delivery/decisions.md`。
简洁报告：改动、验证、尚未实现或未验证的限制。不要因 UI 看起来完整就标记物理阶段完成。
