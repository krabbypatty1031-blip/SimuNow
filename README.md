# SimuNow

项目仓库：[krabbypatty1031-blip/SimuNow](https://github.com/krabbypatty1031-blip/SimuNow)。

Mac 优先、兼容 iPhone / iPad 的室内空调方案分析 App。通过房间与 HVAC 模型、能耗计算、室内气流 CFD、座位级热舒适评价，对比运行设置与设备配置的成本和效果。

## 当前交付

**P0 工程骨架 + P2 房间编辑全套 + P3 任务链路与 L0 能耗**：两个原生 App target、六个本地 Swift Package 模块、可导航的工作区；五步建房向导、办公室/教室模板、俯视图编辑、参数检查器（单位/来源/未知原因）、校验列表、`.simunow` 项目包原子保存与 v1 迁移导入。
计算链路：项目输入 v2 契约、Swift/Python 双端输入哈希（契约交换验证一致）、`run-input/1` 请求、`run-event/1` JSONL 事件流、`run-result/1` 原子结果、L0 稳态代表日能耗适配器（集总平均估算，明确标注，非 CFD）、Mac 本地执行器（posix_spawn 进程组与协作取消）、任务页与结果新鲜度（改输入即「待重算」）。
扫描、真实 CFD（OpenFOAM）、EnergyPlus L1、舒适评价、方案对比报告均为待开发；本机引擎未安装，doctor 如实报告 blocked。未知参数不填 0，质量失败结果不可用于推荐。

## 打开与运行

1. 用 Xcode 打开 `SimuNow.xcodeproj`。
2. Mac 选择共享 scheme `SimuNowMac`，运行目标选择 My Mac。
3. iPhone / iPad 选择 `SimuNowiOS`，选择已安装的 iOS Simulator。
4. 真机运行在 Signing & Capabilities 选择你自己的 Development Team，必要时修改 bundle identifier。

最低系统：macOS 14、iOS / iPadOS 17；Swift 6 模式，建议 Xcode 16 或更新版本。本次验证环境见 [验证记录](Plans/Delivery/verification.md)。RealityView 等更高版本 API 在实际接入时用 availability 或版本决策处理。
本地包无远程 Swift 依赖，打开工程无需下载业务依赖。共享包测试通过 `Scripts/check.sh test` 执行；App schemes 当前未配置独立 UI 测试 target。

```bash
Scripts/check.sh test  # Swift 共享包测试
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
