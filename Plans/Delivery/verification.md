# 工程验证记录

日期：2026-10-03（P4-02 全量 / P3）/ 2026-10-02（P0–P1）；环境：Apple Silicon Mac、Xcode 27.0 (27A266a)、Xcode Swift 6.4、macOS/iOS SDK27。
工程最低 macOS14/iOS17、Swift6模式；最低系统实机运行尚待验证。

## P4-02 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，93 项 | 含 `L2ResultTests`：门禁缺项不通过、`allGatesPass` 镜像 Python、`result-l2.json` 解码、`result-l1.json` 向后兼容 |
| Python `unittest discover -s Backend/tests` | 通过，55 项（约 20.6s） | 含钉版 `test_l2_runner` 全管线：state succeeded、quality passed、`checkMesh ok`、`monitorsStable`、座位 tC>15、`seat_t_c_min` 非 omitted |
| `python3 test/p1/test_quality.py` | 通过，5 项 | 进口面导热合成 case 手算 −51.0087 W；湍流/计数不匹配/缺 patch 拒绝；2026-10-03 弱射流回归：计入过、不计 23% 挂 |
| `python3 test/p1/test_room.py` | 通过，8 项 | 预算新必填 `q_inlet_cond_w` 后全绿 |
| 钉版 L2 管线数值 | quality passed | 质量相对误差 2.35e-6；能量相对误差 **0.19%**（计入门禁前假象 23.4%）；`terms_w.q_inlet_cond = −305.9 W`；座位 25.08 / 25.09 / 25.39 / 25.38 °C，uMag 0.026–0.034 m/s 全带 `lowSpeedAbsoluteError` |
| `Fixtures/task/result-l2.json` | 钉版真值 | 固定 UUID（aaaa…/cccc…）；真实收敛场数值，非手编 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | `SimulationResult` 加可选 `qualityDetail`/`seatSamples` 后两端编译兼容 |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 同上 |

不得当作产品功能：稳态场不推降温时间；座位温度是模型值非实测满意率；进口面导热使弱射流房间偏冷约 2.3 K，属该供应模型后果；带缩放（送风/窗）为整墙跨度假设。

## P3 全量验证（2026-10-03）

| 检查 | 结果 | 说明 |
|---|---|---|
| `Scripts/check.sh test` | 通过，85 项 | 协议、stub、真实 L1、Workspace 提交、WorkerTree 暂存 |
| Python `unittest discover -s Backend/tests` | 通过，37 项 | 含 `test_task_protocol` / `test_l1_runner` / `test_l1_schedule` / `test_python39_worker` |
| `python3 -m simunow_worker doctor` | 通过探测 | 系统 Python 3.9 可启动；无引擎时不编造瓦特 |
| `Scripts/check.sh mac` | BUILD SUCCEEDED | sandbox 仍为 true；Mac 有 Stage WorkerTree |
| `Scripts/check.sh ios` | BUILD SUCCEEDED | 无 `LocalProcessClient` / `Process` |
| 计算按钮 | 无 | 文案是「提交代表日 L1」；未配置时不可点 |
| App 手测 | 办公室 L1 `succeeded` | 冷量 3099.335 W，电功率 1033.112 W，全年未知 |
| P3 清单 | 01–11 已勾选 | 闭环只覆盖代表日 L1，不是 CFD |

不得当作产品功能：缓存仅进程内存；取消是 `terminate()` 不是进程树；一天不能推全年；围护是引擎默认；不是逐点 CFD。

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
| Python doctor | 通过 | worker 正常；P1-01 起在 `SIMUNOW_ENGINES_ROOT` 下 L1/L2 为 configured |
| OpenFOAM P1-02 基准 | 通过 | `test/p1/run_benchmarks.py`；方腔 Nu=2.260 vs 2.243；射流 Um/U0=0.781 vs 0.783；**本条只证明浮力与能量扩散离散，不能证明送风射流、短路或座位分层** |
| P1-03 房间管线 | 通过 | `SIMUNOW_ENGINES_ROOT=test/engines python3 test/p1/run_room.py --input test/p1/fixtures/room_p1.json`；run `20261002T135352Z`/`20261002T135415Z`；`quality.pass=true`；质量 ~0、能量 0.41%；复算座位 ΔT=0 |
| P1-04 EnergyPlus 代表日 | 通过 | `python3 test/p1/run_l1.py --input test/p1/fixtures/room_p1.json`；run `20261002T134747Z`；`EnergyPlus Completed Successfully`；冷量 6334.87 W，电耗=冷量/3；无年节能量 |
| P1-05 粗/中网格 | 通过 | `python3 test/p1/mesh_study.py`；粗 2.9s / 16.0 MB，中 14.3s / 19.8 MB；未做第三套网格 |
| iOS实际启动/真机/最低系统 | 未验证 | 编译通过不等于设备运行验证 |

最终构建命令：`Scripts/check.sh all`。共享包使用 Swift Testing，日志中的 XCTest 0项不代表未测试；后续 Swift Testing 输出确认3项通过。
Mac 观察显示报告空状态的三栏布局，未展示任何数值结果。用户可在 Xcode 选择 SimuNowMac / My Mac 运行。
构建中的 AppIntents metadata 未抽取提示属于当前没有依赖 AppIntents 的说明，不阻断构建。

## 验证范围

项目结构、共享包契约、macOS Debug 和 generic iOS Simulator 编译、worker 能力探测、P1-01…P1-05 命令行物理验证。
P1 不能当作扫描、舒适 PMV、App 切片或定量方案推荐已完成。网格只有粗/中两套，不能声称网格无关。

## 环境处理

系统命令行默认 CommandLineTools；脚本显式设置 DEVELOPER_DIR，不修改全局选择。
Desktop/Documents 的 File Provider 属性可影响测试 bundle 签名，因此脚本默认使用临时构建目录。
Debug 设置 ONLY_ACTIVE_ARCH=YES，保持 App 与本地包架构一致；Release 仍使用默认多架构设置。
