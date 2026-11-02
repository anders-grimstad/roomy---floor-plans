import Foundation

@main
struct PhotoMetadataTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("index.json")
        let legacy = """
        [{"id":"scan-1","createdAt":"2026-06-12T12:00:00Z","title":"Original","totalArea":24.5}]
        """
        try Data(legacy.utf8).write(to: url)
        let index = RoomPhotoMetadataIndex(url: url)
        let before = try index.load()
        precondition(before.count == 1 && before[0].roomDescription == nil, "Old saved scans must decode without descriptions")
        // Preparing or editing a suggestion must never mutate saved metadata.
        let draft = RoomPhotoSuggestionDraft(title: " Kitchen ", roomDescription: " White cabinets. ")
        let unchangedData = try Data(contentsOf: url)
        precondition(unchangedData == Data(legacy.utf8), "Unaccepted suggestion must not change disk")
        try index.accept(id: "scan-1", draft: draft)
        let reopened = try RoomPhotoMetadataIndex(url: url).load()
        precondition(reopened[0].title == "Kitchen" && reopened[0].roomDescription == "White cabinets.", "Accepted edits must survive reopening")
        precondition(reopened[0].totalArea == 24.5 && reopened[0].createdAt == before[0].createdAt, "Accepting suggestions must preserve measured data and scan identity")
        try index.rename(id: "scan-1", title: "My kitchen")
        let renamed = try index.load()
        precondition(renamed[0].roomDescription == "White cabinets.", "Rename must preserve the accepted description")
        do {
            try index.accept(id: "scan-1", draft: RoomPhotoSuggestionDraft(title: "  ", roomDescription: "Discard"))
            fatalError("Empty titles must not overwrite saved metadata")
        } catch RoomPhotoMetadataError.emptyTitle { }
        let rejected = try index.load()
        precondition(rejected[0].title == "My kitchen", "Rejected edits must leave saved metadata intact")
        do {
            try index.accept(id: "missing", draft: draft)
            fatalError("Missing scans must not report successful acceptance")
        } catch RoomPhotoMetadataError.scanNotFound { }
        print("PASS: legacy compatibility, accepted persistence, draft isolation, rename preservation, validation, and measured-data preservation")
    }
}
