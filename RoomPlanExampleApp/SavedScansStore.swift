/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Persists saved scans to disk and loads them for review.
*/

import Foundation
import UIKit

struct SavedScansStore {
    private let fileManager = FileManager.default

    private let rootURL: URL

    init(rootURL: URL? = nil) {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? base.appendingPathComponent("SavedScans", isDirectory: true)
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json")
    }

    func scanFolderURL(for scanId: String) -> URL {
        rootURL.appendingPathComponent(scanId, isDirectory: true)
    }

    func roomUSDZURL(for scanId: String) -> URL {
        scanFolderURL(for: scanId).appendingPathComponent("room.usdz")
    }

    func roomJSONURL(for scanId: String) -> URL {
        scanFolderURL(for: scanId).appendingPathComponent("room.json")
    }

    func hasUSDZ(for scanId: String) -> Bool {
        fileManager.fileExists(atPath: roomUSDZURL(for: scanId).path)
    }

    func loadIndex() -> [SavedScanRecord] {
        (try? RoomPhotoMetadataIndex(url: indexURL).load()) ?? []
    }

    func saveScan(
        title: String,
        exportData: FloorPlanExportData,
        thumbnail: UIImage
    ) throws -> SavedScanRecord {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scanId = UUID().uuidString
        let scanURL = scanFolderURL(for: scanId)
        try fileManager.createDirectory(at: scanURL, withIntermediateDirectories: true)

        let record = SavedScanRecord(
            id: scanId,
            createdAt: Date(),
            title: title,
            totalArea: exportData.totalArea
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportDataURL = scanURL.appendingPathComponent("floorplan.json")
        let exportDataPayload = try encoder.encode(exportData)
        try exportDataPayload.write(to: exportDataURL, options: .atomic)

        let thumbnailURL = scanURL.appendingPathComponent("thumbnail.png")
        if let thumbnailData = thumbnail.pngData() {
            try thumbnailData.write(to: thumbnailURL)
        }

        var index = loadIndex()
        index.insert(record, at: 0)
        try writeIndex(index)

        return record
    }

    func updateScan(id: String, exportData: FloorPlanExportData, thumbnail: UIImage) throws {
        let scanURL = scanFolderURL(for: id)
        guard fileManager.fileExists(atPath: scanURL.path) else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportDataURL = scanURL.appendingPathComponent("floorplan.json")
        try encoder.encode(exportData).write(to: exportDataURL, options: .atomic)

        if let thumbnailData = thumbnail.pngData() {
            try thumbnailData.write(to: scanURL.appendingPathComponent("thumbnail.png"))
        }

        var index = loadIndex()
        if let position = index.firstIndex(where: { $0.id == id }) {
            let old = index[position]
            index[position] = SavedScanRecord(
                id: old.id,
                createdAt: old.createdAt,
                title: old.title,
                totalArea: exportData.totalArea,
                roomDescription: old.roomDescription
            )
            try writeIndex(index)
        }
    }

    func renameScan(id: String, to title: String) throws {
        try RoomPhotoMetadataIndex(url: indexURL).rename(id: id, title: title)
    }

    func acceptPhotoSuggestion(id: String, draft: RoomPhotoSuggestionDraft) throws {
        try RoomPhotoMetadataIndex(url: indexURL).accept(id: id, draft: draft)
    }

    func deleteScan(id: String) throws {
        let folder = scanFolderURL(for: id)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        var index = loadIndex()
        index.removeAll { $0.id == id }
        try writeIndex(index)
    }

    private func writeIndex(_ index: [SavedScanRecord]) throws {
        try RoomPhotoMetadataIndex(url: indexURL).write(index)
    }

    func loadFloorPlanExport(for scanId: String) -> FloorPlanExportData? {
        let exportURL = rootURL.appendingPathComponent(scanId).appendingPathComponent("floorplan.json")
        guard let data = try? Data(contentsOf: exportURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FloorPlanExportData.self, from: data)
    }

    func loadThumbnail(for scanId: String) -> UIImage? {
        let thumbnailURL = rootURL.appendingPathComponent(scanId).appendingPathComponent("thumbnail.png")
        return UIImage(contentsOfFile: thumbnailURL.path)
    }
}
