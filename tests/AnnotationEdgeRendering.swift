import SwiftUI
import AppKit
import PaperKit

@main
struct AnnotationEdgeRendering {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(FloorPlanExportData.self, from: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/synthetic-connected-rooms.json"))).toFloorPlanData()
        let geometry = FloorPlanAnnotationGeometry(worldBounds: plan.bounds)
        var markup = PaperMarkup(bounds: geometry.pageBounds)
        markup.subelements.append(ShapeMarkup(shape: .rectangle, frame: CGRect(x: 5, y: 5, width: 10, height: 10),
            fillColor: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        let document = FloorPlanAnnotationDocument(geometry: geometry, markupData: try await markup.dataRepresentation(), previewPNG: try await FloorPlanAnnotationRasterizer.png(markup: markup))
        guard let preview = FloorPlanAnnotationPreview(document: document) else { throw CocoaError(.coderInvalidValue) }
        for degrees in [0.0, 45.0, 90.0] {
            let alignment = ScanNorthAlignment(roomToNorthYawDegrees: degrees, reference: .trueNorth, accuracyDegrees: 5,
                calibratedAt: Date(timeIntervalSince1970: 0), calibrationMethod: "synthetic", sampleCount: 6, spreadDegrees: 1)
            let displayed = plan.oriented(northAlignment: alignment, sourceIsNorthUpNormalized: false, desiredNorthUp: degrees != 0)
            let renderer = ImageRenderer(content: FloorPlanExportView(floorPlanData: displayed, title: "Annotation edge regression",
                capturedAt: Date(timeIntervalSince1970: 0), annotationPreview: preview, annotationRotationRadians: -CGFloat(degrees) * .pi / 180))
            guard let image = renderer.cgImage else { throw CocoaError(.coderInvalidValue) }
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: "/tmp/roomy-annotation-edge-\(Int(degrees)).png"))
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let redCount = pixels.withUnsafeMutableBytes { bytes -> Int in
                let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 200 && bytes[$0 + 1] < 80 && bytes[$0 + 2] < 80 && bytes[$0 + 3] > 150 }.count
            }
            guard redCount > 20 else {
                throw NSError(domain: "AnnotationEdge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Annotation inside the editable page was clipped at \(degrees)°: \(redCount) red pixels"])
            }
            print("PASS: page-corner annotation remains visible at \(degrees)° (\(redCount) red pixels)")
        }
    }
}
