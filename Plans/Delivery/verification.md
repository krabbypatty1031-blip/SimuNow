# 工程验证记录

日期：2026-10-02；环境：Apple Silicon Mac、Xcode 27.0 (27A266a)、Xcode Swift 6.4、macOS/iOS SDK27。
工程最低 macOS14/iOS17、Swift6模式；最低系统实机运行尚待验证。

## 最终目录验证结果

验证从 `/Users/pacoramirez/Desktop/SimuNow` 执行，确认本地包和文件使用相对路径，工程可搬移。

| 检查 | 结果 | 说明 |
|---|---|---|
| pbxproj 语法与共享 scheme XML | 通过 | plutil 与 XML 解析 |
| Swift Package 测试 | 通过，3项 | draft round-trip、旧 run 新鲜度、未配置引擎拒绝成功 |
| SimuNowMac Debug | BUILD SUCCEEDED | 当前 Apple Silicon 架构，关闭签名构建 |
| SimuNowiOS Debug | BUILD SUCCEEDED | generic iOS Simulator，不需要开发团队 |
| Mac 启动与界面 | 通过 | 空工作区、sidebar、inspector、报告空状态可见 |
| Xcode 打开工程 | 通过 | 两端 shared schemes 与本地包可见 |
| 文档本地链接 | 通过 | 21份计划文档，无失效相对链接 |
| Python doctor | 通过 | worker正常，四级引擎均明确 not_configured |
| iOS实际启动/真机/最低系统 | 未验证 | 编译通过不等于设备运行验证 |
| CFD/能耗/扫描/报告物理能力 | 尚未实现 | 依对应阶段推进 |

最终构建命令：`Scripts/check.sh all`。共享包使用 Swift Testing，日志中的 XCTest 0项不代表未测试；后续 Swift Testing 输出确认3项通过。
Mac 观察显示报告空状态的三栏布局，未展示任何数值结果。用户可在 Xcode 选择 SimuNowMac / My Mac 运行。
构建中的 AppIntents metadata 未抽取提示属于当前没有依赖 AppIntents 的说明，不阻断构建。

## 验证范围

项目结构、共享包契约、macOS Debug 和 generic iOS Simulator 编译、worker 能力探测。
当前没有物理求解器、扫描、真机或报告实现，不能视为这些能力验证。

## 环境处理

系统命令行默认 CommandLineTools；脚本显式设置 DEVELOPER_DIR，不修改全局选择。
Desktop/Documents 的 File Provider 属性可影响测试 bundle 签名，因此脚本默认使用临时构建目录。
Debug 设置 ONLY_ACTIVE_ARCH=YES，保持 App 与本地包架构一致；Release 仍使用默认多架构设置。


## P2-01 验收（2026-10-02）

本轮实现项目输入基座，不改变物理阶段状态。与原 P0 验证共用 Apple Silicon/Xcode 环境；临时独立 Python 3.13 环境使用 requirements-dev.lock（pydantic 2.13.4、jsonschema 4.26.0 及锁定传递依赖）。

实际验收命令：`SIMUNOW_PYTHON=/tmp/simunow-p2-venv/bin/python Scripts/check.sh all`，退出码 0。复现时可按 Backend/README.md 建立 Backend/.venv 后运行 `Scripts/check.sh all`，无需沿用临时路径。另执行 `PYTHONPATH=Backend/src python3 -m simunow_worker doctor`。

| 检查 | 结果 | 证据与范围 |
|---|---|---|
| 生成结构/schema 漂移 | 通过 | generate_domain_models.py --check、models.schema --check |
| Python 单测 | 14 项通过 | 严格解析、独立 Draft202012Validator、迁移、完整性、精确未知值、快照、注册/规则/几何扩展 |
| Swift Testing | 16 项通过 | SimuCoreTests 14 项（含 P0 原有 3 项）+ 独立 SimuExtensionTests 2 项 |
| 跨语言真实交换 | 通过 | Python→Swift→Python 和 Swift→Python→Swift；2 份项目/快照、28 类语义错误或未知扩展，另有结构/损坏输入拒绝 |
| 未知 payload | 通过 | 数值 token 保留大整数和高精度小数；不支持类型阻断准备，不冒充已知类型 |
| OCP | 通过 | 独立设备实现/schema/注册及额外规则覆盖项目与快照；自定义几何查询作用于校验 |
| macOS Debug | BUILD SUCCEEDED | CODE_SIGNING_ALLOWED=NO；共享模型和 schema 资源集成 |
| generic iOS Simulator Debug | BUILD SUCCEEDED | CODE_SIGNING_ALLOWED=NO；最低目标仍为 iOS17 |
| doctor | 通过 | scaffold；l0/l1/l2/l3 均 not_configured |
| 本轮 App 启动/真机/最低系统 | 未验证 | 编译不能替代运行 |
| 求解/守恒/舒适/能耗物理验证 | 未实现 | 输入一致性校验不是求解质量证据 |

日志位于忽略的 `Artifacts/P2-01/check-all.log` 和 `doctor.json`。AppIntents metadata 提示与 P0 一致：当前无该框架依赖，不阻断构建。测试 fixture 是人工接口数据，天气路径与全零哈希不对应真实资产。
