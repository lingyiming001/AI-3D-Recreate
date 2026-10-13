import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class Reconstruction {
    var videoURL: URL?
    var cloudURL: URL?
    var meshURL: URL?
    var showMesh = true
    var status = "导入一段手机视频开始"
    var isRunning = false
    var frameCount = 0
    var projectURL: URL?
    var exportFormat: PointCloudFormat = .glb

    func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK { videoURL = panel.url; status = "视频已导入，准备重建" }
    }

    func openCloud() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ply")!]
        if panel.runModal() == .OK { cloudURL = panel.url; status = "点云已载入" }
    }

    func exportCloud() {
        guard let cloudURL else { return }
        let format = exportFormat
        let source = showMesh && [.ply, .obj, .glb].contains(format) ? (meshURL ?? cloudURL) : cloudURL
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension)!]
        panel.nameFieldStringValue = "scene.\(format.fileExtension)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        status = "正在导出 \(format.rawValue)…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PointCloudExporter.export(source: source, destination: destination, format: format)
                }.value
                status = "已导出 \(destination.lastPathComponent)"
            } catch { status = "导出失败：\(error.localizedDescription)" }
        }
    }

    func start() {
        guard let videoURL, !isRunning else { return }
        isRunning = true
        cloudURL = nil
        meshURL = nil
        Task {
            do {
                _ = try findExecutable("ffmpeg")
                _ = try findExecutable("colmap")
                let project = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SpaceWalk", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                projectURL = project
                try FileManager.default.createDirectory(at: project.appendingPathComponent("frames"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: project.appendingPathComponent("logs"), withIntermediateDirectories: true)
                _ = try await run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-i", videoURL.path,
                    "-vf", "fps=4,scale=1280:-2",
                    "-q:v", "3", project.appendingPathComponent("frames/frame-%05d.jpg").path],
                    stage: "抽帧", project: project)
                frameCount = (try? FileManager.default.contentsOfDirectory(atPath: project.appendingPathComponent("frames").path).count) ?? 0
                guard frameCount >= 12 else { throw PipelineError.message("有效帧不足 12 张。请缓慢移动镜头，拍摄更长的卧室视频。") }
                status = "已抽取 \(frameCount) 帧，正在匹配画面特征…"
                let db = project.appendingPathComponent("database.db").path
                let images = project.appendingPathComponent("frames").path
                _ = try await run("colmap", ["feature_extractor", "--database_path", db, "--image_path", images,
                    "--ImageReader.single_camera", "1", "--FeatureExtraction.use_gpu", "0"],
                    stage: "特征提取", project: project)
                let matcher = frameCount <= 40 ? "exhaustive_matcher" : "sequential_matcher"
                status = frameCount <= 40 ? "正在匹配所有画面组合…" : "正在匹配相邻画面…"
                _ = try await run("colmap", [matcher, "--database_path", db,
                    "--FeatureMatching.use_gpu", "0"], stage: "画面匹配", project: project)
                status = "正在恢复相机轨迹和 3D 点…"
                let sparse = project.appendingPathComponent("sparse")
                try FileManager.default.createDirectory(at: sparse, withIntermediateDirectories: true)
                _ = try await run("colmap", ["mapper", "--database_path", db, "--image_path", images,
                    "--output_path", sparse.path], stage: "空间重建", project: project)
                let candidates = try FileManager.default.contentsOfDirectory(at: sparse, includingPropertiesForKeys: [.isDirectoryKey])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                guard !candidates.isEmpty else {
                    throw PipelineError.message("未能恢复空间。请围绕场景缓慢移动，保持画面重叠，并避免纯旋转拍摄。")
                }
                var bestModel: URL?
                var bestPoints = 0
                var bestRegistered = 0
                for candidate in candidates {
                    let analysis = try await run("colmap", ["model_analyzer", "--path", candidate.path],
                        stage: "分析模型-\(candidate.lastPathComponent)", project: project)
                    let points = Self.pointCount(in: analysis)
                    let registered = Self.registeredImageCount(in: analysis)
                    if registered > bestRegistered || (registered == bestRegistered && points > bestPoints) {
                        bestRegistered = registered
                        bestPoints = points
                        bestModel = candidate
                    }
                }
                guard let model = bestModel else { throw PipelineError.message("重建结果没有有效 3D 点。请拍摄更长的视频并增加平移视差。") }
                let ply = project.appendingPathComponent("scene.ply")
                _ = try await run("colmap", ["model_converter", "--input_path", model.path,
                    "--output_path", ply.path, "--output_type", "PLY"], stage: "导出点云", project: project)
                cloudURL = ply
                var surfaceNote = ""
                if bestPoints >= 300 && bestRegistered >= 5 {
                    status = "正在生成粗略表面预览…"
                    let mesh = project.appendingPathComponent("scene-mesh.ply")
                    do {
                        _ = try await run("colmap", ["delaunay_mesher", "--input_path", model.path,
                            "--input_type", "sparse", "--output_path", mesh.path],
                            stage: "粗略表面", project: project)
                        if try PointCloud(url: mesh).faces.isEmpty {
                            surfaceNote = "粗略表面为空，仅显示点云。"
                        } else {
                            meshURL = mesh
                            showMesh = true
                            surfaceNote = "已生成粗略表面预览；它不是完整的卧室网格。"
                        }
                    } catch {
                        surfaceNote = "粗略表面生成失败，仍可查看点云。详情见任务日志。"
                    }
                }
                let quality = bestPoints < 3000 || bestRegistered < max(8, frameCount / 2)
                    ? "重建数据偏少（\(bestRegistered)/\(frameCount) 帧、\(bestPoints) 点），空间会有缺口。建议拍摄更长视频并缓慢绕行。"
                    : "重建完成：\(bestRegistered)/\(frameCount) 帧、\(bestPoints) 个 3D 点。"
                status = "\(quality) \(surfaceNote)"
            } catch { status = "重建失败：\(error.localizedDescription)" }
            isRunning = false
        }
    }

    private func run(_ command: String, _ args: [String], stage: String, project: URL) async throws -> String {
        status = command == "ffmpeg" ? "正在从视频抽帧…" : status
        let executable = try findExecutable(command)
        let log = project.appendingPathComponent("logs/\(stage).log")
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            let output = Pipe()
            process.standardError = output
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try data.write(to: log, options: .atomic)
            let text = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                let tail = text.split(separator: "\n").suffix(5).joined(separator: "\n")
                throw PipelineError.message("\(stage)失败（\(command) 退出码 \(process.terminationStatus)）：\(tail)\n完整日志：\(log.path)")
            }
            return text
        }.value
    }

    nonisolated static func pointCount(in analysis: String) -> Int {
        count(after: "Points:", in: analysis)
    }

    nonisolated static func registeredImageCount(in analysis: String) -> Int {
        count(after: "Registered images:", in: analysis)
    }

    private nonisolated static func count(after label: String, in analysis: String) -> Int {
        guard let line = analysis.split(separator: "\n").first(where: { $0.contains(label) }),
              let value = line.components(separatedBy: label).last?.trimmingCharacters(in: .whitespaces),
              let count = Int(value) else { return 0 }
        return count
    }

    private func findExecutable(_ name: String) throws -> URL {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        if let path = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return path }
        throw PipelineError.message("找不到 \(name)。请先安装：brew install \(name)")
    }
}

enum PipelineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
