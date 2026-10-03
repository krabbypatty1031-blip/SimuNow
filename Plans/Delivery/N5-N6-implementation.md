# N5/N6 实现与验收交接

2026-10-03；工作分支 `paco-development`；起点 `eda5d5c`。用户本轮明确授权 N5 与 N6，覆盖之前仅实施 N1～N4 的范围限制。本轮单 Agent 实现；用户后续明确授权将本工作区改动提交、推送至 `paco-development`，并通过 PR 整合 `paco-ui-repairs`。正式发布未执行，Apple 平台待验项仍保留。

## 已接入的闭环

家庭/办公室/教室模板 → 房间、风口、方向、关注位置 → 明确采用展示档案 → 真实本地规则 → 每采样点条件建议 → 基准与一至两个候选 → 固定比较保存 → 原生文档重开恢复 → 匿名文字、JSON、原生分页 PDF 预览与系统分享。高级功率/费用/显热表单保留，中文解释口径，不作为看风向的门槛。

- 复制方案按明确原方案复制分析配置，不借旧 run；项目、配置、基准仍为一个 undo 事务。房间/家具仍由所有方案共享。
- 固定比较包含 run/input/result/evaluation 引用和 `bodyHash`。后台检查原父文件及结论；写入时核对最新文档父文件，原子追加，损坏引用不能变成有效比较。
- 重开有界恢复所选方案每方法一个匹配运行，以及第一份有效比较所需父运行；当前费用按固定父电量及当前评价哈希恢复。每页最多检查 12 份比较，比较与数据集均可分页；不重写历史快照。
- 报告使用冻结证据，不重新计算路径、指标、费用或推荐；来源采用精确公共引用白名单，自由文本、姓名、几何、照片和私有路径移除。源 `inputHash` 保留，匿名内容有独立 `exportHash`。PDF 失败时仍允许分享文字和 JSON。
- 分享采用内存 `DataRepresentation`、系统 `ShareLink`、文档导出，不在打开的项目旁创建临时文件。

## 任务状态

“代码实现”不等于 SDK 编译、平台操作或物理验证通过。

| 任务 | 代码与自动检查 | 尚需取得的证据 |
|---|---|---|
| N5-01 日常入口/家庭模板/统一撤销 | 已实现；家庭最小规则输入值层通过；复制来源与 undo 平台测试已添加 | Mac/iPad/iPhone 布局、统一撤销平台测试运行 |
| N5-02 条件建议/三个方案 | 已实现；过期拒绝、逐点身份、三方案和哈希篡改测试通过；独立相机值同步，旧系统二维图 | 两端拖动同步、读屏、两个窗口相机隔离 |
| N5-03 保存/重开/损坏隔离 | 代码实现；文档重开、损坏父记录、匿名附件、测量碰撞平台回归已添加 | Apple FileDocument 测试、Mac 真正关闭重开、iOS 系统导出再开、多窗口与存盘失败 |
| N5-04 文字/JSON/PDF 分享 | 冻结、匿名、独立 hash 及 JSON 契约通过；CoreText/CoreGraphics 分页 PDF 代码实现 | Apple PDF 分支编译、实际渲染逐页看中文/长行/页界，两端分享/取消 |
| N5-05 离线/可访问性/试用 | 自动回归及可执行手工脚本已准备；启动不注入网络/worker | 核心现代两端 E2E、VoiceOver、大字号、深浅色、Reduce Motion、最低系统、两端使用者试用均 notAvailable |
| N5-06 发布候选/资源 | 原创图标、常用中英文字符串、隐私清单、0.2.0(2)、保持 scheme 的生成器及归档脚本已实现 | Apple 资源编译、签名证书、安装/升级/默认文档类型、正式许可确认；未产出可安装包 |
| N6-01 本地测量 | CSV/手动、SI 转换、显式时区、仪表/门窗/质量/分组、本地文件及匿名导出已实现并通过纯值检查 | 两端文件权限/导入/分享；现场仪表数据质量 |
| N6-02 有限射流 | 实测出口依据、参数拟合、独立留出、误差/范围、失败证据及原数据复核模型已实现 | 无独立真实房间数据；消费者定量启用 no-go |
| N6-03 动态 RC/CO₂ | 单房间平均、显式热容量/UA/室外交换与分段源项；解析/守恒/输出步长测试通过 | 真实数据/控制策略未验；不升级逐点预测，产品启用 no-go |
| N6-04 原生网格 | CPU 2D MAC 投影、封闭边界/障碍 mask、热扩散/上风通量/浮力、CFL 拒绝及分辨率基准已实现 | 真机内存/耗时、独立物理基准与 3D/HVAC 边界未验；仍为研究 no-go |
| N6-05 扫描/手动回退 | 主动授权 RoomPlan、支持性检测/错误重试、集中坐标变换、用户确认矩形近似和本地原始 JSON；纯转换测试通过 | Apple delegate 编译、LiDAR 真扫描/无权限回退；设备铭牌仅使用现有人工来源表单 |
| N6-06 专业可选复核 | 明确每次授权的 HTTPS/认证适配、禁重定向、版本/身份/基准/质量/响应预算严格边界与 schema 已实现 | 无已配置机构节点/真实需求验收；不接启动链路；Mac 未增加网络 entitlement，部署 no-go |

## 本次可复现证据

环境是 Debian 13 x86_64，Swift 6.0.3 Ubuntu 工具链，Python 锁定 pydantic 2.13.4 / jsonschema 4.26.0。为运行 Foundation 算法检查，在临时 harness 中用 Apple swift-crypto 3.10.0 提供 SHA-256；生产仍为系统 CryptoKit，没有新 App 依赖。纯 Workspace 值文件直接链接真实源码；没有用模拟 Apple UI 或 FileDocument 冒充平台验收。

```bash
PATH=/tmp/simunow-swift/usr/bin:$PATH \
  SIMUNOW_SWIFT_CRYPTO_PATH=/tmp/simunow-swift-crypto \
  SIMUNOW_PORTABLE_DIR=/tmp/simunow-portable Scripts/check_portable_native.sh
PYTHONPATH=Backend/src:Backend/tests python3 -m unittest discover -s Backend/tests -v
python3 Scripts/generate_domain_models.py --check
python3 Scripts/generate_native_analysis_schemas.py --check
python3 Scripts/generate_consumer_schemas.py --check
PYTHONPATH=Backend/src python3 -m simunow_worker.models.schema --check
```

结果：17 项真实 Swift 测试通过；44 项 Python 测试通过；8 份真实 Swift wire 输出（含校准父数据）及 17 个拒绝反例通过独立 Python schema/语义/匿名 hash 检查；生成器无漂移。新增的 4 项 Apple 文档/相机/事务测试尚未运行。158 份 Swift 文件还做了 Swift 6 语法解析，不能替代 Apple SDK 类型检查。

`Scripts/check.sh test` 在 Linux 因没有 SwiftUI 失败；`mac`/`ios` 因没有 xcodebuild 失败；开发归档脚本明确拒绝无 Xcode 环境。按 **notAvailable** 记录，没有产生 Apple 构建或签名证据。日志、实际合成 wire 文件与网格基准保存在忽略的 `Artifacts/N5-N6/`。

## Apple 环境待执行脚本

1. 执行 `Scripts/check.sh contracts`、`mac`、`ios`，确认全部旧回归与新增文档测试；Debug/Release 分开保存日志。
2. 家庭模板中采用规则档案，修改角度/位置，复制两个候选（含不同展示密度），确认 undo/redo 同时恢复项目与配置；无网络重复。
3. 每个方案保存预览，冻结比较；旋转任一 3D 视口，检查同步及独立选取；强制二维后继续编辑与比较。关闭进程，再开包，检查固定比较和费用身份。
4. 导出文字、JSON 和长中文 PDF，将实际 PDF 渲染为页图逐页检查，抽查同一 run、单位与缺项；在 Mac/iPhone 系统分享中取消与完成；iOS 导出原生包后从浏览器再开。
5. 导入坏 CSV、无时区、缺失/异常和合成校准分组；检验明确拒绝与会话未保存；修改几何/安装/风档后检查历史标记。真实数据另建本地试验，不把合成例算为实测通过。
6. 支持 LiDAR 的真机上主动开始/结束/重试扫描，检查权限拒绝、包围盒确认和保存撤销；无 LiDAR/Mac 按手动向导完成相同本地流程。
7. 验收两窗口、晚到结果、满预算、损坏/未来文件、存盘失败、旧包升级；深浅色、VoiceOver、大字号、横竖屏、Reduce Motion、最低 OS 各记结果。两端各一次试用，记录误解与修正。
8. 完成后才运行 `Scripts/prepare_release_candidate.sh mac|ios`；其产物仅为未签名开发归档。签名、安装、商店/公证与正式发布仍需独立门槛和用户授权。
