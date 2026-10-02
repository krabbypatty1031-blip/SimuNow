# P2 执行计划：房间编辑、保存与模板（2026-10-03，development 分支）

展开 `Plans/Phases/P2-room-model-and-editor.md` 的 P2-02…05。P2-01 模型基座已完成，本计划不复述契约，只展开为可执行任务。所有字段、单位、来源与未知值规则以 `Protocols/project-model-v2.md` 为准，本计划不新增字段；若实施中发现必须新增字段，先改 `spec.py` + schema + 迁移，再回到本计划登记。

## 用户操作与页面状态

### 项目入口（无项目时）

- 操作：新建空白项目、从模板新建（办公室 / 教室）、打开 `.simunow` 项目包、从最近列表打开、导入 v1 draft（显式迁移）。
- 状态：无项目显示入口页；最近列表来自本机 UserDefaults（只存安全范围内的 URL 书签与名称，不含房间内容）。
- 异常：文件损坏 / 非 UTF-8 / 重复键 → 显示"无法读取"+具体原因；schemaVersion=1 → 提供"迁移并打开"（迁移只保留身份，几何与场景为空，迁移说明可见）；schemaVersion>2 或不支持单位 → 拒绝并说明需要更新 App。

### 房间向导（P2-02）

步骤：① 名称与空间类型 → ② 房间尺寸（长=depth/Y、宽=width/X、高=height/Z，单位 m，来源可选 preset/user/measured/assumed）→ ③ 朝向（北向角 deg，允许显式未知）→ ④ 门窗（逐个表面添加，局部 U/V 偏移与宽高，带表面示意图）→ ⑤ 围护参数（各面 U 值与外暴露、窗 U/SHGC/遮阳，提供有出处的预设）→ 完成。

- 完成时生成：一个矩形房间（six surfaces）、开口、一个"基准方案"场景；场景内环境物理参数为显式未知（不编造天气）、HVAC/座位为空、通风四项显式未知。
- 校验：每步只提示阻断项；开口越界/重叠即时提示；未完成的参数以"未知（原因）"呈现，不填 0。
- 异常：尺寸非正、开口超出表面 → 阻断完成按钮并定位字段。

### 编辑（P2-03）

- 工作区三栏：左 项目/方案树；中 俯视放置视图（2D）；右 inspector 属性表单。
- 俯视图：矩形房间俯视（X 右、Y 上），盒体家具、座位、空调室内机与送回风口按坐标绘制；点击选中；拖动改变位置（吸附 0.05 m，实时边界约束，不穿墙、不重叠则放行，否则回弹并在校验列表登记问题）。
- 选择身份：selection 为实体 UUID；删除/移动后 selection 更新；无效选择自动清除。
- inspector 按选中实体分派表单：房间（名称/尺寸/朝向）、开口、家具、空调（位置/送风温度/单分体参数）、风口（方向/面积/风量/风速/密度，三值一致性即时提示）、座位（名称/位置/采样点管理）、人员（met/clo/热源/时间表）、设备热源、控制（设定/传感位置/时间表）、通风、环境（代表日/时区/天气引用/温湿度）、费用（币种/电价/报价）。
- 数值表单统一显示单位与来源；已知值可改为"未知"（必须填原因）；来源为 measured/manufacturer/preset 必须有 reference，assumed 必须有 note（契约已有校验，表单在输入时提示而非仅保存时报错）。
- 撤销范围决定：**本阶段不提供结构性撤销/重做**；文本编辑由系统原生处理；防止误删靠删除确认。理由：结构撤销涉及注册表扩展值重建，工作量与风险大于收益；记录于 decisions.md。
- 校验面板：实时显示 `ProjectValidator` 结果，按 projectIntegrity / inputPreparation 分组；点击问题定位到实体；`inputPreparation` 通过前"运行计算"操作不出现。

### 保存与导入（P2-04）

- 项目包：`名称.simunow/`（目录包）内含 `project.json`（ProjectDocument v2，ProjectCodec 编码）。本阶段不创建 runs/、measurements/ 等目录——P3/P6 接入时再扩展包格式并记录。
- 保存：`project.json` 先写临时文件再原子替换（`Data.write(.atomic)` 同目录临时名 + rename）；保存后 dirty 清除；关闭有未保存修改时确认。
- 打开：读取 `project.json` → ProjectCodec 解码 → `ProjectValidator` 全量校验 → 载入；损坏/版本见入口异常处理。
- 一致性验收：编辑后关闭重开，解码结果与内存值相等（Codable Equatable 全链路）。
- 保存内容不含本机绝对路径（天气引用为包内相对路径，本阶段仅记录引用不复制文件，P3 接入天气时处理）。

### 模板（P2-05）

- 两个代码内置模板：`office`（5×4×2.8 m，一扇窗一扇门，4 工位 + 人员 + 一台分体空调）与 `classroom`（8×6×3.2 m，两窗一门，12 座位网格 + 人员 + 一台分体空调）。
- 模板参数来源策略：几何/met/clo/人均热源/U 值/SHGC 标记 `preset`，reference 写明工程手册口径与"现场核实"提示；环境与天气显式未知；费用为空（不表示免费）。
- 模板 = 生成 ProjectDocument 的纯 Swift 函数（SimuCore 或 SimuWorkspace 内，可单测）；基准方案即模板自带场景；复制方案 = 深拷贝场景 + 新 UUID（座位/设备 ID 保留以表达同一对象）。
- 每个模板的未知项与假设在"假设列表"页可查看（收集全部 unknown reason + assumed note）。

## 输入输出与数据流

- 编辑态：`WorkspaceStore.project: ProjectDocument`（值语义，编辑即替换子值）。
- 保存边界：唯一出口 `ProjectCodec.encode`；唯一入口 `ProjectCodec.decode` / `ProjectMigrator.migrate`。
- 选择/校验状态不写入项目文件；`ScenarioInputSnapshot` 仍由 `ScenarioSnapshotBuilder` 生成（P3 再加哈希）。

## 模块与文件

| 文件 | 责任 |
|---|---|
| `SimuCore/Project/ProjectPackage.swift` | 纯包模型：`[相对路径: Data]` 编解码、原子写读、损坏分类；无 UI |
| `SimuWorkspace/ProjectSession.swift` | @MainActor：当前项目、dirty、selection、recents、打开/保存/新建/模板操作 |
| `SimuWorkspace/Home/HomeView.swift` | 入口页（最近/模板/打开/导入） |
| `SimuWorkspace/Wizard/RoomWizardView.swift` | 五步向导，产出 ProjectDocument |
| `SimuWorkspace/Editing/TopDownRoomView.swift` | 俯视放置与选择 |
| `SimuWorkspace/Editing/InspectorView.swift` 及分派表单 | 属性编辑 |
| `SimuWorkspace/Editing/ValidationIssueListView.swift` | 校验列表与定位 |
| `SimuWorkspace/Editing/AssumptionsView.swift` | 假设/未知列表 |
| `SimuCore/Project/Templates.swift` | office/classroom 模板生成器（纯函数） |
| `Apps/*` | WindowGroup 挂载 Home/Workspace，文件面板适配 |

测试：`SimuCoreTests` 增加包 round-trip、原子写损坏恢复、模板校验通过性、模板快照一致性；`SimuExtensionTests` 不动。UI 逻辑（选择更新、wizard 产出可校验）放 `ProjectSession` 层以非 UI 测试覆盖。

## 实施顺序与验收

1. P2-04 包与 session（先能落盘）→ 2. P2-02 向导 → 3. P2-03 俯视+inspector → 4. P2-05 模板 → 5. 验收。
- 每步：`Scripts/check.sh test` + `mac`/`ios` 编译；包逻辑新增单测先行。
- 阶段验收：`check.sh all` 通过；手动运行 Mac App 完成 建模板项目 → 编辑 → 保存 → 重开一致 → 校验列表可见 的演示路径并截图记录到 verification.md；iOS 编译通过 + 导航可达。
- 降级：拖拽冲突复杂时保留数值编辑为主（计划允许）；3D 手柄不在本阶段。
