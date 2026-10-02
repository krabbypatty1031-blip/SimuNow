# 计算编排层

已实现 P2-01 的项目模型 v2、扩展注册、纯校验、v1 迁移和不可变场景输入快照，见 [项目契约](../Protocols/project-model-v2.md)。P1-01 已建立固定运行目标与真实 doctor，详见 [运行环境说明](Runtime/README.md) 和 [诊断协议](../Protocols/doctor-v1.md)。P3 已实现 `run` 命令（[run-input](../Protocols/run-input-v1.md)/[run-events](../Protocols/run-events-v1.md) 协议）与 L0 稳态代表日能耗适配器（集总平均估算）；L1/L2/L3 引擎未安装未接入。doctor 本身只依赖 Python 标准库（L0 自检惰性导入锁定依赖）。

```bash
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
PYTHONPATH=Backend/src python3 -m simunow_worker run --input <run-input.json> --run-dir <runs/<run-id>> [--cancel-file <path>]
python3 -m venv Backend/.venv
Backend/.venv/bin/python -m pip install -r Backend/requirements-dev.lock
Scripts/check.sh runtime  # 行为测试 + 本机 doctor；blocked 默认仍退出 0
Scripts/check_runtime.sh --strict  # 引擎环境未满足时退出 2
Scripts/check.sh contracts
```

使用 manifest 指定的 Python 3.13.16（ADR-012）建立环境；上面的 python3 必须指向该版本。requirements-dev.lock 固定模型/测试依赖及传递版本；独立虚拟环境不提交。Pydantic 模型不可变，编辑通过构造新值；扩展注册表和未知 JSON 同样不可变。L1/L2 adapter、真实天气/设备数据按 [P1](../Plans/Phases/P1-physics-spike.md) / [P3](../Plans/Phases/P3-orchestration-energy.md) 接入，不在 App 启动时下载安装。
