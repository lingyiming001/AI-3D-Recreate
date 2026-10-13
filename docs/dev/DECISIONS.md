# 关键决定

仅记录影响后续开发的决定、理由和替代方案。

- 首版采用 FFmpeg + COLMAP 生成稀疏 PLY，SceneKit 负责本地浏览。这样可先验证视频重建与交互闭环；照片级效果需要后续稠密重建或 Gaussian Splatting。
