/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Persists saved scans to disk and loads them for review.
*/

import Foundation
import UIKit

struct SavedScanRecord: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let title: String
    let totalArea: Double

    var subtitle: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return "\(dateFormatter.string(from: createdAt)) • \(formatArea(totalArea))"
    }

    private func formatArea(_ area: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.decimalSeparator = ","
        let value = formatter.string(from: NSNumber(value: area)) ?? String(format: "%.1f", area)
        return "\(value) m²"
    }
}

struct SavedScansStore {
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SavedScans", isDirectory: true)
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

    func loadIndex() -> [SavedScanRecord] {
        guard let data = try? Data(contentsOf: indexURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SavedScanRecord].self, from: data)) ?? []
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
        try exportDataPayload.write(to: exportDataURL)

        let thumbnailURL = scanURL.appendingPathComponent("thumbnail.png")
        if let thumbnailData = thumbnail.pngData() {
            try thumbnailData.write(to: thumbnailURL)
        }

        var index = loadIndex()
        index.insert(record, at: 0)
        let indexPayload = try encoder.encode(index)
        try indexPayload.write(to: indexURL)

        return record
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
