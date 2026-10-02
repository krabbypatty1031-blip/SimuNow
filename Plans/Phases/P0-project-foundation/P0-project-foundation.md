# P0：工程与工作边界

## 目标与前置

建立能打开、编译的 Mac/iOS 工程与共享模块；前置为 Xcode、空项目目录和产品方向已确认。

## 功能、设计与技术

两平台入口、可导航的空工作区、Mac inspector、共享 draft 与任务协议。SwiftUI、Observation、SwiftPM、Swift 6、xcconfig、共享 schemes。无数值模拟或假指标。

## 工作项

| ID | 工作 | 输出/验证 |
|---|---|---|
| P0-01 | 创建 target、最低版本、资源与签名占位 | macOS/iOS Simulator 编译 |
| P0-02 | 共享模块、依赖注入、任务/来源/坐标类型 | SwiftPM 契约测试 |
| P0-03 | AGENTS、逻辑计划、协议和 worker 边界 | 文档链接、schema、doctor 检查 |
| P0-04 | 验证、平台限制、后续任务记录 | status / verification |

## 验收与交接

打开工程可选择两个 shared scheme；包无远程依赖；Mac/iOS 导航可达；未配置计算明确不可用。构建/运行/物理验证分别记录。
Development Team 保留用户选择；不更改全局 Xcode 配置。交接从 P1/P2 开始。

## 降级

缺少模拟器运行时先完成 generic Simulator 编译并记录运行未验证；不能宣称真机验证。物理引擎不影响工程骨架验收。
