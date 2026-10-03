# P4-04 舒适适用性

**Files:** 待采样后接 `pythermalcomfort` 适配  
**依赖:** P4-03  
**不做:** 关掉方法输入限制装可评价；把达标座位比例叫实测满意率；儿童/睡眠默认套成人办公模型

**约束:** 缺 RH、MRT、clo、met 时 PMV omitted。超模型范围「不可评价」。

### P4-04a 可评

- [ ] 输入齐全时写 PMV/PPD，带方法名

### P4-04b 不可评

- [ ] 缺湿或超范围 → value null、omitted、原因字段
- [ ] 不得填 PMV=0
