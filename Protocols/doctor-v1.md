# Worker doctor 与 runtime manifest v1

P1-01 的 CLI 专用环境诊断；与项目 v2、simulation request / receipt 分开。不会从 App 启动调用，也不承诺计算管线存在。P3 起新增 L0 真实自检（见下「L0 自检」）。

## 兼容与结构

保留 `protocol_version: 1`、`worker_version`、顶层 `status: scaffold` 和 `engines.l1/l2/l3: not_configured`，新增可选 `environment`。既有消费者继续读取原字段；新消费者用 `environment.report_version: 1` 解析环境信息。snake_case，与 camelCase 项目契约分开。本轮没有更改 Swift Codable、项目模型、request、receipt 或其 schema；目前没有 Swift doctor 消费者。

- [doctor-report.schema.json](Schemas/doctor-report.schema.json)：完整 CLI JSON，默认一次输出一行。子进程输出被捕获，stdout 只含报告。
- [runtime-manifest.schema.json](Schemas/runtime-manifest.schema.json)：团队目标配置；实际发现值在 doctor 报告中，不写回 manifest。
- `environment.status` 为 `ready` / `blocked` / `invalid_configuration`。`ready` 仅表示选定宿主、独立 Python、目标 VM 工具版本、daemon、引擎架构/身份/版本与最小启动检查满足，不能解释为 SimuNow 可求解。
- `container.target`、`engine_checks.*.target` 是目标；`discovered_version`、`discovered_build`、架构、内存和 evidence 是发现值。未查询到的值为 null，不能作零或 false 推断。`executable` 只在成功解析真实版本/启动命令后为 true；版本不匹配仍可 executable，但环境受阻。
- `physical_validation: not_performed`、`simulation_pipeline: not_implemented` 保持独立。任何可执行引擎都不会将 l1/l2 改成已实现。

## L0 自检（P3 新增）

L0 是纯 Python 保真度，不需要容器或外部引擎。doctor 在进程内用固定的最小自检快照真实执行两次 L0 稳态适配器，核对确定性、质量状态与关键指标，结果写入顶层 `l0` 对象（`state` / `hint` / `evidence`），并镜像到 P0 兼容字段 `engines.l0`：

- `verified_available`：自检计算通过且两次结果一致。只证明 Python 计算链路可用，不代表物理验证，也不改变 L1/L2/L3 状态。
- `probe_failed`：自检执行失败；hint 含原因。
- `not_configured`：锁定依赖不可导入（doctor 核心保持仅标准库可导入），或 manifest 无效未执行自检。

`--strict` 的退出语义不变：仍只由 `environment.status` 决定（L0 自检是管线 sanity 信号，不是环境门槛）。

## 状态语义

| state | 含义 |
|---|---|
| not_installed | 查找范围内无所选命令，或 daemon 明确返回无该镜像；不是全盘扫描结论 |
| not_configured | 所选本地配置无效，或上游受阻无法探测；镜像存在与否可为 null |
| discovered | 仅发现 PATH 命令/工具版本；不是引擎目标执行验证 |
| verified_available | 所选目标的对应真实检查成功；查看该层 evidence 的证明范围 |
| unsupported | 所选宿主、OS 或架构不支持该固定 profile；不自动采用 x86 模拟执行 |
| unreachable | 已发现运行时，但无法连接 daemon / Colima 未运行 |
| permission_denied | 查询被权限或沙盒拒绝，与 daemon 停止分开 |
| command_missing | 已选流程中执行命令不存在（例如 file 或子命令消失） |
| timeout | 有限超时内未完成；exit_code 为 null |
| process_failed | 子进程非零退出，但不能可靠归类为已知原因 |
| probe_failed | 进程启动失败、响应无法解析/不一致，或探测容器清理未确认 |
| version_mismatch / identity_mismatch | 发现版本/构建或镜像身份不符合固定目标 |

每项有 hint；evidence 包含不含私人路径的命令说明、过程 state 与真实 exit_code。原始 stderr、环境变量值、socket 地址、机器名、认证信息均不进入报告。文件路径配置只在本地环境中读取。远程适配尚未实现，显示 not_configured，外部节点实际能力未知；不探测 SSH 或凭据。

## 退出行为与时间边界

```bash
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor
PYTHONPATH=Backend/src Backend/.venv/bin/python -m simunow_worker doctor --strict
```

- 默认退出 0：成功生成有效环境报告，即使环境 blocked，保留 P0 CLI 行为。
- `--strict`：ready 退出 0，blocked 退出 2，适合 P1 安装后门槛检查。
- manifest 无法读取/非法/执行 profile 不支持：输出 invalid_configuration JSON，退出 3，与 blocked 分开。
- CLI 参数非法：argparse 诊断写 stderr，退出 2，无 JSON。例如超时必须为有限 0.1–15 秒。

核心检查每个过程默认 5 秒（`--timeout` 覆盖）；宿主内存命令固定 3 秒，辅助 PATH 工具盘点最多每项 2 秒，Docker 清理最多 3 秒。过程顺序有限，无网络探测；超时预算合计默认最多 50 秒，15 秒参数最多 110 秒，另加少量启动/终止开销。超时杀死本地进程组；Docker daemon 侧容器另行按随机 probe 专属名称执行 bounded `rm -f`，报告清理状态。daemon 失联时不能保证远端清理完成，报告提示人工检查。没有无期限 daemon/network 等待。

测试使用注入的 Probe 覆盖安装、失配、错误、超时；真实 Python 子进程验证超时和退出。模拟报告不作为本机引擎证据。独立 JSON Schema 验证与 CLI 兼容检查纳入 `Scripts/check.sh contracts`。
