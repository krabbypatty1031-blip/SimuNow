# N3：Swift本地气流规则预览

版本：详细执行稿v1，2026-10-03。状态：N3-01…06代码已精确整合为40718df，已接入真实production executor；主工作区完整契约与两端构建通过，详[N3交接](../Delivery/N3-implementation.md)和验收台账。前置N1-01…05已提供代码接口，N2已整合显示；实际平台未验项继续台账追踪。

## 目标与支持范围

首期一个矩形房间、最多128个盒体家具、单台SingleSplit、一个明确supply、最多512个关注点，静态风向。生成无量纲方向/假设扩散、有限路径、首次遮挡和关注点几何关系。纯向量场公式可做任意刚体变换测试；含房间/盒体碰撞的整体测试仅采用保持AABB轴对齐的变换（如90°轴旋转/平移），不能为测等变偷偷接入未支持的OBB。所有数值档案属于内部展示假设；不生成m/s、温度、压力、PMV或真实换气结果。

执行时使用[共用契约](../References/10-ai-execution-guide.md)、[验收案例](../References/11-native-acceptance-cases.md)与[方法规格](../References/07-native-method-spec.md)。若算法数值需要变化，改profile/method版本、golden样例和失效策略，不能只调画面后继续复用旧结果。

## 任务与职责

| ID | 依赖 | 主文件/输出 |
|---|---|---|
| N3-01 | N1-03/04 | PreviewProfile、规则场与source解析 |
| N3-02 | N3-01 | PathTracer、SegmentIntersection、termination |
| N3-03 | N3-01/02 | TargetAssessment与RuleEvidence |
| N3-04 | N2、N3-02/03 | 纯overlay描述与RealityKit/二维路径 |
| N3-05 | N1-05、N3-01…04 | preview executor、协调器、防抖和当前结果 |
| N3-06 | N3-01…05 | 规则反例、三方案与性能验收 |

算法放Simulation/AirflowRules；路径显示放Visualization；项目修改继续P2事务。每次交接包含profile版本、DTO、样例ID与结果；不要复制另一套AirflowDirection/CoordinateTransform。

## N3-01：版本化档案与无量纲方向场

**输入**：合法room bounds、supply的位置/方向、显式接受的PreviewProfile。**输出**：可查询RuleFieldSample(direction,pathStrength)、解析假设、unsupported列表。

**位置**：PreviewProfile.swift、AirflowPreviewInput.swift、RuleDirectionField.swift；风向表单复用[AirflowDirection](../../Packages/SimuKit/Sources/SimuVisualization/RoomPlan/PlanProjection.swift)，算法本身用Core纯向量，不反向依赖Visualization。

执行步骤：

- [ ] registry解析room/box/device，检查单房间/单设备/单supply；ports为空需用户补等效风口，不能从机身位置猜出。
- [ ] 方向需通过已有单位向量校验，算法仅为浮点误差再次归一化，不用归一化掩盖导入错误。未知/零向量不得改成朝房间中心。墙面源必须对所有所在边界面朝内（外法线dot(d)<0且超出容差）；切向/朝外源需修复，内部源可朝任意合法方向。
- [ ] 初始内部profile `simunow.preview.genericCone` version1：b0=0.05m、halfAngle=12°、L=room对角线；这些是“展示扩散假设”，不是设备射程/实测风口尺寸。
- [ ] 初次展示说明并让用户明确采用档案；保存id/version/实际数值/source.kind=assumed。允许用户调整展示宽度/角度，不能回写未知风口面积/风量。
- [ ] 建正交基：选与d最不平行的正轴作helper，固定tie顺序X→Y→Z；e1=normalize(cross(d,helper))、e2=cross(d,e1)。
- [ ] 对p：s=dot(p-o,d)，rvec=(p-o)-s*d；b(s)=b0+tan(halfAngle)*s；q=length(rvec)/b(s)。仅0≤s≤L、q≤1且在流体域时有效。
- [ ] 无量纲direction=normalize(d+k*rvec/b(s))，k=tan(halfAngle)；中心轴退化为d。strength=max(0,1-q²)/(1+s/L)²，单位1。它们是规则形状，不是空气速度。
- [ ] 风档没有设备映射时UI使用“预览密度”，默认不改变物理方向、扩散或功率；低/中/高显示样本16/32/64仅供图层细节。设定温度不改变规则场。

**检查**：有限数、b0>0、halfAngle在1…45°（内部允许范围）、L>0且≤diag；profile.maxPaths≤64、maxSegments≤128。资源/范围超限返回问题，不暗中截断配置。

**验证/完成**：V-N3-01…04。中心轴、范围边缘、纯场公式的刚体等变、origin与config变化、invalid profile、unknown不能升级physical basis。输出只含direction/unitless strength及假设。

## N3-02：确定性路径与段碰撞

**输入**：N3-01场、已验证盒体/房间域、seed、路径预算。**输出**：PathRecord(pathID,points,strengths,terminationReason,hitObjectID)和采样摘要。

**位置**：PathTracer.swift、SegmentIntersection.swift、PreviewSampling.swift。复用GeometryBounds读取数据；不扩展Core GeometryPayload来强迫未知几何支持算法。

执行步骤：

- [ ] 固定seed UInt32默认1；第一条中心路径必有。其他路径使用Halton(base2/base3)确定性样本，中心pathID=0，其他i=1…(maxPaths-1)采用UInt64(i)+UInt64(seed)避免UInt32溢出；r0=b0*sqrt(u)、phi=2πv；不调用系统随机源。
- [ ] 发射点在等效截面o+r0*(cosphi*e1+sinphi*e2)；域外/家具内发射点跳过并记录原因/数量。没有任何有效点则失败，不能返回空成功。
- [ ] 在已确认墙面上的中心风口沿内向d偏移epsilon=clamp(diag*1e-7,1e-6,1e-4)m；内部合法起点不移动。检查偏移后未跨入薄家具，源点不以巨大epsilon逃过碰撞。
- [ ] 以轴向步长L/maxSegments步进；按场方向调整实际步长，保证dot(delta,d)>0。每步检查取消、强度阈值0.01、最大128段/64路径。
- [ ] 用slab方法求segment-AABB的tEnter/tExit∈[0,1]；平行轴单独处理，不除0。对room取离开域交点，对boxes取最早进入点。
- [ ] 碰撞盒采用闭边界，触到面/棱/角也视为hit；slab的边界容差与源epsilon分别记录，不能用epsilon放宽穿透。选择最早hit；相同t在数值容差内以稳定objectID排序。最后一个点裁到碰撞位置，记录hit/escaped/weak/lengthLimit/stepLimit/cancelled，不继续反射或绕障。
- [ ] 所有路径坐标保留domain米制，输出不可变有限数组；点/段数量和result bytes均受预算。
- [ ] 开启门窗不做跨开口计算：预览域仍封闭，警告“跨开口气流未模拟”。不能显示门外路径或把回风画成吸引点。

**验证/完成**：V-N3-05…10。0.05m薄家具、平行轴、corner/tangent、实体起点、wall source、不同步长均不能穿透；同seed同环境复现。有效路径为0须解释，不当无风；取消不保存部分轨迹为成功结果。

## N3-03：关注点关系与可追溯规则

**输入**：supply、同一profile、家具和关注点；不从粒子位置统计。**输出**：PointAssessment、SeatAssessment汇总、RuleID/version和证据。

**位置**：AirflowTargetAssessment.swift、PreviewRuleEvidence.swift；DTO归Core/Analysis。

执行步骤：

- [ ] 每个seat.samples作为独立关注点；samples为空时可用seat.position作为“座位位置标记”，注明非身体/呼吸高度，不生成默认1.1m采样点。
- [ ] 验证点在流体域；点无效/类型不支持返回notEvaluated(reason)，不可按0强度或outside统计。
- [ ] 在profile前向范围/横向范围内才做line-of-sight；source→target的线段若有首次家具hit，则occluded并保留hit UUID/位置。
- [ ] 范围外返回outsideAssumedPath；范围内无遮挡返回intersectsAssumedPath；zero/unknown条件返回notEvaluated。规则标签不随显示路径密度改变。
- [ ] 多点seat汇总保留各sample状态：全部一致显示对应关系；混合显示mixed并列数量，任何不可评价单列，不压成一个舒适分。
- [ ] relationCount只标“几何关系数量”；不计算舒适达标比例或满意率。范围外的文字为“未在此假设路径范围内”，不称为“无风/安全”。
- [ ] 保存RuleID，例如preview.pathIntersection.v1、preview.occlusion.v1、preview.unsupported.v1，与run/profile/source/target和理由一起输出。

**验证/完成**：V-N3-11…14。前/后/外三个golden点、混合样点、零采样点、未知点与密度切换。建议生成留N5，N3只输出可解释关系，字段里不放PMV或物理风速。

## N3-04：静态图层与可选动画

**输入**：N3路径/关系的固定result，N2 scene与当前hash。**输出**：3D和二维可显示的OverlayDescriptor、静态路径/箭头/关注点文字。

**位置**：Visualization/RoomScene/AirflowOverlayDescriptor.swift、RealityKit/AirflowPathRenderer.swift、RoomPlan/PlanAirflowOverlay.swift。

执行步骤：

- [ ] 先做静态路径/方向与遮挡端点；背景scene无需重建。Overlay带runID/inputHash/basis/profile版本，过期图层可被明确标记。
- [ ] 使用合并mesh/有限路径实体，避免8192段各一个动态Entity；从domain转换一次，不能路径已转Apple又被父root重复旋转。
- [ ] 墙/家具首次碰撞处结束，overlay不能因为显示隐藏墙而穿过去；unknown/未模拟区域使用中性文字。
- [ ] 关注点状态颜色附文字/图标，列表详情包含profile/RuleID/遮挡对象；色标若显示strength，只标单位1/展示强度。
- [ ] 可选动画沿固定路径播放展示时钟，与算法run生命周期分开；停用时静态信息完整，不使用ParticleEmitter生成新规则路径。
- [ ] Reduce Motion、后台、离页/关窗停止ticker；无需每帧刷新WorkspaceStore或重算场。
- [ ] 14/17二维使用同OverlayDescriptor投影；逐点对照三维，不另造二维规则。

**验证/完成**：V-N3-15/16、V-N2-08/10。改相机无新run；图层可关闭再恢复；不出现T/PMV/m/s图例；只读屏仍能获取全部关系。

## N3-05：工作区防抖、取消与候选归属

**位置**：Simulation/AirflowRules/AirflowPreviewExecutor.swift、Workspace/Analysis/PreviewCoordinator.swift、Workspace/Comparison/PreviewComparisonView.swift。

执行步骤：

- [ ] 把N3纯函数注册为真正executor，N1生产client才开放airflowPreview；故意失败/未注册client保持明确错误。
- [ ] 输入编辑先经P2完整值事务；风向使用现有AirflowDirection.unit，preview config独立文档事务；相机/选择不触发分析。
- [ ] 用户已启用预览后，相关inputHash变化防抖250ms；FakeClock可控，取消旧Task+事件消费，保持旧结果但标“待更新”。
- [ ] submit前再捕获当前snapshot/config/hash；接收事件核对runID、scenarioID、sequence；完成时重比当前inputHash。
- [ ] 晚完成run归历史，不写当前overlay；切方案/undo/外部文档更新同样检查。旧请求不能把已删除方案重建回来。
- [ ] 基准/候选定性比较使用相同profile/version，结果各自归属。P2共享geometry：移动家具会使所有方案相应预览过期，UI须说明。
- [ ] 当前hash再次等于已完成输入可使用缓存并包成新run；不复用旧snapshotHash假装是新证据。
- [ ] 保存由文档层负责；计算成功但超预算不能显示“已保存”。手动重试与取消可操作，不能绑定空closure。

**验证/完成**：V-N3-17…20、V-N1-15/19、V-N5-03。连续20次编辑只展示最新hash；角度变化不触发powerEstimate错误失效；配置撤销后分析对应恢复输入。N3-05提供配置事务接入，N5-01完成其完整UI/undo验收，不另建临时撤销栈。

## N3-06：规则、集成与性能冻结

- [ ] 跑V-N3全部解析/反例，不以截图替代碰撞测试；固定几何/profile/seed golden输出。
- [ ] 64×128路径、128boxes、512targets下测p50/p95/峰值/取消延迟；目标任务p95≤200ms、不含250ms防抖，约30fps展示。目标未达先调整显示/预算，并升配置版本。
- [ ] 在受控离线环境做F-A基准→改角度两个候选→看关系→保存关闭重开；来源假设可达。先沿用N1 artifact接口验收最小保存链路，N5-03再补完整外部更新/iOS导出操作；未做部分记录待验，不形成任务实现的循环依赖。
- [ ] Mac/iPhone/iPad与旧系统回退实际操作，低动态效果和VoiceOver；有平台缺项保持未验证。
- [ ] test、相关native契约、mac/ios；如果共享Core字段变化再contracts。
- [ ] 自审无m/s/T/回风清除污染物/降温时间/舒适/节能承诺，source和RuleID未遗漏。

**阶段完成**：实际Swift规则run接入两种renderer，输入变更/历史/保存状态正确，N5能够仅消费结果生成建议。动画、绕流、浮力、贴壁、多设备和物理网格可延期，不用视觉“补出”未模拟流动。
