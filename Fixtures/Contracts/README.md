# 人工项目契约夹具

office.json / classroom.json 来源为 Backend/tests/fixture_factory.py，schemaVersion=2，单位/坐标见 Protocols/project-model-v2.md。全部参数为人工假设，source.note 明确记录用途；不是实测、公开物理基准、设备规格或真实 CFD。

目的：Swift/Python/schema 互操作、完整性校验、旧版迁移、未知 payload 保留及快照测试。天气路径 contract-only.epw 和全零哈希是假资产标识，不对应天气文件，不能用于真实计算。费用未提供，不表示免费；不输出舒适、能耗或节能结论。

负向输入在测试临时目录按 factory 生成；不提交实际场或真实房间资料。修改字段声明后同步 fixture_factory，再显式更新两份 JSON。
