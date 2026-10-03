# P4-02 质量、能量、收敛

**Files:** 待 P4-01 通过后创建 `QualityRecord` Swift/Python 与 `quality.json` 契约  
**依赖:** P4-01、P1 `quality.py`  
**不做:** 质量失败仍给有效推荐；把残差下降单独当通过；编造守恒误差 0

**约束:** 质量、能量、监测点同时检查；门槛 mass&lt;1%、energy&lt;5% 是工程目标，不是法定标准。失败保留日志，结果 `quality.state=failed`，座位指标 omitted。

### P4-02a 记录

- [ ] checkMesh / residual / monitor / mass / energy 分字段
- [ ] 分母与各项 W 可追溯

### P4-02b 门禁

- [ ] `pass==false` 时 Swift 结果不得当 current 有效场
- [ ] 缺日志不得标 passed
