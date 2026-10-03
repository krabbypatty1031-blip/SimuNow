# 平台与交付

## 能力矩阵与版本策略

| 能力 | macOS14 | macOS15+ | iOS/iPadOS17 | iOS/iPadOS18+ |
|---|---|---|---|---|
| P2 编辑/原生项目包 | 已有代码 | 已有代码 | 已有代码 | 已有代码 |
| 二维房间/对象查看 | 已有代码 | 已有代码 | 已有代码 | 已有代码 |
| Swift 本地规则与估算 | 计划支持 | 计划支持 | 计划支持 | 计划支持 |
| RealityView 非 AR 三维 | 首版二维回退 | N2 计划支持 | 首版二维回退 | N2 计划支持 |
| RoomPlan 扫描 | 不支持 | 不支持 | 后续、需硬件能力 | 后续、需硬件能力 |
| Python/外部引擎 | 可选研发复核 | 可选研发复核 | 不在本机运行 | 不在本机运行 |

上述“计划支持”不代表已实现。当前最低 macOS14 / iOS17、Swift6 不变；RealityView availability 核对为15/18，见 [官方/SDK依据](../References/09-source-register.md)。首版直接采用虚拟相机，不启用 AR world tracking；查看房间无需相机、LiDAR 或摄像权限。

N1-02 检查公开 API、编译与实际非 AR 场景。N2 的 availability/capability 选择 renderer；不调用私有 SDK 模块，不默认新引擎缺失是平台失败原因。提高最低版本需单独 ADR、Package/xcconfig/生成器一致更新和设备范围说明。

## 工程与运行时

保留 SimuNowMac/SimuNowiOS shared schemes、六个包与 DocumentGroup。新源码放包内；App target/资源/配置变化维护 generate_project.py，保留用户 scheme 定制。Development Team/bundle ID/正式签名仍由用户配置。

App 默认注入本地 client，不检测或安装 Python/Colima/OpenFOAM/EnergyPlus，不弹运行时修复提示阻断预览。Backend doctor 和锁定环境仅用于已有研发分支/专业复核，未卸载或删除。

Mac sandbox 和用户选择文件读写继续启用。本地 CPU 分析无需 Process/helper/容器桥接；项目包通过原生文档协调保存。外部复核重新评估签名、helper、节点、许可与权限后才接入，不继承默认关闭 sandbox 的做法。

## UI、内存和能耗

实体/材质/选择更新 MainActor，后台分析只传值。路径/模型缓存有限，停止显示后暂停动画，切后台/关窗取消相关订阅；iOS 内存与热状态单独记录。内存紧张降低显示密度而不改变已保存的方法结论，不能静默改实际分析配置。

旧系统和 Reduce Motion 用二维/静态箭头，仍能完成调整与比较。VoiceOver 可通过对象列表与建议文字操作，三维不是信息唯一入口。实际显示、最低系统和文件分享需要设备/运行时验证，generic build 不替代。

## 隐私与发布候选

房间、测量与照片默认本地；不引入账号、遥测上传、远程节点或自动设备控制。分享冻结结果可去身份，图中明确方法/假设。引入测量/扫描后按实际 API 添加权限与隐私描述。

交付顺序：双端构建→实际查看与文档操作→无网络/无 worker 试用→可访问性→图标/本地化/许可证/隐私→签名安装候选→新机器试装→用户授权后正式分发。N5 产生候选，不自动上传或公证发布。

已验证平台事实见 [verification](verification.md)，不能把本页的新路线当运行证据。

## N5/N6 当前开发候选边界（2026-10-03）

0.2.0(2) 资源与 unsigned Release archive 脚本已准备，见 [资源/隐私清单](consumer-resources-and-privacy.md)。保留原 deployment targets、sandbox、bundle IDs 和共享 schemes；摄像用途只在 iOS 主动 RoomPlan 流程声明。无 Xcode 的本轮 Linux 环境不能产出安装候选；签名、公证/商店、真机安装与旧包升级仍未验。

正式部署门槛还包括 [N5/N6交接](N5-N6-implementation.md) 中的完整 Swift 包、双端 Debug/Release、长中文 PDF 页图、系统分享/取消、浏览器导出再开、最低系统/VoiceOver/动态字号、两端试用及许可证确认。可选专业复核没有默认节点或启动调用，也没有新增 Mac 网络 entitlement；实际节点需求与隐私/权限审查后再启用。
