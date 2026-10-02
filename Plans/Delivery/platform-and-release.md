# 平台与交付

## 兼容矩阵

| 能力 | macOS | iPadOS / iOS |
|---|---|---|
| 项目/方案/指标模型 | 共享 | 共享 |
| 编辑与结果 UI | 全工作区 | 自适应分栏/详情 |
| 场数据加载与采样显示 | 共享格式 | 共享格式，内存预算不同 |
| 房间扫描 | 导入 | RoomPlan + 能力检测 |
| 本地 Python / CFD | Mac adapter | 不支持 |
| 远程计算 | 后续可选 | 后续可选 |
| 报告 | 导出/留档 | 查看/分享/可支持的导出 |

最低 macOS14 / iOS17；每个新增框架调用核对 SDK availability。当前 package 的 SwiftUI 空工作区支持这两端，尚无 renderer 或 RoomPlan。

## 工程配置

`SimuNowMac` 与 `SimuNowiOS` schemes 为共享；Debug 只编译当前架构，Release 使用目标默认架构。当前无开发团队，模拟器/无签名构建不需要团队；真机和正式发行由用户配置。
bundle identifier `com.simunow.mac` / `com.simunow.ios` 为开发占位。发布前替换为团队持有的标识并核对平台权限。
当前只有 accent asset，App icon、privacy manifest（按实际 API 要求）、采集权限描述与本地化资源在能力接入阶段完成。

## 运行时与沙盒

Mac 已启用 app sandbox 与用户选择文件读写。P3 验证 sandbox 下 helper/Process、项目安全书签、容器桥接与运行时路径。
可选路径：应用内签名受控 helper、明确安装的 companion、用户配置私有节点。根据实际分发渠道做 ADR，不默认关闭 sandbox。
Python/EnergyPlus/OpenFOAM 以固定版本部署，启动前 doctor 检查版本与能力；缺少引擎显示修复路径，不在启动时在线安装。
OpenFOAM 发行方式逐项核对依赖许可；独立进程不等于免除分发要求。

## 安全与数据

房间、照片、人员使用与能耗默认本地。远程计算需用户配置目标节点、最小包、认证加密、保留与删除策略。
共享报告可隐藏名称/位置，日志不含密钥或敏感标签；不将真实房间提交到仓库。
移动端文件与后台任务限制独立验证；账号与云同步在明确需求后引入。

## 交付清单

双端构建 → 设备运行 → 运行时/权限 → 图标/版本/本地化 → 许可证与数据说明 → 签名/公证或 TestFlight → 新机器试装。
本次只完成骨架与编译/运行证据；不上传、发布或替用户选择开发账号。
