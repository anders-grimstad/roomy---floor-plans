import Foundation
import CoreGraphics
import PaperKit
import ImageIO
import PencilKit
import AppKit

/// Native PaperKit rendering fixture; the geometry is synthetic, not a captured room.
@main
struct AnnotationRendering {
    static func main() async throws {
        guard #available(macOS 27.0, *) else { throw CocoaError(.featureUnsupported) }
        let geometry = FloorPlanAnnotationGeometry(worldBounds: CGRect(x: 0, y: 0, width: 4, height: 3))
        var markup = PaperMarkup(bounds: geometry.pageBounds)
        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = CGColor(srgbRed: 0, green: 0.3, blue: 1, alpha: 1)
        markup.subelements.append(ShapeMarkup(shape: .rectangle, frame: CGRect(x: 70, y: 80, width: 60, height: 40), fillColor: red))
        let originalArrow = ShapeMarkup(shape: .line(start: .zero, end: CGPoint(x: 1, y: 1)), frame: CGRect(x: 180, y: 100, width: 120, height: 100), strokeColor: blue, lineWidth: 5, endLineMarker: .arrow)
        markup.subelements.append(originalArrow)
        markup.insertNewTextbox(attributedText: NSAttributedString(string: "Room notes", attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.systemPurple]), frame: CGRect(x: 60, y: 270, width: 140, height: 40))
        let points = [CGPoint(x: 240, y: 270), CGPoint(x: 320, y: 320)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .systemGreen), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        markup.append(contentsOf: PKDrawing(strokes: [stroke]))
        let bytes = try await markup.dataRepresentation()
        let reopened = try PaperMarkup(dataRepresentation: bytes)
        try expect(reopened.subelements.count == 4, "native save/reopen preserves drawing, text, rectangle and arrow")
        let png = try await FloorPlanAnnotationRasterizer.png(markup: reopened)
        let output = URL(fileURLWithPath: "/tmp/roomy-annotation-preview.png")
        try png.write(to: output)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.coderInvalidValue) }
        try expect(image.width == 1000 && image.height == 800, "preview preserves canonical page size at 2x")
        // The red rectangle is near the upper-left; the lower-left must remain transparent.
        try expect(redPixel(image, x: 200, y: 200), "native annotation preview is not vertically flipped")
        try expect(!redPixel(image, x: 200, y: 600), "lower-left must not contain the upper-left annotation")

        var northUp = reopened
        let rotatedGeometry = FloorPlanAnnotationGeometry(worldBounds: CGRect(x: 0, y: -4, width: 3, height: 4))
        FloorPlanAnnotationTransform.apply(geometry.pageToView(rotationRadians: -.pi / 2, worldToView: rotatedGeometry.worldToPage), to: &northUp)
        northUp.bounds = rotatedGeometry.pageBounds
        let arrow = northUp.subelements[originalArrow.id]!
        try expect(abs(arrow.rotation - .pi / 2) < 0.000001, "north-up must rotate arrow direction, not only its bounding rectangle")
        var restored = northUp
        FloorPlanAnnotationTransform.apply(geometry.pageToView(rotationRadians: -.pi / 2, worldToView: rotatedGeometry.worldToPage).inverted(), to: &restored)
        let restoredArrow = restored.subelements[originalArrow.id]!
        try expect(abs(restoredArrow.frame.minX - originalArrow.frame.minX) < 0.000001 && abs(restoredArrow.frame.minY - originalArrow.frame.minY) < 0.000001 && abs(restoredArrow.rotation - originalArrow.rotation) < 0.000001, "saving an oriented editor returns annotation positions and rotations to raw coordinates")
        try await FloorPlanAnnotationRasterizer.png(markup: northUp).write(to: URL(fileURLWithPath: "/tmp/roomy-annotation-north-up.png"))

        var mediaBox = rotatedGeometry.pageBounds
        guard let pdf = CGContext(URL(fileURLWithPath: "/tmp/roomy-annotation-north-up.pdf") as CFURL, mediaBox: &mediaBox, nil) else { throw CocoaError(.coderInvalidValue) }
        pdf.beginPDFPage(nil)
        pdf.translateBy(x: 0, y: mediaBox.height)
        pdf.scaleBy(x: 1, y: -1)
        await northUp.draw(in: pdf, frame: mediaBox)
        pdf.endPDFPage()
        pdf.closePDF()
        print("PASS: native PaperKit save/reopen, upper-left marker raster orientation, raw/north-up PNG and PDF generation")
        print(output.path)
    }

    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func redPixel(_ image: CGImage, x: Int, y: Int) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 4)
        return bytes.withUnsafeMutableBytes { data in
            guard let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return data[0] > 200 && data[1] < 50 && data[2] < 50 && data[3] > 200
        }
    }
}
