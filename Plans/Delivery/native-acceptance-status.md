# N1–N5实现与逐项验收台账

启动：2026-10-03。用户最新授权为完整N1→N2→N3→N4顺序实施，各类别由独立Subagent先规划、实现、自审，根代理整合与最终交叉审查。此处仅记录实际证据，不以计划/构建代替运行交互，不宣称绝对无缺陷。N1～N4全部计划项（包括N4及阶段内Should交付）纳入本次目标；N5的案例保留notRun，不用于本次完成门槛。

用户于2026-10-03明确暂缓实际界面验收并保留代码；涉及实际窗口/移动端/VoiceOver的未验项保持缺证据，不继续输入操作。N3满预算性能复核仅测量记录，暂不改生产代码。

## 当前类别

| 类别 | 状态 | 权威位置/证据 |
|---|---|---|
| N1 | 代码已整合；平台验收部分完成 | native_n1代理，97d030d→主分支3ea5b56；[交接](N1-implementation.md)；整合contracts/mac/ios通过，补审7dbacf5 |
| N2 | 代码已整合；平台验收部分完成 | native_n2代理3c9f2e3→e2ea5f5；[交接](N2-implementation.md)；根代理124共享Swift+Extension2/mac/ios通过，Mac编辑闭环与移动端渲染已观察 |
| N3 | 代码已整合；平台/性能部分未验 | f93730f→40718df；165共享Swift+Extension2、39Python、native17/10及两端构建通过；Mac实际闭环，详N3交接 |
| N4 | 代码与最终自动回归通过；平台验收中 | native_n4按规划/实施/自审提交713e06e→c502e81；[交接](N4-implementation.md)；191共享Swift+Extension2、39Python、native23/17及双端构建通过 |
| N5 | 本次不实施 | 用户已将目标改为N1～N4；消费者报告、PDF与发行计划保留待后续授权 |
| 最终审查 | 代码与自动回归通过；实际交互缺证据 | 取消、文档实例替换、历史异步加载、缓存数学依据、撤销/重做及重复校验已补修；10项根回归包含于最终201共享Swift全测，2扩展/39Python/native23与17拒绝反例、双端构建通过；详[最终审查](N1-N4-final-review.md) |

## 验收案例

案例定义见[验收清单](../References/11-native-acceptance-cases.md)。自动/契约/人工子项分别列，不把部分通过写整体通过。status可为notRun/inProgress/pass/fail/notAvailable。

| ID | 状态 | 实际证据/范围 |
|---|---|---|
| V-N1-01 | pass | [N1交接](N1-implementation.md)的01项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-02 | pass | [N1交接](N1-implementation.md)的02项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-03 | pass | [N1交接](N1-implementation.md)的03项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-04 | pass | [N1交接](N1-implementation.md)的04项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-05 | inProgress | 两端最低target构建通过；Mac实际旋转/缩放/重置/无手势选择及材质变化；iPad26.5实际渲染。iPhone/iPad26.5实际渲染；完整交互未验收；14/17运行notAvailable |
| V-N1-06 | pass | [N1交接](N1-implementation.md)的06项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-07 | pass | [N1交接](N1-implementation.md)的07项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-08 | pass | [N1交接](N1-implementation.md)的08项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-09 | pass | [N1交接](N1-implementation.md)的09项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-10 | pass | [N1交接](N1-implementation.md)的10项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-11 | pass | [N1交接](N1-implementation.md)的11项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-12 | pass | [N1交接](N1-implementation.md)的12项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-13 | pass | [N1交接](N1-implementation.md)的13项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-14 | pass | [N1交接](N1-implementation.md)的14项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-15 | pass | [N1交接](N1-implementation.md)的15项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-16 | pass | [N1交接](N1-implementation.md)的16项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-17 | pass | [N1交接](N1-implementation.md)的17项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-18 | pass | [N1交接](N1-implementation.md)的18项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-19 | pass | [N1交接](N1-implementation.md)的19项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-20 | pass | [N1交接](N1-implementation.md)的20项自动/契约证据；Artifacts/N1/contracts.log；主工作区Artifacts/NativeDelivery/n1-integrated-contracts.log通过 |
| V-N1-21 | inProgress | CPU大循环不占MainActor、actor取消及20次coordinator弱引用释放测试通过；N2独立副本20次真实新建/关闭与多窗口已观察，完整计算工作区重复开关纳入本次总审 |
| V-N2-01 | pass | Root n2-integrated-test.log的124共享Swift+Extension2通过；RoomSceneTests三基向量、往返、正尺寸与northAngle隔离 |
| V-N2-02 | pass | Root整合回归通过；非零origin家具center=(2,2.5,1)、符号UUID/示意尺寸与目标adapter |
| V-N2-03 | pass | Root整合回归通过；六面UV/外向winding、Apple handedness、未知开口不生成节点 |
| V-N2-04 | inProgress | wallCells真实缺格/外向厚度/unknown测试通过；Mac实际F-A/F-B门窗/薄盒画面已看见，未知项目人工定位仍待验 |
| V-N2-05 | inProgress | 宽窄fit/有限缩放/presets/focus与hash/undo测试通过；Mac实际点选、drag、wheel、top、focus、reset通过；移动端操作待验 |
| V-N2-06 | inProgress | ID/删除/方案作用域/冻结build输入guard测试通过；Mac三维B点→P2表单X4→4.5→重开确认→undo4已完成；三维选中B删除后对象/样点及旧选择清除，撤销恢复已观察；切方案人工项待验 |
| V-N2-07 | inProgress | Mac完整F-A/F-B实际显示和操作已验；iPhone17Pro/iPadPro13M5 iOS26.5完整房间渲染截图已取得，触摸未验；未请求摄像权限 |
| V-N2-08 | inProgress | 最低14/17 target编译通过，Mac强制二维分支同坐标/对象/方向与编辑入口已实际显示；最低运行时notAvailable |
| V-N2-09 | inProgress | Mac浅/深色已观察、AX对象列表与单位/按钮存在；Mac最大字号无明显放大；iOS大字号/VoiceOver朗读/完整键盘待验 |
| V-N2-10 | inProgress | 单对象diff、20次controller清理与两个controller相机独立测试通过；两个真实窗口输入/显示选择各自保持已观察；20次系统新建/关闭均返回原窗，4/12/20次RSS=116144/120016/120512KiB；非完整泄漏/任务分析 |
| V-N2-11 | inProgress | 场景操作后ProjectPackageIO真实磁盘重开、project/metadata字节及opaque附件保留检查通过；显示性能与系统重开待验 |
| V-N3-01 | pass | N3代理165项回归：中心/边缘/后方解析；单位1。 |
| V-N3-02 | pass | 纯场刚体等变及AABB90°关系等变；不支持OBB。 |
| V-N3-03 | pass | unknown/zero/nonunit、多设备/缺风口及非法几何阻断；全项目Integrity仍保持。 |
| V-N3-04 | pass | 档案/数值/version/seed/hash验证；16/32/64密度不改目标关系。 |
| V-N3-05 | pass | Halton golden、最大UInt32seed、中心首条及确定性预算通过。 |
| V-N3-06 | pass | 0.05m薄盒多step与平行slab通过；Mac实际2D/3D遮挡已观察。 |
| V-N3-07 | pass | 闭边界/角/相切、稳定UUID及全局最小t近邻tie回归通过。 |
| V-N3-08 | pass | 墙内向epsilon、内部源不移及薄盒偏移拒绝通过。 |
| V-N3-09 | pass | 无有效发射拒绝、weak/escaped/length/step预算及取消不保存部分结果；计时样本另列。 |
| V-N3-10 | inProgress | 开口/return/隐藏墙的纯函数回归通过，封闭域能力说明可达；实际开启门窗场景待最终QA。 |
| V-N3-11 | pass | F-A/F-B target golden及Mac实际A/B/C关系与hit对象通过。 |
| V-N3-12 | pass | 纯非法点notEvaluated、生产Integrity阻断、空seat与合法边界marker回归通过，不造点位建议。 |
| V-N3-13 | pass | mixed/空samples位置标记/密度不改标签回归通过。 |
| V-N3-14 | pass | 17份真实Swift native记录含N3生产request/result及10拒绝变异；无m/s/T/PMV字段。 |
| V-N3-15 | pass | 统一overlay只转换一次与display不改hash单测；Mac实际同结果3D/强制2D薄盒截点通过。 |
| V-N3-16 | inProgress | 首版静态合并mesh无ticker、关系列表可达；动画可延期，实际Reduce Motion/VoiceOver纳入本次总审，当前未取得证据。 |
| V-N3-17 | pass | FakeClock20编辑/最新hash、pending取消、驱逐后同hash恢复及N1缓存新身份回归通过。 |
| V-N3-18 | inProgress | 晚事件/错sequence/切候选/删除归属回归通过；同projectID文档实例/侧文件替换、迟到封装及重复序号的根回归通过；实际外部替换操作未验。 |
| V-N3-19 | inProgress | P2同栈配置Undo、共享geometry失效、最新附件合并与预算失败测试通过；Mac导出重开/退出新进程恢复通过，移动端文件操作纳入本次总审，当前未取得证据。 |
| V-N3-20 | inProgress | Release典型client p95约75ms；满预算约520ms超过200目标。新增最多64实际递归路径实体；完整任务/封装分开计时。GPU FPS/App峰值/移动端操作未验，详N3交接。 |
| V-N4-01 | pass | 解析式1000W×120min=2kWh、500/1000W两片=1.5kWh；26项N4测试与真实契约通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-02 | pass | 跨午夜半开拆段=10kWh，固定24h参考口径；N4解析式测试通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-03 | pass | unknown/空缺阻断完整结果、草稿小计/覆盖、重叠/倒序/NaN/负值拒绝，known0有效；单测/契约通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-04 | inProgress | 额定连续显式确认、制冷量不可替代、fraction=.5拒绝的单测通过；真实表单操作未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-05 | pass | 方向不改power hash；basis/来源/时段与范围纳入采用投影，单测通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-06 | pass | 0.1与0.2分价例累计Decimal0.3、逐片精确值及最终格式化已实现，自动化通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-07 | pass | power/tariff边界并集、相接/拆段和空缺拒绝自动化通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-08 | inProgress | 缺价/币种、不同币种、非法费率反例通过，energy与cost独立；真实missing卡片未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-09 | pass | tariff/currency改evaluationHash，固定power不变；独立追加/保留父字节与磁盘重开测试通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-10 | inProgress | 多片小额、明确0、极小非零Decimal支持边界及金额精度契约通过；真实费用详情/读屏未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-11 | pass | UA100W/K×10K=1000W、独立新风增加后2200W；无生产隐藏空气常数。 详[N4交接](N4-implementation.md)。 |
| V-N4-12 | pass | 循环与室外交换分离，人员/设备冻结总显热×有效比例单计，源清单/合计一致性反例通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-13 | inProgress | unknown缺项、明确排除子集、Tin确认和子集禁容量合格自动化通过；真实输入/子集卡片未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-14 | pass | 负Q_signed保留/Qcooling=0；未知SHR不可筛查，能力与负荷范围保守筛查自动化通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-15 | pass | 合法显热不依赖COP/湿度/MRT；独立payload/schema不输出PMV/空间温度/动态降温，契约通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-16 | pass | 两区间四端点+名义，640…1440W；非法范围/漏展开/内部源未支持区间明确拒绝，自动化通过。 详[N4交接](N4-implementation.md)。 |
| V-N4-17 | inProgress | 重叠cannotRank、相关范围/超2要求补配置，自动化通过；真实比较/范围卡片未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-18 | pass | 零基准/方法/version/币种/时段/背景/过期比较边界通过；费用币种不一致独立保留energy比较。 详[N4交接](N4-implementation.md)。 |
| V-N4-19 | inProgress | 生产client/coordinator、固定比较/新runID和角度同功率=0差自动化通过；真实冻结后编辑流程未验。 详[N4交接](N4-implementation.md)。 |
| V-N4-20 | inProgress | 厂家制冷电输入0.60kW及EDF0.2001EUR/kWh来源/日期/适用范围文本核对；合成2h=1.2kWh/0.24012EUR。iPad/iPhone仅launch与几何/入口显示；卡片交互、VoiceOver未验。 详[N4交接](N4-implementation.md)。 |
| V-N5-01 | notRun | 待实现和验证 |
| V-N5-02 | notRun | 待实现和验证 |
| V-N5-03 | notRun | 待实现和验证 |
| V-N5-04 | notRun | 待实现和验证 |
| V-N5-05 | notRun | 待实现和验证 |
| V-N5-06 | notRun | 待实现和验证 |
| V-N5-07 | notRun | 待实现和验证 |
| V-N5-08 | notRun | 待实现和验证 |
| V-N5-09 | notRun | 待实现和验证 |
| V-N5-10 | notRun | 待实现和验证 |
| V-N5-11 | notRun | 待实现和验证 |
| V-N5-12 | notRun | 待实现和验证 |
| V-N5-13 | notRun | 待实现和验证 |
| V-N5-14 | notRun | 待实现和验证 |
| V-N5-15 | notRun | 待实现和验证 |
| V-N5-16 | notRun | 待实现和验证 |
| V-N5-17 | notRun | 待实现和验证 |
| V-N5-18 | notRun | 待实现和验证 |
| V-N5-19 | notRun | 待实现和验证 |
| V-N5-20 | notRun | 待实现和验证 |
