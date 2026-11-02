import Foundation
import CoreGraphics

/// Maps annotation page coordinates to the scan's original, unrotated meter coordinates.
struct FloorPlanAnnotationGeometry: Codable, Equatable {
    let worldBounds: CGRect
    let pointsPerMeter: CGFloat
    let margin: CGFloat

    init(worldBounds: CGRect, pointsPerMeter: CGFloat = 100, margin: CGFloat = 50) {
        self.worldBounds = worldBounds
        self.pointsPerMeter = pointsPerMeter
        self.margin = margin
    }

    var pageBounds: CGRect {
        CGRect(x: 0, y: 0,
               width: max(worldBounds.width * pointsPerMeter + margin * 2, 1),
               height: max(worldBounds.height * pointsPerMeter + margin * 2, 1))
    }
    var worldToPage: CGAffineTransform {
        CGAffineTransform(a: pointsPerMeter, b: 0, c: 0, d: -pointsPerMeter,
                          tx: margin - worldBounds.minX * pointsPerMeter,
                          ty: margin + worldBounds.maxY * pointsPerMeter)
    }

    func pageToView(rotationRadians: CGFloat, worldToView: CGAffineTransform) -> CGAffineTransform {
        worldToPage.inverted()
            .concatenating(CGAffineTransform(rotationAngle: rotationRadians))
            .concatenating(worldToView)
    }

    func displayedWorldBounds(rotationRadians: CGFloat) -> CGRect {
        pageBounds.applying(pageToView(rotationRadians: rotationRadians, worldToView: .identity))
    }

    func includingPageBounds(_ bounds: CGRect) -> Self {
        guard !bounds.isNull, !pageBounds.contains(bounds) else { return self }
        let expanded = pageBounds.union(bounds)
        return Self(worldBounds: expanded.applying(worldToPage.inverted()), pointsPerMeter: pointsPerMeter, margin: 0)
    }
}

struct FloorPlanAnnotationDocument: Codable, Equatable {
    var version = 1
    let geometry: FloorPlanAnnotationGeometry
    let markupData: Data
    let previewPNG: Data
}

struct FloorPlanAnnotationStore {
    let scanFolder: URL
    private var url: URL { scanFolder.appendingPathComponent("annotations.json") }

    func load() throws -> FloorPlanAnnotationDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let document = try JSONDecoder().decode(FloorPlanAnnotationDocument.self, from: Data(contentsOf: url))
        guard document.version == 1,
              document.geometry.pointsPerMeter.isFinite, document.geometry.pointsPerMeter > 0,
              document.geometry.margin.isFinite, document.geometry.margin >= 0,
              document.geometry.worldBounds.width.isFinite, document.geometry.worldBounds.width > 0,
              document.geometry.worldBounds.height.isFinite, document.geometry.worldBounds.height > 0,
              document.geometry.worldBounds.minX.isFinite, document.geometry.worldBounds.minY.isFinite else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }
    func save(_ document: FloorPlanAnnotationDocument) throws {
        // The scan owns the folder. Do not recreate a deleted scan from a lingering editor.
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
    }
}
