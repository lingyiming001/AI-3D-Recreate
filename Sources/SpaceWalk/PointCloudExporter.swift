import Foundation
import SceneKit

enum PointCloudFormat: String, CaseIterable, Identifiable, Sendable {
    case ply = "PLY"
    case obj = "OBJ"
    case glb = "GLB"
    case xyz = "XYZ"
    case pcd = "PCD"

    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
    var detail: String {
        switch self {
        case .ply: "彩色点云原始格式"
        case .obj: "顶点颜色扩展；部分软件可能忽略颜色"
        case .glb: "glTF 2.0 点图元，保留颜色"
        case .xyz: "XYZRGB 文本点云"
        case .pcd: "PCL ASCII 点云"
        }
    }
}

enum PointCloudExporter {
    static func export(source: URL, destination: URL, format: PointCloudFormat) throws {
        if format == .ply {
            if source.standardizedFileURL != destination.standardizedFileURL {
                try Data(contentsOf: source).write(to: destination, options: .atomic)
            }
            return
        }
        let cloud = try PointCloud(url: source)
        switch format {
        case .ply: break
        case .obj: try writeText(destination, lines: objLines(cloud))
        case .xyz: try writeText(destination, lines: xyzLines(cloud))
        case .pcd: try writeText(destination, lines: pcdLines(cloud))
        case .glb: try writeGLB(cloud, to: destination)
        }
    }

    private static func writeText(_ url: URL, lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func objLines(_ cloud: PointCloud) -> [String] {
        let header = cloud.faces.isEmpty ? "# SpaceWalk point cloud" : "# SpaceWalk coarse triangle mesh"
        let vertexLines = zip(cloud.vertices, cloud.colors).map { p, c in
            "v \(p.x) \(p.y) \(p.z) \(Double(c.x) / 255) \(Double(c.y) / 255) \(Double(c.z) / 255)"
        }
        let faceLines = cloud.faces.flatMap { row in
            (1..<(row.count - 1)).map { "f \(row[0] + 1) \(row[$0] + 1) \(row[$0 + 1] + 1)" }
        }
        return [header, "o SpaceWalk"] + vertexLines + faceLines
    }

    private static func xyzLines(_ cloud: PointCloud) -> [String] {
        zip(cloud.vertices, cloud.colors).map { p, c in
            "\(p.x) \(p.y) \(p.z) \(c.x) \(c.y) \(c.z)"
        }
    }

    private static func pcdLines(_ cloud: PointCloud) -> [String] {
        let count = cloud.vertices.count
        return ["# .PCD v0.7 - Point Cloud Data file format", "VERSION 0.7",
                "FIELDS x y z r g b", "SIZE 4 4 4 1 1 1", "TYPE F F F U U U",
                "COUNT 1 1 1 1 1 1", "WIDTH \(count)", "HEIGHT 1", "VIEWPOINT 0 0 0 1 0 0 0",
                "POINTS \(count)", "DATA ascii"] + xyzLines(cloud)
    }

    private static func writeGLB(_ cloud: PointCloud, to url: URL) throws {
        var binary = Data()
        var minimum = [Double.infinity, Double.infinity, Double.infinity]
        var maximum = [-Double.infinity, -Double.infinity, -Double.infinity]
        for p in cloud.vertices {
            let values = [Float(p.x), Float(p.y), Float(p.z)]
            for i in 0..<3 {
                minimum[i] = min(minimum[i], Double(values[i]))
                maximum[i] = max(maximum[i], Double(values[i]))
                appendLE(values[i].bitPattern, to: &binary)
            }
        }
        let positionLength = binary.count
        for c in cloud.colors { binary.append(contentsOf: [c.x, c.y, c.z, 255]) }
        let colorLength = cloud.colors.count * 4
        let indices = cloud.faces.flatMap { row in
            (1..<(row.count - 1)).flatMap { [row[0], row[$0], row[$0 + 1]] }
        }
        let indexOffset = binary.count
        for index in indices { appendLE(index, to: &binary) }
        pad(&binary, byte: 0)
        var primitive: [String: Any] = ["attributes": ["POSITION": 0, "COLOR_0": 1],
                                        "mode": indices.isEmpty ? 0 : 4]
        var bufferViews: [[String: Any]] = [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength, "target": 34962],
            ["buffer": 0, "byteOffset": positionLength, "byteLength": colorLength, "target": 34962]
        ]
        var accessors: [[String: Any]] = [
            ["bufferView": 0, "componentType": 5126, "count": cloud.vertices.count,
             "type": "VEC3", "min": minimum, "max": maximum],
            ["bufferView": 1, "componentType": 5121, "count": cloud.colors.count,
             "type": "VEC4", "normalized": true]
        ]
        if !indices.isEmpty {
            primitive["indices"] = 2
            bufferViews.append(["buffer": 0, "byteOffset": indexOffset, "byteLength": indices.count * 4, "target": 34963])
            accessors.append(["bufferView": 2, "componentType": 5125, "count": indices.count, "type": "SCALAR"])
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "SpaceWalk"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [["primitives": [primitive]]],
            "buffers": [["byteLength": binary.count]],
            "bufferViews": bufferViews,
            "accessors": accessors
        ]
        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        pad(&jsonData, byte: 0x20)
        var glb = Data()
        appendLE(UInt32(0x46546C67), to: &glb)
        appendLE(UInt32(2), to: &glb)
        appendLE(UInt32(12 + 8 + jsonData.count + 8 + binary.count), to: &glb)
        appendLE(UInt32(jsonData.count), to: &glb)
        appendLE(UInt32(0x4E4F534A), to: &glb)
        glb.append(jsonData)
        appendLE(UInt32(binary.count), to: &glb)
        appendLE(UInt32(0x004E4942), to: &glb)
        glb.append(binary)
        try glb.write(to: url, options: .atomic)
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xff) })
    }
    private static func pad(_ data: inout Data, byte: UInt8) {
        while data.count % 4 != 0 { data.append(byte) }
    }
}
