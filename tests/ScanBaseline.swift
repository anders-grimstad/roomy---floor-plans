import Foundation

// Synthetic geometry with hand-checked dimensions; this is not a LiDAR capture.
@main
struct ScanBaseline {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(FloorPlanExportData.self, from: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/synthetic-connected-rooms.json")))
        let plan = payload.toFloorPlanData()
        check(plan.floorOutlines.count == 2, "both room outlines survive loading")
        check(plan.totalArea == 18, "connected rooms retain their hand-measured 18 m² area")
        check(plan.bounds == CGRect(x: -0.5, y: -0.5, width: 7, height: 4), "six by three metre plan retains its half-metre display margin")
        check(plan.floorOutlines.map(\.story) == [0, 0], "same-storey room metadata survives loading")

        let alignment = ScanNorthAlignment(roomToNorthYawDegrees: 90, reference: .trueNorth, accuracyDegrees: 5,
            calibratedAt: Date(timeIntervalSince1970: 0), calibrationMethod: "synthetic", sampleCount: 6, spreadDegrees: 1)
        let north = plan.oriented(northAlignment: alignment, sourceIsNorthUpNormalized: false, desiredNorthUp: true)
        near(north.walls[0].end.x, 0, "north-up rotates wall end x clockwise")
        near(north.walls[0].end.y, -4, "north-up rotates wall end y clockwise")
        near(north.bounds.width, 4, "north-up swaps padded plan width")
        near(north.bounds.height, 7, "north-up swaps padded plan height")
        check(north.totalArea == 18 && north.walls[0].length == 4, "rotation preserves area and wall length")

        let encoded = FloorPlanExportData(from: north, northAlignment: alignment, isNorthUpNormalized: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reopened = try decoder.decode(FloorPlanExportData.self, from: encoder.encode(encoded)).toFloorPlanData()
        let raw = reopened.oriented(northAlignment: alignment, sourceIsNorthUpNormalized: true, desiredNorthUp: false)
        near(raw.walls[0].end.x, 4, "save/reopen/north-off restores original x")
        near(raw.walls[0].end.y, 0, "save/reopen/north-off restores original y")
        check(raw.floorOutlines.map(\.id) == plan.floorOutlines.map(\.id), "save/reopen preserves room identities")
        check(raw.objects.first?.label == "Table", "save/reopen preserves furniture labels")
        let unchanged = reopened.oriented(northAlignment: alignment, sourceIsNorthUpNormalized: true, desiredNorthUp: true)
        near(unchanged.walls[0].end.y, -4, "reopening a north-up scan does not rotate it twice")

        let svg = SVGExporter().export(plan)
        let parser = XMLParser(data: Data(svg.utf8))
        check(parser.parse(), "SVG export is valid XML")
        check(svg.contains("Kitchen") && svg.contains("Living room"), "SVG includes both room section labels")

        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/synthetic-connected-rooms.json"))) as! [String: Any]
        legacy.removeValue(forKey: "isNorthUpNormalized")
        legacy.removeValue(forKey: "northAlignment")
        let old = try decoder.decode(FloorPlanExportData.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(old.isNorthUpNormalized == nil && old.toFloorPlanData().totalArea == 18, "legacy exports without north metadata remain readable")
        print("PASS: scan geometry, orientation, reopening, compatibility and SVG checks (synthetic export fixture)")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    static func near(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        check(abs(actual - expected) < 0.00001, "\(message): got \(actual), expected \(expected)")
    }
}
