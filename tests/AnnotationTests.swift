import Foundation
import CoreGraphics

@main
struct AnnotationTests {
    static func main() throws {
        let geometry = FloorPlanAnnotationGeometry(worldBounds: CGRect(x: -2, y: -1, width: 4, height: 3))
        try expect(geometry.pageBounds == CGRect(x: 0, y: 0, width: 500, height: 400), "annotation page must contain plan plus fixed margins")
        try point(CGPoint(x: -2, y: -1).applying(geometry.worldToPage), equals: CGPoint(x: 50, y: 350), "lower scan corner maps to bottom-left page margin")
        try point(CGPoint(x: 2, y: 2).applying(geometry.worldToPage), equals: CGPoint(x: 450, y: 50), "upper scan corner maps to top-right page margin")

        // Hand-computed: raw (-1,0) is page (150,250); clockwise 90° is world (0,1).
        // Current view maps (0,1) to (200,220).
        let worldToView = CGAffineTransform(a: 80, b: 0, c: 0, d: -80, tx: 200, ty: 300)
        let northUp = geometry.pageToView(rotationRadians: -.pi / 2, worldToView: worldToView)
        try point(CGPoint(x: 150, y: 250).applying(northUp), equals: CGPoint(x: 200, y: 220), "annotation follows the same north rotation as scan geometry")
        let original = CGPoint(x: 275, y: 125)
        try point(original.applying(northUp).applying(northUp.inverted()), equals: original, "editing-view coordinates return to canonical page without drift")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roomy-annotations-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let measuredGeometry = Data("original floorplan bytes".utf8)
        try measuredGeometry.write(to: folder.appendingPathComponent("floorplan.json"))
        let store = FloorPlanAnnotationStore(scanFolder: folder)
        try expect(try store.load() == nil, "legacy scan without annotations opens normally")
        let document = FloorPlanAnnotationDocument(geometry: geometry, markupData: Data([1, 4, 9]), previewPNG: Data([137, 80, 78, 71]))
        try store.save(document)
        try expect(try FloorPlanAnnotationStore(scanFolder: folder).load() == document, "save and reopen preserve native markup, preview and coordinate system")
        try expect(try Data(contentsOf: folder.appendingPathComponent("floorplan.json")) == measuredGeometry, "annotation saves do not modify measured geometry")
        try Data("broken".utf8).write(to: folder.appendingPathComponent("annotations.json"))
        do {
            _ = try store.load()
            throw CheckFailure(message: "corrupt annotation data must report failure instead of appearing empty")
        } catch is DecodingError { }
        print("PASS: annotation mapping, orientation, legacy opening, persistence, geometry isolation, corruption reporting")
    }

    struct CheckFailure: Error { let message: String }
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw CheckFailure(message: message) }
    }
    static func point(_ actual: CGPoint, equals expected: CGPoint, _ message: String) throws {
        try expect(abs(actual.x - expected.x) < 0.000001 && abs(actual.y - expected.y) < 0.000001, message)
    }
}
