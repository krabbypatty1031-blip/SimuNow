# 技术依据与查询记录

查询：2026-10-03。这里只记录支持路线边界的官方资料；内部展示档案的数值、性能目标与工作量估计是设计选择，尚无准确率或运行性能证据。

| 来源 | 支持的结论 | 对本计划的影响 |
|---|---|---|
| [Apple RealityView](https://developer.apple.com/documentation/realitykit/realityview) | SwiftUI中承载RealityKit内容 | N2三维展示入口 |
| [Apple RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent) | iOS可使用非AR模式；macOS内容使用非AR模式 | 明确选择虚拟相机，房间查看不依赖扫描 |
| [Apple virtual camera](https://developer.apple.com/documentation/realitykit/realityviewcamera/virtual) | 虚拟相机选择API | N1验证公开API后接入 |
| [Apple CameraControls](https://developer.apple.com/documentation/realitykit/cameracontrols)、[orbit](https://developer.apple.com/documentation/realitykit/cameracontrols/orbit) | 公开相机交互选项 | N1能力spike先验证，与自管相机只能择一控制 |
| [Apple PerspectiveCameraComponent](https://developer.apple.com/documentation/realitykit/perspectivecameracomponent)、[lights and cameras](https://developer.apple.com/documentation/realitykit/scene-content-lights-and-cameras) | 非AR相机组件与视角控制的公开入口 | N2拟采用单相机状态，实际RealityView接入仍由N1验证 |
| [Apple Task.checkCancellation](https://developer.apple.com/documentation/swift/task/checkcancellation())、[WWDC23并发任务](https://developer.apple.com/videos/play/wwdc2023/10170/) | 协作取消/任务生命周期需明确处理 | N1限制事件、保留句柄并显式传播取消；非运行性能证据 |
| [Apple WWDC24: Discover RealityKit APIs for iOS, macOS and visionOS](https://developer.apple.com/videos/play/wwdc2024/10103/) | RealityView与多种RealityKit展示能力跨平台 | 共享场景与小范围平台适配；不把通用物理当CFD |
| [EnergyPlus Engineering Reference v24.2](https://energyplus.net/assets/nrel_custom/pdfs/pdfs_v24.2.0/EngineeringReference.pdf) | 热平衡/热容量算法需要相应输入与假设 | N4仅做限定集总估算，N6动态模型须独立校准；不声称等价EnergyPlus |
| [NIST CONTAM guide v3.4](https://www.nist.gov/publications/contam-user-guide-and-program-documentation-version-34) | 室外/室内交换、机械与浮力驱动有明确模型 | 首版路径规则不自动提供换气/空气质量结论 |
| [NIST CONTAMW theoretical background, §5.1](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=860813) | 均匀混合分区假设不能给区内局部效应 | 集总温度/浓度不能包装为座位级空间预测 |

## 本机SDK核对

检查当前Xcode的MacOSX/iPhoneOS SDK公开Swift接口声明；RealityView与RealityViewCameraContent声明为 macOS15.0、iOS18.0起可用，虚拟相机在同范围可用。核对入口为SDK中的RealityKit及其SwiftUI接口声明；实现只import公开RealityKit/SwiftUI，不依赖底层私有模块名。

这是API可用性核对，不是实际两端渲染成功证据。N1-02仍需使用目标SDK和运行时验证；N2保留macOS14/iOS17二维回退。未来SDK变化重新核对，不将更新工具链等同提高最低系统。

## 尚未取得的证据

没有为规则扩散角/射程/衰减选择经校准通用系数；未验证任何本地速度场、座位温度、舒适结果或节能效果。已有N3任务p50/p95测量，见[N3交接](../Delivery/N3-implementation.md)；GPU帧率与消费者试用数据仍未取得。后续资料登记必须写版本、具体适用范围、独立数据来源与复现入口。

## 详细执行稿的内部约定

N3的0.05m展示宽度、12°扩散、Halton采样、衰减函数、64×128预算，以及N2显示墙厚/FOV/视角、N1排队/缓存/侧文件预算，均为可修改且需版本化的实施选择。没有新增物理精度依据。N4的fixed24HourReference是缩小首版时段模型的选择，不保证真实账单日规则；ρ/cp测试值只用于解析夹具。详细数值与限制见阶段文件，不从本表推导实测结论。

## N4公开来源案例准备（2026-10-03）

此案例只用于核对额定连续情景输入与来源链路，不是房间实测，不成为生产默认值或账单精度证明。

- 厂家：[Mitsubishi Electric MSZ-AY/AP，February 2026](https://library.mitsubishielectric.co.uk/pdf/download_full/4788)，第2页MUZ-AY25VG2栏，SYSTEM POWER INPUT的Heating/Cooling nominal行列为0.78/0.60 kW；采用制冷电输入600 W，与配套MSZ-AY25VGK2的2.5 kW制冷能力分开。不得用COP/EER反算输入，额定运行只作为显式情景。
- 电价：[EDF Tarif Bleu官方价格表](https://particulier.edf.fr/content/dam/2-Actifs/Documents/Offres/Grille_prix_Tarif_Bleu.pdf)，生效2026-08-01，第1页Option Base、6 kVA行为20.01欧分TTC/kWh，即0.2001 EUR/kWh。这里采用公布的含税单位消费费率，未包含订阅月费、设备、安装或额外费用；不再额外虚构税率叠加。适用性只限来源列出的法国居民方案。
- 案例另行声明参考日08:00–10:00连续运行，这是测试选择而非来源中的实际采样：600 W×2 h=1.2 kWh，1.2×0.2001=0.24012 EUR。生产要求用户确认basis/时段与费率，不能推广为消费者实际账单。
- 核对方式：官方PDF浏览文本的页码、行标题、列名及生效日期。浏览截图接口未返回可检视像素；直接下载出现证书/截断/连接超时，临时不完整PDF不作为视觉核对证据。N4实施时继续验证DTO/计算/界面展示，来源案例与现实测量精度分开记录。
