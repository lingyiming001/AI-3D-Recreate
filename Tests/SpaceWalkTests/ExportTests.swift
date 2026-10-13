import XCTest
@testable import SpaceWalk

final class ExportTests: XCTestCase {
    func testBinaryPLYFromCOLMAP() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("binary.ply")
        var data = Data("""
        ply
        format binary_little_endian 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """.utf8)
        for value in [Float(1), 2, 3] {
            let bits = value.bitPattern
            data.append(contentsOf: (0..<4).map { UInt8((bits >> ($0 * 8)) & 0xff) })
        }
        data.append(contentsOf: [12, 34, 56])
        try data.write(to: url)
        let cloud = try PointCloud(url: url)
        XCTAssertEqual(cloud.vertices.count, 1)
        XCTAssertEqual(cloud.vertices[0].x, 1)
        XCTAssertEqual(cloud.colors[0].y, 34)
    }

    func testCOLMAPAnalysisPointCount() {
        let output = "I20261013 model.cc:440] Registered images: 10\nI20261013 model.cc:442] Points: 676\n"
        XCTAssertEqual(Reconstruction.pointCount(in: output), 676)
        XCTAssertEqual(Reconstruction.registeredImageCount(in: output), 10)
        XCTAssertEqual(Reconstruction.pointCount(in: "no model"), 0)
    }

    func testBinaryTriangleMesh() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("mesh.ply")
        var data = Data("""
        ply
        format binary_little_endian 1.0
        element vertex 3
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_index
        end_header

        """.utf8)
        for value in [Float(0), 0, 0, 1, 0, 0, 0, 1, 0] {
            let bits = value.bitPattern
            data.append(contentsOf: (0..<4).map { UInt8((bits >> ($0 * 8)) & 0xff) })
        }
        data.append(3)
        for index in [UInt32(0), 1, 2] {
            data.append(contentsOf: (0..<4).map { UInt8((index >> ($0 * 8)) & 0xff) })
        }
        try data.write(to: url)
        let mesh = try PointCloud(url: url)
        XCTAssertEqual(mesh.faces, [[0, 1, 2]])
        XCTAssertEqual(mesh.node.geometry?.elements.first?.primitiveType, .triangles)
        let obj = folder.appendingPathComponent("mesh.obj")
        try PointCloudExporter.export(source: url, destination: obj, format: .obj)
        XCTAssertTrue(try String(contentsOf: obj, encoding: .utf8).contains("f 1 2 3"))
        let glb = folder.appendingPathComponent("mesh.glb")
        try PointCloudExporter.export(source: url, destination: glb, format: .glb)
        let bytes = [UInt8](try Data(contentsOf: glb))
        let length = Int(UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20..<(20 + length)])) as? [String: Any])
        let meshes = try XCTUnwrap(json["meshes"] as? [[String: Any]])
        let primitives = try XCTUnwrap(meshes[0]["primitives"] as? [[String: Any]])
        XCTAssertEqual(primitives[0]["mode"] as? Int, 4)
        XCTAssertEqual(primitives[0]["indices"] as? Int, 2)
    }

    func testFormatsKeepPointCountAndColor() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("input.ply")
        try """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        0 0 0 255 0 0
        1 2 3 0 255 0

        """.write(to: source, atomically: true, encoding: .utf8)

        let obj = folder.appendingPathComponent("scene.obj")
        try PointCloudExporter.export(source: source, destination: obj, format: .obj)
        let objText = try String(contentsOf: obj, encoding: .utf8)
        XCTAssertEqual(objText.split(separator: "\n").filter { $0.hasPrefix("v ") }.count, 2)
        XCTAssertTrue(objText.contains("v 0.0 0.0 0.0 1.0 0.0 0.0"))

        let pcd = folder.appendingPathComponent("scene.pcd")
        try PointCloudExporter.export(source: source, destination: pcd, format: .pcd)
        let pcdText = try String(contentsOf: pcd, encoding: .utf8)
        XCTAssertTrue(pcdText.contains("POINTS 2\nDATA ascii"))
        XCTAssertTrue(pcdText.contains("1.0 2.0 3.0 0 255 0"))

        let glb = folder.appendingPathComponent("scene.glb")
        try PointCloudExporter.export(source: source, destination: glb, format: .glb)
        let bytes = [UInt8](try Data(contentsOf: glb))
        XCTAssertEqual(Array(bytes.prefix(4)), [0x67, 0x6c, 0x54, 0x46])
        let jsonLength = Int(UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20..<(20 + jsonLength)])) as? [String: Any])
        let meshes = try XCTUnwrap(json["meshes"] as? [[String: Any]])
        let primitives = try XCTUnwrap(meshes[0]["primitives"] as? [[String: Any]])
        XCTAssertEqual(primitives[0]["mode"] as? Int, 0)
        let accessors = try XCTUnwrap(json["accessors"] as? [[String: Any]])
        XCTAssertEqual(accessors[0]["count"] as? Int, 2)
    }
}
