# P1-02 公开基准

**Files:**

- Create: `test/p1/benchmarks/cavity_ra1e4/`（OpenFOAM case）
- Create: `test/p1/benchmarks/jet_nonisothermal/`（OpenFOAM case）
- Create: `test/p1/run_benchmarks.py`
- Evidence: `test/outputs/p1_bench/bench_report.json`
- 禁止：把 `test/outputs/p0_latest.json` 的 Python Nu 直接写成 OpenFOAM 已验证

**Interfaces:**

- Consumes: P1-01 锁定的镜像与求解器
- Produces: `bench_report.json`：每个算例的文献值、计算值、相对误差、文献引用、适用范围一句话

文献（P1 必须写进报告，不得口头）：

- 浮力：de Vahl Davis, G. (1983). Natural convection of air in a square cavity. *Int. J. Numer. Methods Fluids*. Ra=10⁴ 时 Nu≈2.243（与现有 `test/fixtures/cavity_ra1e4.json` 一致）
- 射流：报告中必须给出**具体公开算例名称 + 可核对出处**（例如 IEA Annex 20 2D 槽缝送风，或 Nielsen 室内空气试验的可复现子集）。选定后把名称写进 `bench_report.json` 的 `jet.citation`，未选定不算过关

---

### P1-02a OpenFOAM 浮力基准

- [x] 用锁定镜像跑方腔/热腔，得到壁面 Nusselt 或与文献对应的中心剖面
- [x] 网格、Ra、Pr、边界写入 run 目录，可复算
- [x] 相对误差写入报告；阈值先用与 Python P0 相同的 18% 仅作「求解器没装反」门，真正采用的误差以实测填写，不得预先填 2.3%

```bash
# 示意：以 test/p1 脚本为准
test/.venv/bin/python test/p1/run_benchmarks.py --only cavity
```

通过：`bench_report.json` 中 `cavity.engine` 为 `openfoam-v2512`，且有 `nusselt` 与 `reference_nusselt`。失败：只引用 Python 2D 结果。

### P1-02b 适用范围声明

- [x] 在报告 `notes` 写死：本条只证明浮力与能量扩散离散，**不能**证明送风射流、短路或座位分层
- [x] `status.md` 若提前引用 P1-02，必须带上这句话

通过：报告里有该句。失败：用方腔 Nu 宣传「房间 CFD 已校准」。

### P1-02c 非等温射流

- [x] 独立 case：有送风温差、可识别射流轴线
- [x] 至少对比文献或公开数据中的**一条**轴线速度或温度衰减
- [x] 湍流模型若从层流改为 RAS，记录模型名与近壁处理；与 P1-03 房间 case 不一致时必须在报告写「房间仍用某某模型，射流验证用某某，不能混用误差」

通过：`jet.pass` 为布尔值，附监测点定义。失败：用 `hotRoom` 或方腔冒充射流。

### P1-02d 误差表

`bench_report.json` 至少：

```json
{
  "cavity": {
    "citation": "de Vahl Davis 1983",
    "quantity": "mean_nusselt",
    "reference": 2.243,
    "computed": null,
    "relative_error": null,
    "run_dir": null,
    "scope": "buoyancy_diffusion_only"
  },
  "jet": {
    "citation": null,
    "quantity": null,
    "reference": null,
    "computed": null,
    "relative_error": null,
    "run_dir": null,
    "scope": "supply_jet"
  }
}
```

通过：两行 `computed` 均非 null，citation 可核对。失败：空表或编造误差。
