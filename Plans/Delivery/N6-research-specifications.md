# N6 子规格与 go/no-go

2026-10-03。所有夹具为人工几何/公式基准，不是现场设备数据。研究方法从未注册到 production 本地 executor，既有 rulePreview/simplifiedEstimate 依据不变。

## 有限射流

方法 `simunow.experimental.finiteJet.v1`；经验速度 `V(x,r)=V_out/(1+k*x)*exp(-(r/(r0+s*x))²)`。米、秒、m/s；安装单位方向分解轴向 x 与径向 r。r0 是用户声明实测等效半径；V_out 必须有仪表测量。校准仅自由下游射流，排除近场 x<2r0、反向或 x>30m，不含家具绕流、贴壁、浮力或回流。

扩散 s∈[0.02,0.34]、衰减 k∈[0.01,1.01] m⁻¹，各 41 个值，最小训练 SSE 选择；最多 2000 个有效记录。至少 6 训练/3 独立留出，有轴/径向变化；明确用户 RMSE 门槛、公开 MAE/RMSE/max-error 和原参数留出误差。网格边界最优视为不可辨识/模型不适用并拒绝。原测量及各失败记录保留。**算法验收 go；消费者实际速度 no-go：缺真实独立数据。**

## 平均动态 RC 与 CO₂

单房间、规定的分段常量源项/室外条件。`C*dT/dt = (UA + cp_vol*Q_out)*(T_out-T) + Q_internal-Q_cooling`；`dCO₂/dt = (Q_out/V)*(CO₂_out-CO₂) + 1e6*G/V`。C 显式 J/K，UA W/K，V m³，Q_out m³/s，cp_vol J/(m³.K)，CO₂源 G m³/s。Q_cooling 为实际声明输送显热，无 COP 自动映射；室内回风循环不进入 Q_out。

每个常量段用 exp/expm1 精确积分；输出时间步只是采样，不是隐式实测控制。支持 C>0、无交换守恒、预先定义源信号，最多 1000 段、7 日、10000 输出、采样步≥0.1s。解析指数、封闭源项和不同输出步长一致测试通过。没有温控器、潜热、湿度、辐射舒适或逐点场。**数值子规格 go；物理/产品升级 no-go。**

## 原生 CPU 网格

方法 `simunow.experimental.closedBoxProjection2D.v1`。2D MAC 面速度/中心压力，常密度不可压缩；封闭外壁和障碍面法向速度为零，流体 mask 内统计。Neumann Poisson Gauss–Seidel，压力只定到常数；按投影后的最大散度而非单次迭代次数声明收敛。网格各边 2…64，最多 5000 迭代，有限量/数组尺寸检查和取消。

热步：2D 封闭绝热，Boussinesq 浮力预测→压力投影→一阶上风守恒温度通量和显式扩散。`CFL = dt/dx*(max|u|+max|v|)+4*alpha*dt/dx² ≤1`；压力不收敛或 CFL 越界拒绝；障碍不当零温度参与平均。无湍流/近壁面/3D/送回风边界/湿度，不声称房间 CFD。

内部基准：单位方盒正弦初始速度，8²/16²/32²，dt=.01s、ρ=1.2、散度容差 1e-6；另有障碍隔绝、温度均值守恒和不稳定步拒绝。Debian Swift 6 Debug 的本次 8/16/32 方格耗时约 0.006/0.097/1.443s，迭代 161/701/2901，最终散度约 7.53e-7/8.39e-7/9.51e-7 s⁻¹，估计主要数组 2752/10752/42496 字节。数字是单次合成 CPU 测量，非 RSS、p95、iPhone 预算或独立物理数据；实际 JSON 在 Artifacts。**算法研究 go；消费者实时/Metal/3D 升级 no-go**，先做真机预算及外部独立基准再立项。

## RoomPlan 与专业节点

RoomPlan 只在支持真机且用户主动相机授权后运行。采用中央 Apple→米制 Z-up 坐标变换，世界轴包围盒近似须用户确认；不宣称精确非矩形重建。保留原点、scan 来源、原始本地 JSON 与 hash，设备/门窗/关注点和性能要人工补齐。没有扫描能力或权限时返回既有手动向导。**纯转换 go；SDK/真机验收 notAvailable。**

专业复核采用用户配置的 HTTPS、临时认证、单次 inputHash 与数据传输确认，不探测默认节点、不启动 worker。严格 receipt/version/quality/benchmark、有限响应、禁止 redirect 和异源结果；首版离线流程独立。不提供未配置的可点击上传按钮，Mac sandbox 未增网络权限。**可选协议/适配研发 go；节点产品接入 no-go**，缺已授权机构及真实节点验证。
