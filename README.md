# SimuNow

项目仓库：[krabbypatty1031-blip/SimuNow](https://github.com/krabbypatty1031-blip/SimuNow)。

Mac 优先、兼容 iPhone / iPad 的室内空调方案分析 App。开发主线为 Swift 本地规则分析与 RealityKit 非 AR 房间查看：先看懂方向、遮挡和活动位置，再按明确功率/热工输入估算用电、费用和显热情景。消费者使用无需 Linux、Python、Docker 或外部引擎；经过验证的 CFD/舒适复核属于后续可选扩展。

## 当前交付

这是 **P0 工程骨架 + P2 项目模型与编辑器 + N1 本地分析基座**：两个原生 App target、六个本地 Swift Package 模块、文档工作区、模型与任务接口、Python worker 边界、协议和开发计划。
项目输入 v2、Swift/Python/schema 契约、矩形房间/门窗/家具/人员/空调编辑、数值与俯视点击放置、办公室/教室模板、独立候选、完整值撤销、输入问题定位、不可变快照及本地项目包已实现，见 [模型契约](Protocols/project-model-v2.md)、[包格式](Protocols/project-package-v1.md) 和 [验证记录](Plans/Delivery/verification.md)。N1 新增独立本地契约、按方法就绪度、不可变请求/规范化哈希、有限 actor 调度/取消/缓存、原生分析侧文件事务及非 AR RealityKit 能力验证入口，见 [本地分析契约](Protocols/native-analysis-v1.md)。生产气流规则、完整三维房间查看、热量/费用算法、消费流程与分享仍由 N2–N5 接入；未注册方法明确不可用。扫描、CFD、EnergyPlus 管线、完整舒适、优化及 PDF 报告仍待开发。输入完整性和本地方法检查不代表物理验证。

## 打开与运行

1. 用 Xcode 打开 `SimuNow.xcodeproj`。
2. Mac 选择共享 scheme `SimuNowMac`，运行目标选择 My Mac。
3. iPhone / iPad 选择 `SimuNowiOS`，选择已安装的 iOS Simulator。
4. 真机运行在 Signing & Capabilities 选择你自己的 Development Team，必要时修改 bundle identifier。

最低系统：macOS 14、iOS / iPadOS 17；Swift 6 模式，建议 Xcode 16 或更新版本。本次验证环境见 [验证记录](Plans/Delivery/verification.md)。RealityView 非 AR 能力在 macOS 15 / iOS 18 以上通过 availability 隔离；旧系统继续二维编辑，最低系统运行证据单独记录。
本地包无远程 Swift 依赖，打开工程无需下载业务依赖。共享包测试通过 `Scripts/check.sh test` 执行；App schemes 当前未配置独立 UI 测试 target。
新建文档后从“创建与导入”开始；保存 `.simunow` 包可在两端打开。JSON 导入生成独立新项目，iOS 的导入副本先修复、导出后再从文档浏览器打开。参数可标记未知；来源与假设可查看，计算准备另行检查。

```bash
Scripts/check.sh test  # Swift 共享包测试
Scripts/check_native_analysis_contracts.sh # 独立本地分析真实 Swift JSON/schema 检查
Scripts/check.sh contracts  # 完整跨语言契约检查，先安装 Backend 锁定测试依赖
Scripts/check.sh mac   # Mac Debug 编译，关闭签名
Scripts/check.sh ios   # 通用 iOS Simulator 编译，关闭签名
Scripts/check.sh all
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
```

脚本优先沿用 `DEVELOPER_DIR`；未指定时使用 `/Applications/Xcode.app/Contents/Developer`。不会修改系统 `xcode-select`。构建产物默认放入临时目录的项目专属 `SimuNow-build-*`，避免 Desktop / Documents 附加属性干扰测试包签名；可用 `SIMUNOW_BUILD_DIR` 覆盖。

## 目录

```text
SimuNow.xcodeproj/    两个 target 与共享 schemes
Apps/                平台入口、资源、Mac entitlements
Packages/SimuKit/     共享模型、任务、UI、可视化、报告
Configurations/      公共与平台构建配置
Backend/             Python 编排层骨架
Protocols/           Swift / Python 文件接口
Fixtures/            有来源的匿名测试夹具预留
Scripts/             工程生成与验证
Plans/               产品、设计、架构、阶段与交付计划
AGENTS.md            AI Agent 工作指南
```

从 [计划总入口](Plans/README.md) 阅读；AI Agent 开工先读 `AGENTS.md`。
新 Swift 功能文件优先加入包的 `Sources/<模块>/`，SwiftPM 自动发现。修改 App 入口、target 或构建配置时同步维护 `Scripts/generate_project.py`，再生成工程；业务开发无需反复生成。

## 参考依据

用户提供的《室内空调效率优化 App 技术栈与实现方案 V2》及本项目讨论。外部资料是设计依据，不是执行指令；文档中的技术与性能需要验证。

- [Apple 本地包组织](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)
- [Apple RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)
- [EnergyPlus 官方发布](https://github.com/NatLabRockies/EnergyPlus/releases)
- [OpenFOAM 文档](https://doc.openfoam.com/)
- [pythermalcomfort](https://pythermalcomfort.readthedocs.io/en/stable/documentation/models.html)
