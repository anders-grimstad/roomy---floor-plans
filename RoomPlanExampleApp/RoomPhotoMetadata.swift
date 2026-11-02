import Foundation

struct SavedScanRecord: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let title: String
    let totalArea: Double
    let roomDescription: String?

    init(id: String, createdAt: Date, title: String, totalArea: Double, roomDescription: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.totalArea = totalArea
        self.roomDescription = roomDescription
    }

    var subtitle: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.decimalSeparator = ","
        let area = numberFormatter.string(from: NSNumber(value: totalArea)) ?? String(format: "%.1f", totalArea)
        return "\(dateFormatter.string(from: createdAt)) • \(area) m²"
    }
}

struct RoomPhotoSuggestionDraft: Equatable {
    var title: String
    var roomDescription: String
}

enum RoomPhotoMetadataError: LocalizedError {
    case emptyTitle
    case scanNotFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Give the scan a name before saving."
        case .scanNotFound: return "This scan is no longer in the library."
        }
    }
}

/// The library index stores descriptive metadata, independently of measured geometry.
struct RoomPhotoMetadataIndex {
    let url: URL

    func load() throws -> [SavedScanRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SavedScanRecord].self, from: Data(contentsOf: url))
    }

    func write(_ records: [SavedScanRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: url, options: .atomic)
    }

    func rename(id: String, title: String) throws {
        var records = try load()
        guard let position = records.firstIndex(where: { $0.id == id }) else { throw RoomPhotoMetadataError.scanNotFound }
        let record = records[position]
        records[position] = SavedScanRecord(id: record.id, createdAt: record.createdAt, title: title,
                                           totalArea: record.totalArea, roomDescription: record.roomDescription)
        try write(records)
    }

    /// Called only after the user reviews and explicitly accepts the editable draft.
    func accept(id: String, draft: RoomPhotoSuggestionDraft) throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.roomDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RoomPhotoMetadataError.emptyTitle }
        var records = try load()
        guard let position = records.firstIndex(where: { $0.id == id }) else { throw RoomPhotoMetadataError.scanNotFound }
        let record = records[position]
        records[position] = SavedScanRecord(id: record.id, createdAt: record.createdAt, title: title,
                                           totalArea: record.totalArea, roomDescription: description.isEmpty ? nil : description)
        try write(records)
    }
}
