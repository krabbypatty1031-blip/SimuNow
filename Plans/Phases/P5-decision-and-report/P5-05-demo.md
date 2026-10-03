# P5-05 离线演示与失败路径

**Files:**

- Modify: `WorkspaceView` 报告空状态 → 有证据才显示导出
- Modify: `RoomEditorForm` / 报告页：API 未配置时按钮仍是「导出证据 PDF」，不是灰掉的「生成报告」
- Test: 无密钥导出；质量失败拒绝进报告；引擎未配置不可点提交（已有）
- Modify: `Plans/Delivery/verification.md`（手测清单）
- 不修改：`SimuNowMac.entitlements` 的 Release 沙盒；不把 Debug 关 sandbox 带进 Release

**Interfaces:**

- Consumes: P5-01…04、P4 Debug 手测链路
- Produces: 固定办公室输入下可复现的建议+PDF；失败路径文案
- 不产生：Release 公证、签名 helper、App Store 包

**约束：**

- 离线演示验收的是**证据 PDF**，不是模型 API
- 质量失败 / stale / 口径不同：不能当有效推荐进 PDF
- 未配置引擎：提交按钮不可点（P3/P4 已有）
- 不在启动时下载模型或引擎
- 不把真实房间照片、密钥写进仓库

---

### P5-05a 失败路径

- [x] 无候选 → 报告页保持空状态，无空的「导出」可点按钮
- [x] 仅有质量失败候选 → 可解释、不可导出有效建议 PDF
- [x] API 键缺失：导出证据 PDF 成功，状态行说明「未配置叙述器，仅证据表」

### P5-05b 手测链路（Debug）

- [x] 办公室模板 + 舒适默认 + 演示电价（单测锁 clo=0.5 / met=1.2 / 1.2 HKD）
- [ ] L1 → L2 默认口 → 固定；改送风高度 → L2 → 固定（App Debug 点击本会话未重跑；P4 手测数字见 verification.md）
- [x] 报告页三卡（运行/舒适/改造）可从同口径两候选生成；导出 PDF 含两个 run ID、达标比例、代表日 HKD、演示电价声明
- [x] 拔掉叙述器配置后重复导出仍成功

通过：评委机无外网也能出 PDF。失败：没 API 就无法导出。
App 点击链路不由单测代替；未重跑不得把 P5 阶段门标为关闭。
