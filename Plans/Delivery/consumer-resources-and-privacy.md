# N5 资源、隐私与开发候选

2026-10-03；版本 0.2.0，构建 2；macOS 14 / iOS/iPadOS 17；现代 RealityView 仍限 macOS 15 / iOS 18，旧版完整二维入口保留。

| 内容 | 来源/许可/状态 |
|---|---|
| 应用名 SimuNow | 既有名称与 bundle IDs 保留 |
| AppIcon | 项目 stdlib 脚本原创房间/风向图形；Mac 16…1024 和 iOS 1024 RGB PNG，无外部图片或字体；已看 256px 生成图 |
| 常用文字 | App 主 bundle Localizable.xcstrings，zh-Hans/en；单位用系统格式化，固定 SI/Decimal 不改写 |
| UI/三维/分页/扫描 | SwiftUI、RealityKit、CoreText/CoreGraphics、RoomPlan/AVFoundation 系统框架；无新第三方 App 包 |
| 开发验证 SHA-256 | 临时 Apple swift-crypto 3.10.0 (Apache-2.0)，仅 Linux harness；不复制到 App、不变更生产 CryptoKit |
| Python 开发依赖 | 既有锁定 pydantic/jsonschema 等；仅契约开发工具，不随消费者 App 启动 |
| 源码授权 | 仓库当前没有 LICENSE/NOTICE；正式对外分发前须由所有者明确源码/资源授权，不自动选择开源许可证 |

`PrivacyInfo.xcprivacy` 默认无跟踪/后台收集；已审查代码没有新增 UserDefaults、文件时间戳等 required-reason API 直接调用。房间、测量和扫描 JSON 留在本地项目；相机仅主动扫描请求，非 AR 浏览和手动建模不需相机。默认分享匿名摘要，完整项目仍是用户明确的文档导出。未来专业节点真正启用后必须按实际机构数据收集/保留规则重审隐私清单和商店声明。

资源在 `generate_project.py` 注册；目标 IDs、现有 schemes 保留。Mac sandbox 与用户选中文件权限保持开启，没有启动网络/下载/服务。Swift 新源文件由包自动发现。

```bash
Scripts/prepare_release_candidate.sh mac
Scripts/prepare_release_candidate.sh ios
```

脚本先执行 schema 漂移及完整 Swift 包测试，再产出 `CODE_SIGNING_ALLOWED=NO` 的 Release archive 到临时目录；它不是可正式分发的安装包。当前 Linux 无 Xcode，归档 notAvailable。签名证书/Team、真机或清洁 Mac 安装、升级旧项目、默认文档类型、两端演示彩排与正式商店/公证均待独立验证；不因此关闭 sandbox 或自动上传。
