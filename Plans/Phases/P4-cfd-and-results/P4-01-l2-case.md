# P4-01 模型转几何 / patch / case

**Files:**

- Create: `Packages/SimuKit/Sources/SimuCore/L2RoomMapping.swift`
- Create: `Packages/SimuKit/Tests/SimuCoreTests/L2RoomMappingTests.swift`
- Create: `Backend/src/simunow_worker/models/l2_room.py`
- Create: `Backend/tests/test_l2_room.py`
- Modify: `.gitignore`（跟踪 `test/p1/write_openfoam_room.py`，仍忽略引擎与输出）
- Modify: `Plans/Delivery/status.md`（有测试证据后再写）

**Interfaces:**

- Consumes: `ProjectDraft`、`L2BoundaryMapping`、P1 `write_openfoam_room` / `room_input`
- Produces: `L2MappedRoom`；Python `project_to_l2_room` → P1 形状 JSON；可写 case 目录
- 不产生：OpenFOAM 求解、座位舒适、视口切片、App「开始计算」、`quality.pass`

**约束：**

- 送风温度来自边界/盘管，不是区设定
- 人数 ≠ 座位数；人员显热一次
- `omitted: furniture_boxes` 与 `omitted: envelope_u_value` 必须保留（P1 `load_room` 仍拒绝有家具的第一版）
- 不写 `quality.pass`、不发明 UA / SHGC / 墙温
- 网格与物性 source=`assumed`
- 缺 OpenFOAM 时不得填座位温度 0

---

### P4-01a 草稿 → L2 房间

- [x] 测试：office 映射 size 6×6×2.8；supply T=16；setpoint=26；人数 8 ≠ 4 座
- [x] 测试：assumptions 含 omitted furniture / envelope；无 `quality.pass`
- [x] 测试：`applyOccupantCount(3)` 后 n_people=3，座位数不变
- [x] 测试：`applySupplySpeedMs` 后 u 改变

通过：Swift / Python 同一套键。失败：用设定温度当入口，或把座位数当人数。

### P4-01b 写 case、不求解

- [x] 测试：`write_openfoam_room` 从映射 JSON 写出 `0/U`、`system/blockMeshDict`
- [x] 测试：字典含 inlet 与 outlet；不调用 `buoyantBoussinesqSimpleFoam`

通过：临时目录有 patch。失败：必须有引擎才写得出字典。

### P4-01c 变量变更与缺引擎

- [x] 测试：改送风速度后 `room_input.input_hash` 变
- [x] `run-l2`：无 `SIMUNOW_ENGINES_ROOT` → failed，座位 T omitted；case 已写出。求解器尚未接线

通过：哈希变且不编造 °C。失败：改输入仍复用旧场。
