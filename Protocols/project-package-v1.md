# SimuNow 项目包 v1

P2-04 的本地 `.simunow` 是目录包，导出 UTI `com.simunow.project`，同时符合 `com.apple.package` 和 `public.content`。Mac/iOS 原生 DocumentGroup 管理打开、协调保存与关闭；独立导出通过 ProjectPackageIO 完成序列化后原子写入。不能对 DocumentGroup 正在管理的 URL 再调用独立写入。

```text
Example.simunow/
  project.json       必需，ProjectDocument schemaVersion 2
  metadata.json      必需，项目包 bookkeeping version 1
  assets/weather/    按 SHA-256 命名的 EPW 副本
  runs/              预留；已有附件按不透明数据保留
```

`project.json` 使用 [项目输入 v2](project-model-v2.md) 和 ProjectCodec。Core/worker 的物理输入契约不变，未来引擎仍通过不可变快照和运行请求消费输入。`metadata.json` 是 App 文档层数据，不是物理输入，worker 当前不读取项目包或该侧文件。[metadata schema](Schemas/project-package-metadata.schema.json) 定义其结构：

```json
{"packageVersion":1,"baselineScenarioID":"00000000-0000-0000-0000-000000000001","templateID":"simunow.template.office.v1","templateVersion":1}
```

基准、模板字段可省略；templateID/templateVersion 必须同时存在且非 null，模板版本为正整数、标识非空且 UTF-8 最多 256 bytes。基准 UUID 必须引用 project 中的方案。元数据根未知字段与未来 packageVersion 拒绝；项目未来根版本、损坏 JSON、非法已知 payload 拒绝。未知扩展 payload、其他包内文件、二进制附件和空目录保留，不能据此声称支持其计算或渲染。

结构合法而有语义错误的项目进入修复状态，完整性不通过禁止保存；不完整且明确未知的草稿允许保存。计算准备独立检查当前方案；缺失包内天气资源阻断准备但不阻断草稿保存。天气路径必须在 `assets/` 内，存在的资源必须为普通文件且与声明哈希一致；失配和非法路径阻断保存。EPW 导入只做格式头检查、复制与哈希，真实气象适用性留待 P3。

导入 JSON 创建独立项目，不覆写源文件。v1 必须显式确认迁移；Mac 打开新文档，iOS 先进入独立导入编辑会话，修复后导出新包、从文档浏览器打开。原项目不被替换。版本迁移沿用 ProjectMigrator，不增加隐式物理默认值。

默认读取/输出上限：4096 条目、32 层、64 MiB 单文件、256 MiB 全包、8 MiB project.json、64 KiB metadata.json。完整输出树含必需 JSON 都参与预算。符号链接、特殊文件和非法相对路径拒绝。该 value 文档面向 P2 小项目；后续大体积场数据需要流式存储和独立 artifact 生命周期。

编辑撤销保留最近 60 个完整项目值（含基准和模板信息），会话关闭后不恢复历史。天气附件在会话内追加保留，撤销回退引用，重做仍可引用旧文件。选择状态与捕获快照不写入 package metadata；P2 的快照可以含未知输入，不等于 RunInput、运行哈希或数值结果。

验证见 [工程记录](../Plans/Delivery/verification.md)。原生文档声明依据 [Apple DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup) 和 [Apple DTS 文档类型说明](https://developer.apple.com/forums/thread/783646)。
