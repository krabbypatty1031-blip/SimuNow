# P1 可验收清单

> 给执行者：按 `P1-01` → `P1-05` 顺序；同层字母可在依赖满足后并行。勾选后把 run 目录与命令写入 `Plans/Delivery/status.md`。

**Goal:** 命令行从同一份房间输入得到可复算的 U/T 场、冷负荷和座位样本。

**已有、不得再当 P1 完成证据：** `test/engines` 里 EnergyPlus 25.2.0 与 `simunow/openfoam:2512` 仅证明二进制能启动；Python 方腔 Nu 不能代替 OpenFOAM 基准。

**锁定（P1 全程沿用）：**

- OpenFOAM：ESI `opencfd/openfoam-run:2512`，`linux/arm64`，求解器 `buoyantBoussinesqSimpleFoam`，层流起点（P1-02 射流再决定是否 RAS）
- EnergyPlus：`25.2.0-cf7368216c` Darwin arm64，天气 `test/engines/weather/CHN_Hong.Kong.SAR.450070_CityUHK.epw`
- 入口：`test/p1/` 脚本；`Backend` doctor 只探测，不在启动时安装
- 禁止硬编码开发者 Desktop 路径；引擎根目录用环境变量 `SIMUNOW_ENGINES_ROOT`
- 工程门槛：送回风质量误差 &lt; 1%、能量误差 &lt; 5%（待校准，非法定）
- 三网格、现场、舒适 PMV、App 显示：本阶段不做

## P1-01 运行时

- [x] P1-01a 锁定 OpenFOAM 镜像、平台、求解器名单
- [x] P1-01b 锁定 EnergyPlus 版本与 EPW 哈希
- [x] P1-01c 写出 `runtime_manifest.json`
- [x] P1-01d `doctor` 读取 manifest，缺引擎报修复路径
- [x] P1-01e 记录一次峰值内存与 CPU 架构

## P1-02 基准

- [x] P1-02a OpenFOAM 浮力基准 vs 文献
- [x] P1-02b 写明「自然对流 ≠ 送风射流」
- [x] P1-02c 室内非等温射流公开算例
- [x] P1-02d 误差表（值、文献、来源 URL/DOI、本 run 路径）

## P1-03 房间管线

- [x] P1-03a 冻结输入 JSON 与坐标/重力约定
- [x] P1-03b JSON → OpenFOAM v2512 case
- [x] P1-03c `blockMesh` + `checkMesh` 门禁
- [x] P1-03d 求解至监测点稳定
- [x] P1-03e 切片 + 座位采样（点在流体域）
- [x] P1-03f 质量/能量守恒报告
- [x] P1-03g 同输入跑两次，input_hash 一致
- [x] P1-03h 一键脚本退出码 0 当且仅当质量通过

## P1-04 EnergyPlus

- [x] P1-04a 同一房间 JSON 生成 25.2 IDF（含 IdealLoads 连接对象）
- [x] P1-04b 代表日跑通，单位为 W 与 °C
- [x] P1-04c 标为等效 Ideal Loads，电耗 = 冷量 / COP
- [x] P1-04d 导出给 L2 的面温度或热流，且每面只选一种 BC
- [x] P1-04e L1 内部得热与 L2 热源口径对照表

## P1-05 网格与性能

- [x] P1-05a 粗网格：时间、RSS、质量、能量
- [x] P1-05b 中网格：同上
- [x] P1-05c 座位指标粗/中差（低速用绝对误差）
- [x] P1-05d 写出「比赛可用规模」一行结论
- [x] P1-05e 明确三网格/现场为后续，不在本文件验收

## 阶段完成门

同时满足才可在 `status.md` 写「P1 物理验证通过」：

1. P1-01c/d 的 doctor 对 L1/L2 不再是无依据的 `not_configured`
2. P1-02d 至少一行公开浮力基准 + 一行射流基准
3. P1-03h 房间脚本质量通过且可复算
4. P1-04b 代表日 `EnergyPlus Completed Successfully`，无假年度节能
5. P1-05d 有粗/中网格耗时与内存

L2 若在 12h 内不能稳定：勾选降级记录（无逐点结论），不得用动画或 Python 2D 场冒充 L2。
