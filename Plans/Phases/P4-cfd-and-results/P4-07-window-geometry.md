# P4-07 窗几何保真：换墙、多窗、出红斑

**Goal:** 窗从「合并成整墙热带」变成「每扇窗按真实墙面、真实宽度、真实高度单独进网格」；沿墙挪窗、换墙、加窗都要让坐姿高度温度场看得见地变化；网格与有效粘度重新标定，让窗边局部暖区（红斑）在质量门禁通过的前提下自然出现。

**现状三条硬事实（本方案要拆掉的）：**

1. `l2_room.py` 把所有窗并成第一扇窗所在墙的**通长带**（高度取第一扇 z0/z1，带通量 = Σ窗W ÷ 带面积）。沿墙挪窗不进网格；换墙只换热带所在墙。
2. `write_openfoam_room.py` 只按高度切层：送/回风永远 x=0 整墙带，窗永远 x=lx 整墙带；y 向（跨度）从不切分，yMin/yMax 是不可切的 `frontAndBack` 整面墙。
3. 混合强：网格 16×12×14、`nu=0.006`（约空气 400 倍有效粘度），坐高座位温差常只有零点几度——即便窗 patch 正确，红斑也需要网格加密 + 降粘度且**重过质量门**。

3D 视口里窗本来就画在真实位置（带框、真实 s0/s1/wall）——本方案让**计算跟上显示**，而不是显示迁就计算。

**Files（改动面）:**

- 投影层：`Backend/src/simunow_worker/models/{l2_room,p1_mapping}.py`（`window` → `windows[]`）；`boundary.py` DTO 形状不变（面积加权平均通量口径保留）
- P1 管线：`test/p1/room_input.py`、`write_openfoam_room.py`（多块网格重写）、`run_room.py`（q_window 口径）；`field_slice.py` / `field_flow.py` 逻辑不动只改披露注释；`test/p1/fixtures/room_p1.json`
- 测试：`Backend/tests/{test_l2_room,test_l2_runner,test_l2_quality,test_p1_mapping}.py`、`test/p1/test_*`
- 钉版：`Fixtures/task/{result-l2,field-slice-l2}.json`（全部 L2 数字重钉 + 迁移说明）；L1 钉版**不动**（`l1_room.py` 单窗求和形状不变，`write_idf.py` 不改）
- Swift：`UserFacingCopy` / `ViewportLegend` / `WorkspaceView` 的「整墙带」窗文案；相关断言
- 文档：`P4-checklist.md`、`status.md`、`decisions.md`（实施时补 ADR 修订 ADR-018 的 L2 半边）

**依赖:** P4-01…P4-06、ADR-018（本方案只修订其 L2 半边；L1「面积求和进单窗」不变）。

**不做:** 送/回风口逐口化（仍 x=0 墙整墙高度带，速度按风量缩放，披露照旧——另开工作包）；门洞、家具盒；湍流模型（仍 laminar + 有效粘度）；L1 投影几何；网格无关性声明。

**约束（全程锁定）:**

- 总窗瓦数守恒：Σ(q_i×A_i) 逐窗进网格，能量门禁对账的是「逐窗 patch 实际注入的 ΣW」
- 质量门禁是唯一裁判：checkMesh ok / 求解收敛 / monitor 稳 / mass_rel<0.01 / energy_rel<0.05，全过才算有效场
- 钉版 L2 数字必然全漂移 → 重钉 + 迁移说明（AGENTS 数据规范），不静默改数
- 窗位置/宽度改动必须改 `input_hash`（P4-01c 口径）
- 不为红斑加人工对比度、不锁色标（已回退）、不把不过门的场当好场

分两个里程碑：**A 几何保真**（确定性，可独立交付）→ **B 场保真**（实验性，质量门禁为裁判，可停在 A）。

---

## P4-07A 几何保真：换墙、多窗（逐窗 patch、任意墙）

### P4-07A-a 房间 JSON 契约：`window` → `windows[]`

- `l2_room.py`：投影改为 `windows = [{wall, s0_m, s1_m, z0_m, z1_m, q_w_m2}]`（墙 ∈ xMin/xMax/yMin/yMax；q 逐窗声明，无通量 → 声明 0.0，不发明）。`window_area_m2`（Σ 面积）与 ΣW 字段保留（L1 对照用）。assumptions：删「all windows merge into one band」「window band spans the full wall」，加「each window enters at its own wall, span and height; total window W = sum over windows」。
- 校验（投影层，中文 reason 走失败事件）：`wall` 必须四墙之一；`0 ≤ s0 < s1 ≤ 所在墙跨度`；`0 ≤ z0 < z1 ≤ 房高`；**同墙重叠窗合并**为一个矩形（q = ΣW/ΣA 面积加权，W 守恒，assumptions 披露「同墙重叠窗已合并」——编辑器允许任意放置，不把用户输入变成失败）；**xMin 墙窗的 z 区间不得与送/回风 z 带相交**（相交 → 拒绝 + reason：进口面优先，窗 W 会被吞掉，不静默丢守恒）。
- `p1_mapping.py` 同步改 `windows[]`（ADR-018 的第四个投影）。
- `room_input.py`：`window_area_m2` 改为「有 `windows` 列表 → Σ 逐窗矩形面积；退回 legacy 单 `window`（L1 房间，无 s0/s1）→ 保持整墙带 span×height（注释写明两形状为何并存）」；新增 `window_total_w(room)` = Σ 逐窗 q×A。
- 测试：`test_l2_room` —— 两窗逐窗 q 各自保留；换墙后 `wall` 字段如实；挪窗（同 ΣW）`input_hash` 变；无通量窗 q=0 声明值；同墙重叠合并后 ΣW 不变；xMin 窗撞送风带 → 拒绝。

### P4-07A-b case writer：三向切分多块网格

`write_openfoam_room.py` 的 block/patch 生成重写（其余字典不动）：

- 切分集合：`cuts_x` = {0, lx} ∪ yMin/yMax 窗的 s0/s1（沿合同 x 轴）；`cuts_h`（高度，foam y）= 现有送/回/各窗 z0/z1；`cuts_s`（跨度，foam z）= {0, span} ∪ xMin/xMax 窗的 s0/s1。
- 顶点改为**完整三维格点阵**（(len_x+1)×(len_h+1)×(len_s+1) 个点，按格点索引引用），块 = 区间笛卡尔积，每块 `hex ... (n_x n_h n_s)`；`_allocate_cells` 推广到三向，薄带每向 ≥2 单元（保 checkMesh）。
- 面归 patch（只看块的 6 个外面是否贴域边界）：
  - x=0 面：z 区间 ⊂ 送风带 → `inlet`；⊂ 回风带 → `outlet`；否则 `walls`（xMin 窗与送/回带不相交已由投影层保证）
  - x=lx 面：(跨度区间, 高度区间) ⊂ 某 xMax 窗矩形 → `windowN`
  - foam z=0 / z=span 面：(x 区间, 高度区间) ⊂ 某 yMin/yMax 窗矩形 → `windowN`
  - 地板/天花板 → `walls`；**`frontAndBack` 名字不再成立，并入 `walls`**（patch 集合变为 inlet / outlet / window0..N-1 / walls）
- `0/U|T|p_rgh|p|alphat` 的 boundaryField 逐 patch 生成：`windowN` 在 U 为 noSlip、T 为 fixedGradient（梯度 = q_i / kappa，逐窗自己的通量）、p_rgh fixedFluxPressure。
- `case_meta.json` 增 `windows[]`（patch 名 ↔ 窗 id、wall、s0/s1、z0/z1、q_w_m2、面积）+ ΣW；旧 `window_q_w_m2` 单值改为 ΣW。
- **回归性质**：单窗、满跨、xMax、高度同旧版 → 网格与旧版同构（块数相同，仅 patch 名 window→window0）。这是重钉复算的第一步。
- 测试（不求解可测）：blockMeshDict 文本断言——两窗不同 s0/s1 → 两个 patch、面只覆盖各自矩形；yMax 窗 → 面落在 foam z=span 平面；Σ窗面积 == 声明；引擎在时跑 blockMesh+checkMesh 冒烟。网格预算：默认目标总数 16×12×14 量级不暴涨。

### P4-07A-c 守恒与质量门禁同口径

- `run_room.py`：`q_window_w` 改 `window_total_w(room)`（Σ 逐窗 q×A）。`quality.py` 公式不动——能量门现在**真正核对逐窗 patch 实际注入的 ΣW**（fixedGradient 逐窗缩放，注入瓦数 = Σ q_i×A_i）。
- 单窗房引擎回归：单窗从通长带变真实矩形（面积变小、逐 m² 通量变大、ΣW 不变）→ 五门禁应全过；`field_flow.py` 种子注释同步（进口仍 x=0 整墙带，不变）。
- 引擎不在时：`run-l2` 照旧诚实失败（OpenFOAM not configured），不编造温度。

### P4-07A-d 挪窗可感知（A 的验收核心）+ 重钉 + 文案

- 引擎敏感性存证（本地 `Artifacts/sensitivity/`，不进库）：同 ΣW、同人数，窗沿墙从 y 低挪到 y 高 → 座位温度向量变化、切片暖区 (x,y) 随窗移动；换到 yMax 墙 → 暖区跟到对应墙；两候选并排对比页可见红斑位置差异。
- 重钉：`Fixtures/task/result-l2.json` + `field-slice-l2.json` 全部 L2 数字重跑重钉；`test_l2_runner` 独立复算断言更新；`test/p1/fixtures/room_p1.json` 改 `windows[]`；迁移说明记入 status/ADR（同 ADR-012 式「对齐前/后」双列）。
- 文案（Swift，`UserFacingCopy` / `ViewportLegend` / `WorkspaceView`）：「窗按实际墙面与宽度进入计算，每扇窗单独进网格；送回风仍按整墙高度带进入计算，速度按风量缩放」。检查器/图例/「计算过程」三处口径一致。

---

## P4-07B 场保真：红斑（实验性，可独立停止）

前置：P4-07A 完成（逐窗 patch 是局部暖区的几何前提）。**质量门禁为唯一裁判，不为红斑放宽任何门。**

### P4-07B-a 网格阶梯

- `nx/n_span/n_height` 16×12×14 → 24×20×18（时间允许再 32×24×20）；复用 `run_room --nx/--n-span/--n-height` CLI 旋钮与 `mesh_study.py` 口径。
- 求解时间预算：App `L2TaskClient` 超时 900 s 内；`l2_runner.run_pipeline` 内部 600 s 需同步上调；`end_time 4000` 迭代不足收敛时可调，记录进 case_meta。

### P4-07B-b 粘度阶梯

- `nu` 0.006 → 0.003 → 0.0015（`l2_room.py` `_assumed` 单点改 + 敏感性循环本地存证）；每档记录：五门禁逐项、座位 ΔT spread、近窗座位 vs 远窗座位温差、求解耗时。
- 有效粘度是湍流代 quantities（laminar 模型不变），assumptions 与 ADR 写明它不是空气分子粘度。

### P4-07B-c 接受标准（硬）

- 只有**全门禁通过**的最低 `nu` 才写入默认；若 0.003 以下全不过 → 停在能过的档，红斑弱就如实披露「混合强，坐高座位温差零点几度」，不硬凑。
- 通过后的验收：坐高切片 stats 的 max 位置落在窗矩形投影附近；挪窗 → 暖区移动；色标自动范围下暖区自然显红（不加人工对比度）。
- 采用新 nu/网格 → assumptions + ADR 记录 + 钉版再重跑；不采用 → 记录阶梯结果止步，A 的成果照常交付。

---

## 风险

1. **低 nu 稳态不收敛**：浮力主导下 `buoyantBoussinesqSimpleFoam` 层流稳态可能物理非稳态 → monitor 门禁会挡；止步不算失败（B 明确可停在 A）。
2. **多块网格面质量**：三向切分后 checkMesh 非正交/偏斜可能变差 → 门禁挡；必要时调 `_allocate_cells` 分配或切分容差（1e-9 去重已有）。
3. **钉版全漂移**：L2 全部数字（座位、切片、quality 项）重钉，L1 不动；忘了重钉会被 `test_l2_runner` 独立复算抓住。
4. **runtime 逼近 900 s**：网格加密 + 低 nu 迭代变慢；超预算就停在粗一档。
5. **窗-风口重叠输入**：xMin 窗撞送/回风带 → 投影层拒绝 + 中文 reason（失败事件如实上报），不静默挪窗或丢守恒。
6. **双形状并存**（`windows[]` vs L1 legacy 单 `window`）：`room_input` 注释钉死各自消费者；`load_room` 同时接受，`input_hash` 覆盖新形状。

## 顺序与验证

A-a → A-b → A-c（引擎回归 + 重钉）→ A-d（敏感性存证 + 文案）→ B（可停）。每步：

```bash
Scripts/check.sh test
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
python3 test/p1/run_room.py            # 引擎在时；五门禁全过才算数
```

共享 JSON 契约（P1 房间）改动同步 schema/测试/迁移说明；Swift 端编译两端（`check.sh mac` / `ios`）+ 显示检查。实施时在 `decisions.md` 补 ADR（修订 ADR-018 L2 半边：逐窗 patch 取代整墙带；记录重叠合并与 xMin 冲突拒绝两条口径）。
