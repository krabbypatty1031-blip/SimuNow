# 计算编排层

已实现 P2-01 的项目模型 v2、扩展注册、纯校验、v1 迁移和不可变场景输入快照，见 [项目契约](../Protocols/project-model-v2.md)。尚未接入任何数值引擎；doctor 不依赖模型测试环境即可运行。

```bash
PYTHONPATH=Backend/src python3 -m simunow_worker doctor
python3 -m venv Backend/.venv
Backend/.venv/bin/python -m pip install -r Backend/requirements-dev.lock
Scripts/check.sh contracts
```

requirements-dev.lock 固定模型/测试依赖及传递版本；独立虚拟环境不提交。Pydantic 模型不可变，编辑通过构造新值；扩展注册表和未知 JSON 同样不可变。实际引擎、Process、容器、任务协议与运行哈希仍按 [P1](../Plans/Phases/P1-physics-spike.md) / [P3](../Plans/Phases/P3-orchestration-energy.md) 接入，不在 App 启动时下载安装。
