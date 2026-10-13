# SpaceWalk · 开发状态

更新日期：2026-10-13

## 项目目标

- macOS SwiftUI 应用：从用户卧室采集素材构建可导入其他应用、可作为游戏场景的完整房间。验收标准见 `docs/dev/GAME_SCENE_TARGET.md`。

## 当前状态

- 已实现视频导入、FFmpeg 抽帧、COLMAP 顺序匹配与稀疏重建、PLY 输出。
- 已实现 SceneKit 彩色点云浏览器：旋转、缩放、WASD、Q/E、Shift。
- 已支持直接打开已有 PLY；处理在本机运行。
- 已支持导出 PLY、OBJ、GLB、XYZ、PCD 点云。
- 已修复 COLMAP 4.2.1 的 GPU 参数名，重建时优先选择注册画面最多的子模型，并保存逐阶段日志。
- 短视频改用全量画面匹配、4 fps 抽帧；支持稀疏 Delaunay 粗略网格预览与 PLY/OBJ/GLB 三角面导出，并提示质量不足。
- 已更新并启动 `dist/SpaceWalk.app`；进程检查确认正在运行。桌面控制工具未授权，窗口未直接核验。
- 现有 11 帧的实验产物保存在 `dist/preview/bedroom-coarse-mesh.ply` 与 `bedroom-points.ply`，可在应用中打开比较。
- 当前网格仅是稀疏点推算的粗略表面，不是照片级连续卧室。COLMAP 稠密立体重建在本机需要 CUDA，无法使用。
- 界面已把现有输出标为「粗略预览」，明确不具备照片纹理与碰撞；`swift build --disable-sandbox` 通过。

## 未完成事项

- [ ] 在应用内使用原视频完整跑一次，并核对点云显示效果。
- [ ] 获取用户原视频后分析时长、运动和重叠度；确定适合 Mac 的稠密重建方案。
- [ ] 明确目标游戏应用/引擎与手机 LiDAR 能力，再确定导出格式和采集流程。
- [ ] 优化大点云加载、进度显示与相机控制。

## 下一步

1. 用户上传原视频后评估素材，并在修复版应用中完整重建。
2. 基于素材与硬件能力决定稠密网格或 splat 渲染方案。

## 关键路径与验证

- 入口：`Sources/SpaceWalk/main.swift`；运行：`swift run SpaceWalk`。
- 验证：`swift test --disable-sandbox`（此受限环境需设置可写模块缓存）。

## 阻塞

- 现有任务仅 11 帧；全量匹配实验从 5 帧/91 点提高到 10 帧/888 点，Delaunay 得到 1,096 面。应用内新流程待验证；照片级稠密方案仍缺失。用户表示会上传原视频。
