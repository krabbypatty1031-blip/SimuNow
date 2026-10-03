# N1～N4 最终整合审查

2026-10-03。范围为N1～N4全部21个任务/72个验收案例，包括N4的Should任务。N5建议、ComparisonRecord、PDF、消费者分享和发行候选未实施。当前代码审查与最终自动回归通过，实际平台验收仍缺证据，不能据此宣称全部验收完成或绝对无缺陷。

## 已整合的阶段

| 阶段 | 本地整合 | 实现与证据 |
|---|---|---|
| N1 | 3ea5b56，补审7dbacf5 | 独立契约、就绪度、规范化hash、有限任务/缓存、分析附件；[交接](N1-implementation.md) |
| N2 | e2ea5f5 | 非AR几何、相机、点选、P2编辑/撤销、二维回退；[交接](N2-implementation.md) |
| N3 | 40718df | 确定性路径、首次遮挡、关注点、后台预览/取消、定性比较和历史；[交接](N3-implementation.md) |
| N4 | 713e06e→c502e81 | 真实生产功率/Decimal费用/显热/范围及固定比较；191共享Swift+2扩展、39Python、native23/17和两端构建通过；[交接](N4-implementation.md) |

## 根代理的跨阶段修复

| 风险 | 处理 | 验证边界 |
|---|---|---|
| completed大载荷在主线程校验；封装取消后仍可能追加 | 事件结构与数学依据在后台校验；保存校验/封装句柄并传播取消，await后重查generation/identity；旧sequence在重校验前丢弃 | stoppedAnalysisCancelsArtifactWorkAndCannotPersist、lateArtifactCannotMutateAReplacementSession、duplicateInvalidEventCannotFailTheCurrentValidRun；迟到测试实际等待旧订阅结束 |
| 自一致伪功率进入会话/缓存 | Client完成及缓存前、Coordinator保留结果前调用冻结输入的ThermalEstimateEvidenceValidation | 采用1000W×2h、返回自一致500W×2h=1kWh的伪executor/client均应失败；与schema自一致检查分开 |
| 同UUID/同字节的新文档继承旧任务 | 瞬态documentInstanceID，每次读包新建，编辑/天气/分析事务保留；真实binding回调核对实例；新实例清空preview/power/heat会话、撤销和当前比较视图 | documentInstanceSurvivesTransactionsButChangesOnAnotherRead、sidefileAppendPreservesUndoButAnotherDocumentClearsSession |
| 历史解析只查projectID，等待期间附件或文档替换 | 索引/单份加载传播取消；加载结束重查最新binding实例和sidefileRevision，按方法恢复正确协调器；已删方案仅看历史 | latestBindingRejectsHistoryBeforeExternalChangeNotification；真实系统历史操作仍待验 |
| 撤销/重做发布失败，却先改变Store及历史栈 | 两者先走同步文档preflight，拒绝时不弹栈、不更新输入或发布，显示原因 | rejectedUndoAndRedoKeepDocumentAndHistoryConsistent |
| UI刷新反复检查全项目 | Store按真实输入revision/选中scenario复用报告；Document缓存不可变已验证基线，公开project/metadata变化继续完整校验；写包/事务预算门槛保留 | cachedDocumentIntegrityCannotHidePublicMetadataMutation及既有编辑/修复/选中方案回归；没有新GPU/完整App耗时结论 |
| 旧费用/比较worker回写新会话 | 费用父记录加载增加generation、实例/侧文件复核；比较返回前核对实例/侧文件，resetSession清理旧费用/就绪状态 | N4现有取消/新run/保存失败测试及根实例测试；真实UI竞争未验 |
| 表单内容被裁剪，旧准备提示混淆能力 | 房间/门窗/预览配置及N4编辑使用可滚动grouped Form；长假设摘要折叠；高级完整物理输入独立命名，报告空状态反映已实现估算 | 源码/两端构建；UI修复清单029/041/048/053保持待真实复验，不凭编译勾选 |

## 回归记录

当前完整回归命令使用现有锁定Python，无新依赖安装：

```bash
SIMUNOW_PYTHON=Backend/.venv/bin/python SIMUNOW_BUILD_DIR=/private/tmp/SimuNow-Native-Final-Review Scripts/check.sh contracts
SIMUNOW_BUILD_DIR=/private/tmp/SimuNow-Native-Final-Review Scripts/check.sh mac
SIMUNOW_BUILD_DIR=/private/tmp/SimuNow-Native-Final-Review Scripts/check.sh ios
```

最终日志为忽略目录`Artifacts/NativeDelivery/n4-final-review-{contracts,mac,ios}.log`；首轮整合日志`n4-integrated-*`保留用于审查。初次sandbox执行因SwiftPM嵌套sandbox及Xcode服务权限失败，日志另存`*-sandbox.log`；必要开发工具服务已通过自动批准的提权验证重跑。三份最终命令均exit0。完整契约通过201项共享Swift、2项扩展、39项Python、23份真实native记录、17个拒绝变异、2份跨语言项目/快照及28个兼容/错误案例。共享Swift全测264.663秒；该Debug并行测试时间不代表App交互性能。两端日志均BUILD SUCCEEDED。

根新增10项回归。N4整合前4项隔离生命周期测试已通过；首轮全测201项发现旧缓存fixture始终返回1000W（2个缓存断言失败），以及构建期间新增sequence修复导致共享库object早于测试源码（duplicate测试失败）。当前修正fixture采用真实v1积分载荷并增加13次逐次完成断言，没有放宽缓存/数学门槛；源码冻结后两个专项在`n4-final-cache-and-sequence-v2.log`通过（2项、16.120秒）。最终冻结源码的完整契约重跑exit0，201项共享Swift均通过，Mac/iOS构建exit0；本段前述失败和专项均保留日志。代理191项和此前165项仅是对应阶段的历史证据。

## 实际平台证据与未完成项

Mac既有N2/N3真实点选、相机、P2编辑/撤销、薄盒遮挡、三个方案比较、系统导出/退出进程重开已观察。现代iPhone/iPad已启动并显示三维；N4的`n4-ipad-probe-launch.png`/`n4-iphone-probe-launch.png`仅证明几何及估算入口显示，未操作估算卡片。

电脑操作服务曾getApp等待约977秒后返回−10005，本轮只读getState两次超时并重置kernel，最后一次10.972秒；不能用构建、控制器单测或启动截图替代真实输入、VoiceOver和系统文件面板。最低macOS14/iOS17运行环境当前不可用。N4卡片全流程、现代移动端完整编辑/保存、深浅色/大字号/读屏、GPU帧率和App峰值仍未验。

N3 Release典型client p95约75ms，满预算约520ms超过200ms目标；不包含250ms防抖、输入准备/封装/保存，GPU未测。Debug并行全测数据不替代上述App性能证据。当前规则与估算不能推出实测舒适、空间温度、动态降温或年度节省。

用户PitchDeck/PitchAssets和iOS scheme由独立SHA基线保护；自动回归结束时35份均未变。交接前再次核对时33份仍一致，PitchDeck.pptx与PitchAssets/style-guide.json在另一路工作期间更新；根代理未写入这两份，也不纳入本次提交。不得用旧基线覆盖新材料。


## 继续验收的明确步骤

1. 电脑操作服务恢复后，用最终根源码重新构建独立验证身份；现有N4 probe是代理版本，不能直接当根补修版本的界面证据。保留用户真实项目，使用匿名F-A/B/C副本和真实生产client。
2. Mac依次输入/执行完整功率、分价费用、显热清单/能力、两参数范围和冻结比较；补验known0、missing、子集、unknownSHR、重复执行、修改后过期及保存失败。逐项记录V-N4-04/08/10/13/17/19/20，不能仅因自动化通过而勾选。
3. 用系统文件面板保存并退出独立进程，从新进程重开；核对功率/显热历史、费用父run及evaluation、原始input/result字节不变。执行同UUID包替换、等待中的历史加载和完成封装后关闭竞争；确认新会话不继承旧任务。
4. iPhone/iPad完整走创建/编辑、采用预览、相机/点选、估算/比较及系统文件流程；补验横竖屏、深浅色、大字号、完整键盘与VoiceOver单位/状态。最低macOS14/iOS17另需实际运行环境，现代系统强制二维不能替代。
5. 隔离测量最终Release输入准备、client、封装、保存与UI完整耗时，满预算样本单列；取得App自己的GPU帧率/峰值与重复窗口任务释放证据。保留满预算520ms未达目标记录，不用Debug并行全测覆盖它。
6. 将实际证据与对应台账更新后再判断目标是否达成。目前代码/契约工作已经完成，没有已知自动回归失败；上述真实平台缺口阻止宣称全部验收通过。

阻断审计：原目标实施turn `01a0fe06-d147-7762-842d-6b5238569ee7`及范围更新turn `01a1004c-a6e2-7eb3-a849-77e0931bd1bc`均观察到电脑操作服务超时。这里只计两个连续目标turn；工具重试次数不等于目标turn次数。若下一目标续跑仍遇到同一阻断且没有独立工作可推进，按目标规则标记blocked。


本地提交状态：根跨阶段修复与全局计划改动仍在工作区，N4已整合HEAD为c502e81。最终暂存及一次重试均未执行：自动权限审查未在截止时间内完成而拒绝；这不是不安全判定。已提交本地提交确认请求，当前不再重试。代码/契约/两端构建证据保持有效，没有push。


### 用户暂缓实际界面验收（2026-10-03）

用户回复“保留现有代码，暂缓界面验收”。本轮应用清单getState恢复（8.786秒），但独立N4窗口getApp及一次重试都未执行，返回自动权限审查deadline（92.922/93.758秒），与此前native观察超时分开记录。现停止窗口/模拟器输入、读屏及文件面板验收，已有源码不变；未验项目保持缺证据。

N3-06的满预算p95≤200ms是明确目标，旧Release约520ms不能写成达标。native_n3已在独立工作树开始性能复核；收到暂缓请求后仅测量与记录结论，暂不改生产源码、测试逻辑或提交。后续如需优化，先以该口径的可靠证据继续，不通过降范围、改变计时起止或减弱校验制造通过。

本地提交问题尚无回复，根补修和计划仍留工作区；没有Git暂存/提交或push。用户暂缓实际验收不等于验收通过，也不构成N5实施授权。


性能跟进收尾：native_n3未在本轮交接前返回新的有效测量证据；为落实保留现有代码、暂缓验收的请求，根已中止该复核turn，状态为interrupted。没有采用未经报告的数据，也没有新的源码/测试变更或性能达标结论。200ms目标保留未完成，后续恢复时先复核最后可靠Release口径。

验收阶段按用户请求暂停；完整N1～N4目标保持未完成，不削减验收范围。恢复工作需要用户重新启动实际验收，并解决UI工具权限审查deadline/缺失最低系统运行环境；仍需按上面的明确步骤补证据。
