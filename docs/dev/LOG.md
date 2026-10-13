# 开发记录

只记重要节点：日期｜改动｜验证｜遗留。最新记录追加在末尾。

## 2026-10-12

- 从空目录创建 macOS SwiftUI 原型，接入 FFmpeg + COLMAP 稀疏重建与 SceneKit 点云浏览。
- `swift build --disable-sandbox` 编译通过；未进行视频端到端测试（缺少 COLMAP）。
- 加入 PLY、OBJ、GLB、XYZ、PCD 导出；`swift test --disable-sandbox` 通过 1 项格式验证。

## 2026-10-13

- 打包并临时签名 `dist/SpaceWalk.app`，通过 Launch Services 启动；进程检查显示应用正在运行。桌面控制工具拒绝访问，未核验窗口画面。
- 定位退出码 1：COLMAP 4.2.1 不识别旧的 SiftExtraction/SiftMatching GPU 参数。改为 FeatureExtraction/FeatureMatching，保留分阶段日志与明确错误信息。
- 用失败任务留下的 11 张帧在临时目录跑通 COLMAP 特征提取、匹配、mapper 和 PLY 导出；两个模型分别为 91 和 676 点，现改为选取较大模型。
- `swift test --disable-sandbox` 通过 3 项测试；修复版应用已重新签名并启动。应用窗口未直接核验。
- 针对卧室只有点的问题，用现有 11 帧验证全量匹配（10 帧/888 点）和稀疏 Delaunay（1,096 面）；加入 4 fps 抽帧、短视频全量匹配、粗略网格显示与导出、质量提示。COLMAP PatchMatch 在本机报错要求 CUDA。4 项测试通过；原视频待用户上传。
- 修复版应用重新签名并启动；旧帧的网格与点云预览保存至 `dist/preview/`，供应用内直接打开比较。界面未能通过桌面控制工具核验。
- 用户明确目标是可在其他应用中使用的卧室游戏场景；新增 `GAME_SCENE_TARGET.md` 记录几何、纹理、碰撞、尺度和目标应用导入验收要求。当前稀疏路径仅定位为诊断预览。
- 修正界面文案，避免把粗略点云/网格误称为可用游戏模型；`swift build --disable-sandbox` 通过。
