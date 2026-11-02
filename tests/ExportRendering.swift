import SwiftUI
import AppKit
import PaperKit
import CoreText
import PDFKit

/// Synthetic plan rendered through the production export view with macOS platform adapters.
@main
struct ExportRendering {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let font = URL(fileURLWithPath: "RoomPlanExampleApp/Silkscreen-Bold.ttf")
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(FloorPlanExportData.self, from: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/synthetic-connected-rooms.json"))).toFloorPlanData()
        let geometry = FloorPlanAnnotationGeometry(worldBounds: plan.bounds)
        var markup = PaperMarkup(bounds: geometry.pageBounds)
        markup.subelements.append(ShapeMarkup(shape: .rectangle, frame: CGRect(x: 200, y: 160, width: 100, height: 70),
            strokeColor: CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 1), lineWidth: 4))
        markup.subelements.append(ShapeMarkup(shape: .line(start: .zero, end: CGPoint(x: 1, y: 1)),
            frame: CGRect(x: 200, y: 240, width: 100, height: 80), strokeColor: CGColor(srgbRed: 0, green: 0.2, blue: 1, alpha: 1),
            lineWidth: 3, endLineMarker: .arrow))
        markup.insertNewTextbox(attributedText: NSAttributedString(string: "Keep clear", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.systemPurple]), frame: CGRect(x: 320, y: 220, width: 140, height: 40))
        let document = FloorPlanAnnotationDocument(geometry: geometry, markupData: try await markup.dataRepresentation(),
            previewPNG: try await FloorPlanAnnotationRasterizer.png(markup: markup))
        guard let preview = FloorPlanAnnotationPreview(document: document) else { throw CocoaError(.coderInvalidValue) }
        let alignment = ScanNorthAlignment(roomToNorthYawDegrees: 90, reference: .trueNorth, accuracyDegrees: 5,
            calibratedAt: Date(timeIntervalSince1970: 0), calibrationMethod: "synthetic", sampleCount: 6, spreadDegrees: 1)
        let folder = URL(fileURLWithPath: "/tmp/roomy-export-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for north in [false, true] {
            let name = north ? "north-up" : "raw"
            let displayed = plan.oriented(northAlignment: alignment, sourceIsNorthUpNormalized: false, desiredNorthUp: north)
            let view = FloorPlanExportView(floorPlanData: displayed, title: "Synthetic connected rooms · annotation QA",
                capturedAt: Date(timeIntervalSince1970: 1_793_318_400), annotationPreview: preview,
                annotationRotationRadians: north ? -.pi / 2 : 0)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.coderInvalidValue)
            }
            try png.write(to: folder.appendingPathComponent("\(name).png"))
            var wrotePDF = false
            renderer.render { size, draw in
                var bounds = CGRect(origin: .zero, size: size)
                guard let context = CGContext(folder.appendingPathComponent("\(name).pdf") as CFURL, mediaBox: &bounds, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
                wrotePDF = true
            }
            guard wrotePDF else { throw CocoaError(.fileWriteUnknown) }
            guard let pdf = PDFDocument(url: folder.appendingPathComponent("\(name).pdf")),
                  pdf.pageCount == 1, let page = pdf.page(at: 0),
                  let pdfPNG = page.thumbnail(of: CGSize(width: image.width, height: image.height), for: .mediaBox).tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: pdfPNG),
                  let pngFromPDF = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try pngFromPDF.write(to: folder.appendingPathComponent("\(name)-from-pdf.png"))
            print("PASS: actual export body produced \(name) PNG/PDF with native markup, \(image.width)×\(image.height)")
        }
        print(folder.path)
    }
}
