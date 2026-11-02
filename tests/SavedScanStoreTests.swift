import Foundation
import AppKit

/// Uses the production store with a native macOS image adapter, in a temporary library.
@main
struct SavedScanStoreTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roomy-library-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SavedScansStore(rootURL: folder)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(FloorPlanExportData.self, from: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/synthetic-connected-rooms.json")))
        let image = NSImage(size: CGSize(width: 1, height: 1))
        image.addRepresentation(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!)
        let first = try store.saveScan(title: "First", exportData: payload, thumbnail: image)
        let persistedCreatedAt = store.loadIndex().first!.createdAt
        let second = try store.saveScan(title: "Second", exportData: payload, thumbnail: image)
        precondition(store.loadIndex().map(\.id) == [second.id, first.id], "Autosaves must appear newest first")
        precondition(store.loadThumbnail(for: first.id) != nil, "Saved thumbnail must reopen")
        let raw = Data("raw capture sentinel".utf8)
        try raw.write(to: store.roomJSONURL(for: first.id))
        try store.acceptPhotoSuggestion(id: first.id, draft: RoomPhotoSuggestionDraft(title: "Living area", roomDescription: "A reviewed description."))
        try store.updateScan(id: first.id, exportData: payload, thumbnail: image)
        try store.renameScan(id: first.id, to: "Renamed")
        let reopened = SavedScansStore(rootURL: folder)
        let record = reopened.loadIndex().first { $0.id == first.id }!
        precondition(record.title == "Renamed" && record.roomDescription == "A reviewed description.", "Plan updates and manual rename must preserve accepted descriptions")
        precondition(record.createdAt == persistedCreatedAt && record.totalArea == 18, "Updates must preserve the persisted creation date and measured area")
        precondition(reopened.loadFloorPlanExport(for: first.id)?.walls.first?.length == 4, "Saved plan must retain its reference wall")
        let retainedRaw = try Data(contentsOf: reopened.roomJSONURL(for: first.id))
        precondition(retainedRaw == raw, "Metadata and plan updates must preserve raw capture files")
        try reopened.deleteScan(id: first.id)
        precondition(!FileManager.default.fileExists(atPath: reopened.scanFolderURL(for: first.id).path), "Delete must remove the scan folder and its attachments")
        precondition(reopened.loadIndex().map(\.id) == [second.id], "Delete must retain other library records")
        precondition(reopened.loadFloorPlanExport(for: second.id)?.totalArea == 18, "Deleting one scan must leave others readable")
        print("PASS: actual library save/reopen/update/rename/delete, thumbnails, descriptions and raw-file preservation")
    }
}
