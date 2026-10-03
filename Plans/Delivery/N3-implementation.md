# N3 实现与交接记录

日期：2026-10-03，独立 worktree native-n3，基点 e2ea5f5。仅本记录由 N3 代理维护；总状态/验收台账由根代理维护。

## 执行规划

1. 冻结 genericCone v1 纯值档案与已验证输入投影，保留单矩形房间、单 SingleSplit、单 supply、128 boxes/512 targets/64×128 的明确上限；拒绝 unknown、非法向量与未接受假设。
2. 实现无量纲方向场、UInt64 Halton 确定性截面、墙内向微偏移、闭边界 slab 首次碰撞及完整取消。逐段裁到首 hit，不造绕流/回风/真实风速。
3. 直接从同一场和 source→target 线段给每个关注点关系/规则证据，混合座位汇总保持各样点，不由路径密度推算关系。需要的可选证据字段同步独立 schema 与真实 Swift 导出。
4. 同一不可变结果适配三维/二维 overlay；每条 path 合并三角 mesh，实体数有界。旧几何更新期间拒绝贴新 overlay，显示开关不改输入。
5. 注册生产 executor；每窗协调 250 ms 防抖、取消、当前输入 hash 和历史归属，使用 P2 同一配置 undo 与最新 document binding append；结果驻留载荷有界，已保存历史可 lazy 读取。
6. 接入当前预览/规则清单/三方案定性比较及独立 DEBUG 产品入口。先纯算法/事务单测、契约交叉验证，再两端构建、满预算性能记录。
7. 自审全部 V-N3 反例、守住定性边界与持久化状态，准确交接已验/未验实际平台范围；精确提交 N3 文件，不提交复制 Plans、scheme 或用户 Pitch。

## 文件归属

Simulation/AirflowRules 负责算法/executor；Core/Analysis 负责可选证据 DTO；Visualization 负责合并 mesh 与统一二维投影；Workspace/Analysis、Comparison 与文档绑定负责防抖/配置/保存/历史显示；Apps 只注入真实 client 和 DEBUG 独立入口。不修改 N4 算法、N5 建议/PDF、用户原 App 或 Xcode 状态。

## 实际接口、验证与自审

### 完成范围与公开接入

| 任务 | 已实现代码 | 验证与限制 |
| --- | --- | --- |
| N3-01 | `PreviewProfile`、`RuleDirectionField`、`AirflowPreviewInput`；明确接受 genericCone v1，b0=0.05m、半角12°、范围默认房间对角线；单位向量拒绝修正 | 中心/边缘/后方公式、纯场刚体等变、unsupported/unknown/多设备/缺风口/非法档案及hash变更通过 |
| N3-02 | UInt64 Halton、中心首条、仅墙内向epsilon、闭边界slab、确定性BVH broad phase、全局最小t同容差集合按UUID挑选、截段首次碰撞、完整取消 | 薄0.05m盒、平行/角/相切、恰落房间边界、同t与近邻连锁tie、step1/4/16/128、无有效发射通过；不反射/绕障 |
| N3-03 | 每sample/空samples位置标记直接field+LOS；hitID/hitPosition、RuleID、source/profile、混合计数与notEvaluated理由 | 非法目标纯函数保留notEvaluated；生产入口仍阻断全项目projectIntegrity。合法项目容差内略在预览域外的位置标记可不可评价，不造身体高度；空seat不生成点位建议 |
| N3-04 | `AirflowOverlayDescriptor`；`AirflowPathMeshBuilder`纯后台数组；每path一个合并ModelEntity；同overlay二维路径/遮挡终点；旧几何期间拒绝新overlay | 64×128渲染最多新增64个真实递归Entity；公开mesh入口先校验2…129有限点，空/单点/全重复/非有限拒绝；无需ticker，GPU帧率未验 |
| N3-05 | 真`AirflowPreviewExecutor`注册；每窗`PreviewCoordinator`250ms防抖与取消；同P2 undo的冻结配置草稿；最新文档binding追加；有界历史/lazy载入；三候选定性比较 | 20编辑、pending取消不能复活旧结果、切方案缺配置待采用、当前stage/failure归属、驻留压力及hash复用恢复、packageIssues阻断、配置撤销和保存重开已验 |
| N3-06 | 全部规则反例、真实生产Swift导出、独立Python schema拒绝变异、隔离DEBUG App、满预算/典型生命周期测量与最终自审 | 代码闭环可运行；满预算真实client仍超过200ms目标，GPU约30fps/最低系统/移动端手势文件分享/VoiceOver未验，不能标性能全通过 |

- `LocalAnalysisClient.production(registry:)`当前只注册真实airflowPreview v1。N4添加真正thermal executors；未注册方法仍明确不可用。两平台App `@State`保存一个共享client并显式注入所有DocumentGroup窗口，因此2 running/8 queued是全App的登记预算，窗口coordinator独立。
- `PreviewWorkspaceInput`只冻结现有project/scenario/config与`additionalIssues`；不建立第二套文档、hash或request权威。`AnalysisInputResolver.prepare`返回同一次完整验证的request/readiness；production预览和比较均传入文档包完整性问题。
- `AirflowPreviewConfigurationDraft`冻结打开时project/scenario/配置store，过期拒绝；raw字符串拒绝NaN/无效中间文本。未展示length、segments、strength、source/version等全部保持；配置使用`WorkspaceStore.updateAnalysisConfiguration`同一P2事务/undo。
- 可选向后兼容证据：`PreviewTargetRelation.hitPosition`；`AirflowPreviewPayload.sourcePortID/geometryToleranceMeters/wallSourceOffsetMeters/emissionRejections`；`PreviewEmissionRejection(pathID,reason)`。没有改v2项目/P0/native record版本；独立Schemas与Core资源和生成器同步，未知opaque原数字token和附件保留。
- 显示密度只改采样和对应配置hash，不改目标关系；壁面隐藏/相机/显示路径不改分析输入。始终说明封闭域/无回风吸引；开启门窗和回风的当前状态提示来自最新readiness，缓存载荷只含固定能力边界，避免snapshot更新配旧条件说明。
- `AnalysisCoordinator`最多12份结果、24MiB编码/估计载荷预算、256份会话记录；当前所需结果固定，超额历史按需载入。不是进程RAM硬上限，不删除用户保存文件，不删除比较引用。Client原12份/32MiB缓存仍独立有界。
- 成功、checks、rulePreview依据、当前hash和加入文档/写盘状态分别显示。`.saved`文案是“已加入项目；文档保存负责写盘”，不会把内存追加宣称已落盘。

### 规则与状态回归

测试位于`Packages/SimuKit/Tests/SimuCoreTests/AirflowPreviewTests.swift`；复用N1既有身份/sequence、缓存新run封装、取消唯一终态及opaque往返回归。

| 冻结用例 | 实际证据 |
| --- | --- |
| V-N3-01…04 | `n3CenterEdgeBehindFormula`、`n3PureFieldRigidEquivariance`、`n3UnsupportedZeroNonunitMultipleAndMissingSource`、`n3ProfileVersionsNumbersAndHashDensity` |
| V-N3-05…10 | Halton最大UInt32seed/golden、薄盒多step、闭slab/角/相切、墙epsilon/内部源、恰好边界escaped、拒绝发射完整证据/零有效失败、weak/预算/cancel、开口/return固定能力说明；BVH与线性200段及近邻tie集完全等价 |
| V-N3-11…14 | F-A/F-B target golden、混合样点/空samples标记、非法纯输入notEvaluated及生产门槛分别验证、空seat与合法项目容差marker、真实DTO严格导出/无物理速度温度舒适字段 |
| V-N3-15…16 | 同result二维/三维只转一次；纯mesh后台准备、64path合并Entity、关闭显示/相机无run；静态关系列表完整，后台/关闭停止消费；VoiceOver/Reduce Motion实机未验，不宣称通过 |
| V-N3-17…19 | fake-clock连续20输入只当前hash；旧hash pending取消不复活；旧身份/sequence终态保持N1检查；config undo、共享几何令三候选过期；历史驱逐后当前保留/可恢复；最新document append不load整Store或清undo；包损坏门槛同时用于预览与比较 |
| V-N3-20 | 下表实际性能；F-C冻结yaw0/+30/-30，同P2复制语义保留嵌套对象UUID，仅scenarioID不同，单测无盒相交数量2/0/1。比较按scenario/entityID作用域而不是名字，不给优胜/舒适/节电排名 |

额外自审修复：旧completed阶段不用于待采用候选或pending新输入；stop/cancel清当前hash/readiness/归属。免序列化的公开validate仍检查raw/opaque数字词法，拒绝01/+1/NaN/残缺指数等，保持旧strict boundary；全项目point_bounds/point_in_solid均阻断分析，仅roomView可警告。

### 实际验证记录

硬件Apple M2 Max / Mac14,6 / 12 CPU / 32GiB，macOS27.0(26A428)、Xcode27.0(27A266a)、Swift6.4。部署下限仍macOS14/iOS17，未实际启动这些最低系统。

`Artifacts/N3`是忽略的本地测量/构建日志，不进入Git：

- `final-contracts.log`：39 Python；独立扩展2 tests；共享Swift165 tests passed；v2/P0跨语言2 projects/snapshots/28错误与兼容用例；native17个真实Swift输出（含生产N3request/result）+10拒绝变异+独立字段断言；生成无漂移。锁定pydantic2.13.4、jsonschema4.26.0，使用现有venv，无安装运行依赖。
- `final-mac-build.log`、`final-ios-build.log`：最新生产源码两端BUILD SUCCEEDED。
- `final-probe-mac-build.log`：真实WorkspaceDocumentView/production executor DEBUG独立副本BUILD SUCCEEDED，另目录`/private/tmp/SimuNow-N3-Probe-Final/macOS/Build/Products/Debug/SimuNow.app`，bundle`com.simunow.nativevalidation.n3.final.mac`，不覆盖原正在运行的Probe。
- `final-debug-performance.log`：Debug隔离顺序典型/满预算client测试；`final-release-performance.log`：Release顺序executor/client/典型测量，client与典型通过；首次executor取消计时晚于trace完成曾使该单项断言失败。最小复验`final-release-executor.log`最终通过，5次trace均先完成，以null/unavailable记录缺失的中途样本，不把未取消样本当0或负延迟。下面分别列时间，执行器CPU不能代替client任务或GPU。

根代理真实CUA已回报：Mac F-A相交2/范围外1；加入0.05m F-B后相交1/遮挡1/范围外1，B命中薄盒且二维终点正确；同profile三个候选为1/1/1、0/0/3、1/0/2，各run独立；native导出→import重开→退出进程后再开与手动按需恢复三份run已验；包内input/result/manifest checks passed。NaN明确拒绝，13°采用后Undo恢复12°并更新。新的stage修复副本已由根代理复验：F-A完成后切未采用+30°候选，仅显示待采用，无旧completed/noScenario；根代理也复验13°完成→Undo12°，AX观察当前method checking后当前completed，旧终态隔离。iPad/iPhone独立Probe已安装启动并显示room，DeviceHub操作超时，不能标触摸/文件/分享通过。

### 性能、优化与未达目标

所有满预算都保留64paths×128segments、128boxes、512targets，实际64paths/8067segments。结果wire973185bytes，含request/result/manifest的artifact约1200203bytes。mesh压力测试另用完整8192绘制segments。

优化前真实client曾在Debug并行两测试p50/p95=2808/3176ms、Release1263/1475ms；隔离Release分段：request准备931ms、validate877ms、hash63ms、result编码369ms、artifact1466ms、client1275/1291ms。算法本身优化前线性collision在Debug全测试p50/p95约515/613ms；BVH后曾隔离Debug163/169ms，不能把这些executor数字当整个任务达标。

已完成安全优化：

1. JSON单UTF8输出buffer与无escape字符串解析，保留Foundation排序/escaping和opaque number token；UInt64/负零/opaque原拼写都有byte等价回归；原始数字词法仍验证。
2. schema每scalar不重建关键词Set，UUID直接严格ASCII格式检测仍经UUID解析，number只解析一次；未取消任何断言。
3. readiness复用一次完整ProjectValidator报告，不重复全project encode/selected validate；`ProjectCodec.validate/validateSnapshot`与encode执行相同结构及插件校验，只省未使用的序列化。resolver/hash仍完整检查。
4. artifact复用同次完整验证得到的request bytes；公开request不能凭传入hash跳过验证。结果编码增加可传播取消和遍历取消检查。
5. 文档追加仅在公开project/metadata与构造时已验证值相等、assets未变时复用编码/天气摘要，仍检查完整包预算。公开值或资产变化走完整constructor，有非法public project与超包预算回归。预览request、client CPU、artifact编码和mesh数组都在Task.detached；分析流水线主线程处理状态、最新binding合并和RealityKit资源安装。append测量不包括后续SwiftUI body/布局；现`WorkspaceDocumentView.body`读取`document.integrityReport`仍同步进行项目验证，N5应缓存匹配输入的报告或后台协调，不能把0.1ms追加时间宣称整个UI提交时间。

| 测量环境/口径 | p50 / p95 ms | 补充 |
| --- | --- | --- |
| 最终Debug隔离满预算client（10次，cache禁用） | 1251 / 1269 | request准备953ms、artifact1147ms、append0.197ms；运行中client取消0.109ms |
| 最新Debug完整contracts并发全部测试 | client1627 / 2047，executor220 / 288 | 最终165项全测试并发；另一次合约+多端并行构建client3472/6228ms。CPU竞争明显，不能只选最好的一组 |
| 最终Release隔离满预算client | client495.28 / 519.74 | 包含validate/hash、executor、checks/result codec；不含250ms防抖、request准备、artifact持久化；request305ms、artifact475ms、append0.056ms、client运行中取消19.53ms |
| Debug典型F-A32paths/3targets/无盒（30次） | client155.03 / 161.30 | request9.67/10.10、artifact144.46/160.71、append含MainActor hop0.158/0.204ms |
| Release典型F-A32paths/3targets/无盒（30次） | client69.84 / 75.04 | request5.72/5.93、artifact69.50/72.69、append含MainActor hop0.072/0.097ms；cache禁用 |
| MainActor完整64×128 mesh/entity安装 | 最终全测试32.92ms（高竞争轮次曾64.76ms；较轻负载31–44ms） | 数组事先后台准备；新增64真实递归实体，camera更新不重建。一次提交可能造成帧延迟，不据此推断FPS |

满预算**真实任务p95≤200ms未达到**，约30fps没有有效GPU数据，均保留为性能/发布限制。典型client低于200ms只适用于表列输入与口径，加入request/artifact后的保存全链路不能由client时间代替。当前处理为后台任务/清晰pending与stage/取消、默认32与可选16显示路径/显示开关/二维回退；没有为达标暗改64×128预算、profile版本或golden输入。

取消分别记录登记后立即取消与progress0.1完成input/index后运行约5ms的取消。Release短trace在5次计时器样本均先完成，运行中trace延迟记录null/unavailable；Debug全测试得到真实CancellationError样本0.016ms。提前完成样本单列，不算成功取消或报告延迟。算法取消正确性与client取消唯一终态仍是强断言。N1client完整取消与executor追踪取消分别记录，曾Releaseclient需约357ms才到终态，优化后最近约19.5ms；不承诺硬实时。`getrusage`MaxRSS只是测试进程高水位，不是App峰值或驻留载荷RAM上限，未测真实App满预算峰值。

### N4/N5 接续与边界

N4复用相同resolver/config/hash/client/工件，不另建执行权威；扩充production注册实现，逐方法检查与freshness保持。N5建议必须先检查可评价关注点存在、checks/resultBasis/输入归属，并保留RuleID/假设来源；N3checks通过允许“路径有效但没有关注点”，不是有效点位建议。已保存历史通过NativeArtifactCodec.index/load按需读取，当前打开URL由FileDocument负责，不能actor直接写URL。

N5继续消费者布局、报告/PDF、自动按需恢复历史、移动端真实文件/分享/手势、VoiceOver/动态字号/最低系统、GPU帧率/真实App内存及性能预算取舍；现N3不给舒适/节电/真实换气/降温时间承诺。所有全局status/verification/decisions由根代理整合后更新。
