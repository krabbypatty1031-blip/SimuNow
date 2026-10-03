# 3D 视口方案 A

日期：2026-10-03。底座：UX 第一轮 + 两位小数已通。用户选择方案 A：只读 RealityKit 查看，不做点选与三维拖柄。

**目标：** 在不改物理、schema、哈希、质量门的前提下，把房间视口做成可绕看的三维实体：房间、门窗、家具盒、人话座位名、质量通过才上色的坐姿高度温度切片。

**可用性：** `RealityView` 是 macOS 15 / iOS 18（现行 SDK）。工程最低仍是 macOS 14 / iOS 17；旧系统走 Canvas `RoomWireframeView`。

**不做：** 点选联动、3D 拖柄、纵向剖面、把 `z0` / `L1` 画回界面、改求解器。

详见 [3D-checklist.md](3D-checklist.md)。决策见 [ADR-016](../../Delivery/decisions.md)。
