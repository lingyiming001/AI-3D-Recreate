import SwiftUI
import SceneKit

struct CloudView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> ExplorerView {
        let view = ExplorerView()
        view.backgroundColor = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.085, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.scene = SCNScene()
        view.rendersContinuously = true
        return view
    }

    func updateNSView(_ view: ExplorerView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.scene = SCNScene()
        guard let url else { return }
        do {
            let points = try PointCloud(url: url)
            view.scene?.rootNode.addChildNode(points.node)
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.zFar = 10000
            camera.position = SCNVector3(points.center.x, points.center.y, points.center.z + CGFloat(max(points.radius * 2.3, 1)))
            view.scene?.rootNode.addChildNode(camera)
            view.pointOfView = camera
        } catch {
            // Status is reflected by the parent when pipeline fails.
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedURL: URL? }
}

final class ExplorerView: SCNView {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        guard let camera = pointOfView else { return }
        let speed: Float = event.modifierFlags.contains(.shift) ? 0.5 : 0.12
        let t = camera.presentation.simdWorldTransform
        let right = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": camera.simdPosition += forward * speed
        case "s": camera.simdPosition -= forward * speed
        case "a": camera.simdPosition -= right * speed
        case "d": camera.simdPosition += right * speed
        case "q": camera.simdPosition.y -= speed
        case "e": camera.simdPosition.y += speed
        default: super.keyDown(with: event)
        }
    }
}

struct PointCloud {
    let node: SCNNode
    let center: SCNVector3
    let radius: Float
    let vertices: [SCNVector3]
    let colors: [SIMD4<UInt8>]
    let faces: [[UInt32]]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let end = data.range(of: Data("end_header\n".utf8)),
              let header = String(data: data[..<end.upperBound], encoding: .utf8) else {
            throw PipelineError.message("PLY 文件头无效")
        }
        let lines = header.components(separatedBy: .newlines)
        guard let vertexLine = lines.first(where: { $0.hasPrefix("element vertex ") }),
              let count = Int(vertexLine.split(separator: " ").last ?? "") else {
            throw PipelineError.message("PLY 缺少顶点")
        }
        let props = lines.drop(while: { !$0.hasPrefix("element vertex ") }).dropFirst()
            .prefix(while: { $0.hasPrefix("property ") })
            .map { $0.split(separator: " ").map(String.init) }
        let faceCount = lines.first(where: { $0.hasPrefix("element face ") })
            .flatMap { Int($0.split(separator: " ").last ?? "") } ?? 0
        let stride = props.reduce(0) { $0 + Self.size($1[1]) }
        let names = props.map { $0[2] }
        let offset = end.upperBound
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<UInt8>] = []
        vertices.reserveCapacity(count)
        colors.reserveCapacity(count)
        let bytes = [UInt8](data)
        let binary = header.contains("format binary_little_endian")
        var faceRows: [[UInt32]] = []
        if binary {
            guard stride > 0, offset + count * stride <= bytes.count else { throw PipelineError.message("PLY 数据不完整") }
            for i in 0..<count {
                var values: [String: Double] = [:]
                var p = offset + i * stride
                for prop in props {
                    values[prop[2]] = Self.read(bytes, at: p, type: prop[1])
                    p += Self.size(prop[1])
                }
                vertices.append(SCNVector3(Float(values["x"] ?? 0), Float(values["y"] ?? 0), Float(values["z"] ?? 0)))
                colors.append(SIMD4(UInt8(clamping: Int(values["red"] ?? 220)), UInt8(clamping: Int(values["green"] ?? 230)), UInt8(clamping: Int(values["blue"] ?? 245)), 255))
            }
            var p = offset + count * stride
            for _ in 0..<faceCount {
                guard p < bytes.count else { throw PipelineError.message("PLY 面数据不完整") }
                let n = Int(bytes[p]); p += 1
                guard n >= 3, n <= 64, p + n * 4 <= bytes.count else { throw PipelineError.message("PLY 面索引无效") }
                let row = (0..<n).map { j -> UInt32 in
                    let q = p + j * 4
                    return UInt32(bytes[q]) | UInt32(bytes[q+1]) << 8 | UInt32(bytes[q+2]) << 16 | UInt32(bytes[q+3]) << 24
                }
                p += n * 4
                faceRows.append(row)
            }
        } else {
            let body = String(decoding: data[offset...], as: UTF8.self)
            let bodyLines = body.split(separator: "\n")
            for line in bodyLines.prefix(count) {
                let values = line.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
                guard values.count >= names.count else { continue }
                let dict = Dictionary(uniqueKeysWithValues: zip(names, values))
                vertices.append(SCNVector3(Float(dict["x"] ?? 0), Float(dict["y"] ?? 0), Float(dict["z"] ?? 0)))
                colors.append(SIMD4(UInt8(clamping: Int(dict["red"] ?? 220)), UInt8(clamping: Int(dict["green"] ?? 230)), UInt8(clamping: Int(dict["blue"] ?? 245)), 255))
            }
            for line in bodyLines.dropFirst(count).prefix(faceCount) {
                let values = line.split(whereSeparator: \.isWhitespace).compactMap { UInt32($0) }
                guard let n = values.first, n >= 3, values.count > Int(n) else { throw PipelineError.message("PLY 面索引无效") }
                faceRows.append(Array(values[1...Int(n)]))
            }
        }
        guard !vertices.isEmpty else { throw PipelineError.message("点云为空") }
        guard faceRows.allSatisfy({ $0.allSatisfy { Int($0) < vertices.count } }) else {
            throw PipelineError.message("PLY 面索引超出顶点范围")
        }
        self.vertices = vertices
        self.colors = colors
        self.faces = faceRows
        let xs = vertices.map(\.x), ys = vertices.map(\.y), zs = vertices.map(\.z)
        let c = SCNVector3((xs.min()! + xs.max()!) / 2, (ys.min()! + ys.max()!) / 2, (zs.min()! + zs.max()!) / 2)
        center = c
        radius = Float(max(xs.max()! - xs.min()!, ys.max()! - ys.min()!, zs.max()! - zs.min()!) / 2)
        let packedVertices = vertices.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        let vertexData = packedVertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let positionSource = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 1, dataOffset: 0, dataStride: 4)
        let indices: [UInt32]
        let element: SCNGeometryElement
        if faceRows.isEmpty {
            indices = (0..<vertices.count).map(UInt32.init)
            element = SCNGeometryElement(data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
                primitiveType: .point, primitiveCount: indices.count, bytesPerIndex: 4)
            element.pointSize = 3
            element.minimumPointScreenSpaceRadius = 1
            element.maximumPointScreenSpaceRadius = 5
        } else {
            indices = faceRows.flatMap { row in (1..<(row.count - 1)).flatMap { [row[0], row[$0], row[$0 + 1]] } }
            element = SCNGeometryElement(data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
                primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4)
        }
        let geometry = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        geometry.firstMaterial?.lightingModel = faceRows.isEmpty ? .constant : .blinn
        geometry.firstMaterial?.isDoubleSided = true
        node = SCNNode(geometry: geometry)
    }

    private static func size(_ type: String) -> Int {
        switch type { case "char", "uchar", "int8", "uint8": 1; case "short", "ushort", "int16", "uint16": 2; case "double", "float64": 8; default: 4 }
    }
    private static func read(_ bytes: [UInt8], at p: Int, type: String) -> Double {
        func u32() -> UInt32 { UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24 }
        switch type {
        case "uchar", "uint8": return Double(bytes[p])
        case "char", "int8": return Double(Int8(bitPattern: bytes[p]))
        case "ushort", "uint16": return Double(UInt16(bytes[p]) | UInt16(bytes[p+1]) << 8)
        case "short", "int16": return Double(Int16(bitPattern: UInt16(bytes[p]) | UInt16(bytes[p+1]) << 8))
        case "float", "float32": return Double(Float(bitPattern: u32()))
        case "double", "float64":
            let bits = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[p+$1]) << ($1 * 8) }
            return Double(bitPattern: bits)
        default: return Double(Int32(bitPattern: u32()))
        }
    }
}
