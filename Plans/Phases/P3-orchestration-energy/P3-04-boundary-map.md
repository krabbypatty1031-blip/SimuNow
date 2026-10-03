# P3-04 L1 到送风/壁面/热源边界

**Files:**

- Create: Swift/Python 边界 DTO（给后续 L2，不跑 OpenFOAM）
- 依赖：P3-03

**Interfaces:**

- Consumes: L1 result + 房间几何/热源
- Produces: 送风 T、壁面热流或 omitted、人员/灯光/设备对流热
- 不产生：网格、场、质量.pass

**约束：**

- 送风温度依据 L1 或设备设定，不是房间设定温度
- 辐射/对流不重复计入
- envelope 未建模保持 omitted

---

### P3-04a 映射键

- [x] supply T、return、window flux、occupant/lighting/equipment W

### P3-04b 送风依据

- [x] 测试：setpoint 26、supply 16 时边界用 16

### P3-04c 守恒

- [x] 人员显热只出现一次
