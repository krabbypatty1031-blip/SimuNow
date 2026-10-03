# P2-01 冻结完整房间模型

**Files:**

- Modify: `Packages/SimuKit/Sources/SimuCore/ProjectModels.swift`
- Modify: `Packages/SimuKit/Tests/SimuCoreTests/ContractTests.swift`
- Modify: `Protocols/Schemas/project-draft.schema.json`
- Modify: `Protocols/README.md`
- Create: `Backend/src/simunow_worker/models/__init__.py`
- Create: `Backend/src/simunow_worker/models/project.py`
- Create: `Backend/tests/test_project_model.py`
- Create: `Fixtures/project-draft-v1.json`
- Create: `Fixtures/project-v2-office.json`
- Modify: `Plans/Delivery/status.md`（有测试证据后再写）

**Interfaces:**

- Consumes: P0 `ProjectDraft` v1 身份字段；数据契约中的几何/使用/HVAC
- Produces: schemaVersion 2 的 `ProjectDraft`（仍用此类型名，扩展三个可选分区）；`hasCompletePhysicalModel`
- 不产生：磁盘 `.simunow` 包、向导 UI、P1 solver JSON。P3 再写 adapter

**约束：**

- 设定温度 ≠ 送风温度
- 循环风量/回风口 ≠ 室外新风
- 开口与风口用 `s0`/`s1`（沿墙）+ `z0`/`z1`，不得默认整墙宽
- 送风速度与 `supplyAirflowM3s` 须与补丁面积互校（相对误差默认 5%）
- `PhysicalQuantity` 可带可选 `reference` / `uncertainty`；空字符串视为无出处
- 座位是采样点，人数热源在 occupancy
- v1 JSON 缺分区时不得填默认 6×6×2.8 房间去「凑齐」模型
- envelope / environment 仍为后续可选分区，本补丁不加入

---

### P2-01a v1 不可求解

- [x] 测试：现有 v1 JSON 解码后 `hasCompletePhysicalModel == false`
- [x] 实现该布尔属性；缺 geometry/occupancy/hvac 任一即为 false

### P2-01b v2 Swift round-trip

- [x] 测试：办公室夹具含矩形尺寸、一扇窗、四个座位、分体空调送回风、设定 26°C、送风 16°C、COP、新风
- [x] 编解码后相等；`lengthUnit == "m"`；`coordinateSystem == "rightHandedZUp"`
- [x] 设定与送风温度字段不同

### P2-01c Schema 与 Python

- [x] schema 允许 version 1（无分区）与 version 2（三分区 required）
- [x] Python `parse_project` 对同一 Fixtures JSON 得到相同 has_complete_physical_model

### P2-01d 迁移

- [x] v1 → 解析对象不创建假开口/假空调
- [x] 不得把 v1 标成可提交计算

### P2-01e 记录

- [x] Protocols/README 写明 v1/v2
- [x] status.md 只写测试命令，不写「房间编辑完成」

### P2-01f 墙面跨度与送风量

- [x] `Opening` / `AirTerminal` 含 `s0`/`s1`
- [x] `supplyAirflowM3s` 与速度×面积相对误差默认 5%
- [x] 夹具窗宽 1.5 m，不是整墙

### P2-01g 出处

- [x] 可选 `reference` / `uncertainty`；空白 reference 编码为缺省
- [x] 旧 JSON 无这两键仍能解码
