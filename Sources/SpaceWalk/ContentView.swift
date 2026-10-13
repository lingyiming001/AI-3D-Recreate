import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @State private var reconstruction = Reconstruction()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 310)
            Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
            ZStack(alignment: .bottomLeading) {
                CloudView(url: reconstruction.showMesh ? (reconstruction.meshURL ?? reconstruction.cloudURL) : reconstruction.cloudURL)
                if reconstruction.cloudURL == nil {
                    VStack(spacing: 15) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 76, weight: .ultraLight))
                            .foregroundStyle(.cyan.opacity(0.7))
                        Text("重建拍摄空间")
                            .font(.system(size: 28, weight: .semibold))
                        Text("导入手机视频，生成可浏览的 3D 空间预览")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
                if reconstruction.cloudURL != nil {
                    Text("拖动旋转 · 滚轮缩放 · WASD 移动 · Q/E 升降 · Shift 加速")
                        .font(.caption)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.title2).foregroundStyle(.cyan)
                Text("SPACEWALK").font(.headline).tracking(2)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("01 / 视频").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Button { reconstruction.openVideo() } label: {
                    Label("导入手机视频", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                if let url = reconstruction.videoURL {
                    Text(url.lastPathComponent).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("02 / 空间重建").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Button { reconstruction.start() } label: {
                    Label("开始重建", systemImage: "cube")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(reconstruction.videoURL == nil || reconstruction.isRunning)
                if reconstruction.isRunning { ProgressView().controlSize(.small) }
                Text(reconstruction.status)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if reconstruction.frameCount > 0 {
                    Text("已抽取 \(reconstruction.frameCount) 帧").font(.caption2).foregroundStyle(.tertiary)
                }
                if let project = reconstruction.projectURL {
                    Button("打开任务文件夹与日志") { NSWorkspace.shared.open(project) }
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("03 / 探索").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Button { reconstruction.openCloud() } label: {
                    Label("打开已有 PLY 点云", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let url = reconstruction.cloudURL {
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
                if reconstruction.meshURL != nil {
                    Toggle("显示粗略表面", isOn: $reconstruction.showMesh)
                        .font(.caption)
                    Text("表面由稀疏点估算，可能有缺口或错误三角面。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("04 / 导出格式").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Picker("格式", selection: $reconstruction.exportFormat) {
                    ForEach(PointCloudFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .labelsHidden()
                Text(reconstruction.exportFormat.detail)
                    .font(.caption2).foregroundStyle(.secondary)
                Button { reconstruction.exportCloud() } label: {
                    Label("导出粗略预览", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(reconstruction.cloudURL == nil)
                Text(reconstruction.showMesh && reconstruction.meshURL != nil
                     ? "PLY / OBJ / GLB 包含粗略三角面；XYZ / PCD 为点云。"
                     : "当前显示点云；OBJ 和 GLB 保存为点图元。")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("当前导出尚无照片纹理与碰撞，不可直接作为游戏场景。")
                    .font(.caption2).foregroundStyle(.orange)
            }

            Spacer()
            Text("建议拍摄至少 20 秒：绕卧室缓慢走动，覆盖不同角度，保持画面重叠；避免纯旋转。")
                .font(.caption).foregroundStyle(.tertiary)
            Text("本地处理 · 原视频不会上传")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 22)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.055, green: 0.075, blue: 0.11))
    }
}
