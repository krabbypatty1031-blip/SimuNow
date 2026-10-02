# P3：任务编排与能耗

## 目标与前置

连接 App → worker → L1 → 结果，并建立 L2 可复用任务框架。前置 P1 初步通过与 P2 可运行模型。

## 功能、设计与技术

Mac CLI/helper adapter、JSONL 进度、独立 run 目录、输入哈希、缓存、取消、超时、L1 指标与边界转换。
Swift actor / async、Foundation Process（Mac）、Python subprocess、原子文件、EnergyPlus epJSON/IDF。CPU任务和 UI 状态隔离。

## 工作项

| ID | 工作 | 验收 |
|---|---|---|
| P3-01 | Request/Event/Result schema 与解析器 | 乱序、截断、错 run 有处理 |
| P3-02 | 本地执行器、stderr 日志、取消进程树 | 取消幂等，失败保留证据 |
| P3-03 | 时间表/天气到 L1，容量与电耗分开 | 代表日与单位有效 |
| P3-04 | L1 到送风/壁面/热源边界转换 | 送风温度依据，热源守恒 |
| P3-05 | 缓存、新鲜度、超时和恢复策略 | 旧任务不覆盖当前方案 |

## 关键实现

测试 request 的 input hash 与实际快照一致。日志不含个人房间标签；资源限制按 P1 实测制定。
选等效电耗时显示方法/有效COP/辅机范围；采用真实设备对象则从对应输出取电耗，不重复除 COP。
App sandbox 下进程、路径、容器桥接需要打包验证；架构支持受控 helper 或独立 companion，不能假定 Process 自动取得权限。
iOS 只消费接口/文件结果；远程 adapter 后续接入且不默认上传。

## 验收与降级

Mac 更改代表日或人数，提交任务，看到进度、电耗与边界；退出与失败不损坏项目。
没有真实曲线时使用有来源的等效性能并做范围分析；不以额定制冷功率充当耗电。
