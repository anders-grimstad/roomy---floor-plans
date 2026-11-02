import Foundation
import CoreGraphics
import PaperKit
import ImageIO

@main
struct AnnotationBoundarySave {
    @MainActor
    static func main() async throws {
        let geometry = FloorPlanAnnotationGeometry(worldBounds: CGRect(x: -0.5, y: -0.5, width: 5, height: 4))
        // The old 45-degree editor allowed this note outside the fixed canonical page.
        let editor = FloorPlanAnnotationGeometry(worldBounds: CGRect(x: -0.5, y: -3.32842712474619, width: 5.94974746830583, height: 5.94974746830583))
        let transform = geometry.pageToView(rotationRadians: -.pi / 4, worldToView: editor.worldToPage)
        var markup = PaperMarkup(bounds: editor.pageBounds)
        let note = ShapeMarkup(shape: .rectangle, frame: CGRect(x: 80, y: 80, width: 20, height: 20),
            fillColor: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        markup.subelements.append(note)
        var document = try await FloorPlanAnnotationTransform.document(from: markup, geometry: geometry, canonicalToEditor: transform)
        let angles: [CGFloat] = [.pi / 4, -.pi / 3, 0]
        for angle in angles {
            let reopened = try PaperMarkup(dataRepresentation: document.markupData)
            let element = reopened.subelements[note.id]!
            let world = CGPoint(x: element.frame.midX, y: element.frame.midY).applying(document.geometry.worldToPage.inverted())
            guard abs(world.x - -1.64142135623731) < 0.00001, abs(world.y - 1.5) < 0.00001 else {
                throw NSError(domain: "AnnotationBoundary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saving or reopening moved the corner note in measured world coordinates"])
            }
            guard document.geometry.displayedWorldBounds(rotationRadians: 0).contains(world),
                  let source = CGImageSourceCreateWithData(document.previewPNG as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.coderInvalidValue) }
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let count = pixels.withUnsafeMutableBytes { bytes -> Int in
                let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] > 200 && bytes[$0 + 1] < 80 && bytes[$0 + 2] < 80 && bytes[$0 + 3] > 150 }.count
            }
            guard count > 100 else { throw CocoaError(.coderInvalidValue) }
            let nextEditor = FloorPlanAnnotationGeometry(worldBounds: document.geometry.displayedWorldBounds(rotationRadians: angle), pointsPerMeter: document.geometry.pointsPerMeter, margin: 0)
            let nextTransform = document.geometry.pageToView(rotationRadians: angle, worldToView: nextEditor.worldToPage)
            var editing = reopened
            FloorPlanAnnotationTransform.apply(nextTransform, to: &editing)
            editing.bounds = nextEditor.pageBounds
            document = try await FloorPlanAnnotationTransform.document(from: editing, geometry: document.geometry, canonicalToEditor: nextTransform)
        }
        print("PASS: angled-editor corner note survives native save/reopen and repeated orientation changes without world-coordinate drift")
    }
}
