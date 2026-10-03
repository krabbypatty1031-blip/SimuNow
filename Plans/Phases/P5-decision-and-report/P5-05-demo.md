# P5-05 离线演示与失败路径

**Files:**

- Modify: `WorkspaceView` 报告空状态 → 有证据才显示导出
- Modify: `RoomEditorForm` / 报告页：未配置 DeepSeek 时不显示导出按钮，状态行说明原因；按钮文案仍是「导出对比说明」，不是「生成报告」
- Test: 无密钥拒绝导出；质量失败拒绝进报告；引擎未配置不可点提交（已有）
- Modify: `Plans/Delivery/verification.md`（手测清单）
- 不修改：Release 的 App Sandbox 与 library validation；只增加 `network.client`；不把 Debug 关 sandbox 带进 Release

**Interfaces:**

- Consumes: P5-01…04、P4 Debug 手测链路
- Produces: 固定办公室输入下可复现的建议+PDF；失败路径文案
- 不产生：Release 公证、签名 helper、App Store 包

**约束：**

- 导出验收的是 **DeepSeek 对比说明 + 本地附录**（ADR-019）。无密钥不能导出。
- 质量失败 / stale / 口径不同：不能当有效推荐进 PDF
- 未配置引擎：提交按钮不可点（P3/P4 已有）
- 不在启动时下载模型或引擎
- 不把真实房间照片、密钥写进仓库

---

### P5-05a 失败路径

- [x] 无候选 → 报告页保持空状态，无空的「导出」可点按钮
- [x] 仅有质量失败候选 → 可解释、不可导出有效建议 PDF
- [x] API 键缺失：不能导出，状态行「未配置 DeepSeek，不能生成对比说明」

### P5-05b 手测链路（Debug）

- [x] 办公室模板 + 舒适默认 + 演示电价（单测锁 clo=0.5 / met=1.2 / 1.2 HKD）
- [x] L1 → L2 默认口 → 固定；改送风高度 → L2 → 固定（App Debug 2026-10-03：L1 `B0932281`、默认口 `057D25D4` 24.43–24.73 °C、降低口 `373BC329` 24.21–24.50 °C）
- [x] 报告页三卡（运行/舒适/改造）可从同口径两候选生成；导出 PDF 含两个 run ID、达标比例、代表日 HKD、演示电价声明
- [x] 拔掉 DeepSeek 配置后导出被拒绝，不写文件

通过：无密钥时按钮不可点且不写文件。失败：没 API 却写出一份假装模型写的 PDF。
App Debug 点击链路已于 2026-10-03 记录（当时仍是证据表）；DeepSeek 官方连通仍待手测。Release 沙盒仍不能宣称产品闭环。
