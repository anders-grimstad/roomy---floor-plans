import Foundation
import CoreGraphics
import PaperKit
import ImageIO
import UniformTypeIdentifiers

@available(iOS 27.0, macOS 27.0, *)
enum FloorPlanAnnotationTransform {
    @MainActor
    static func document(from editorMarkup: PaperMarkup, geometry: FloorPlanAnnotationGeometry,
                         canonicalToEditor: CGAffineTransform) async throws -> FloorPlanAnnotationDocument {
        var markup = editorMarkup
        apply(canonicalToEditor.inverted(), to: &markup)
        var contentBounds = CGRect.null
        for element in markup.subelements {
            let frame = element.frame
            let rotation = CGAffineTransform(translationX: -frame.midX, y: -frame.midY)
                .concatenating(CGAffineTransform(rotationAngle: element.rotation))
                .concatenating(CGAffineTransform(translationX: frame.midX, y: frame.midY))
            let padding = (element as? ShapeMarkup).map { $0.lineWidth / 2 } ?? 0
            contentBounds = contentBounds.union(frame.applying(rotation).insetBy(dx: -padding, dy: -padding))
        }
        let savedGeometry = geometry.includingPageBounds(contentBounds)
        if savedGeometry != geometry {
            apply(geometry.pageToView(rotationRadians: 0, worldToView: savedGeometry.worldToPage), to: &markup)
        }
        markup.bounds = savedGeometry.pageBounds
        return FloorPlanAnnotationDocument(geometry: savedGeometry, markupData: try await markup.dataRepresentation(),
            previewPNG: try await FloorPlanAnnotationRasterizer.png(markup: markup))
    }

    static func apply(_ transform: CGAffineTransform, to markup: inout PaperMarkup) {
        // Page changes are rigid rotations and translations. Mapping bounding boxes
        // alone loses arrow direction and distorts non-square text and shapes.
        let angle = atan2(transform.b, transform.a)
        var elements = markup.subelements
        for var element in elements {
            let frame = element.frame
            let center = CGPoint(x: frame.midX, y: frame.midY).applying(transform)
            element.frame = CGRect(x: center.x - frame.width / 2, y: center.y - frame.height / 2,
                                   width: frame.width, height: frame.height)
            element.rotation += angle
            elements.updateOrAppend(element)
        }
        markup.subelements = elements
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum FloorPlanAnnotationRasterizer {
    static func png(markup: PaperMarkup) async throws -> Data {
        let size = markup.bounds.size
        let scale = min(2, 4096 / max(size.width, size.height))
        let width = max(1, Int(ceil(size.width * scale)))
        let height = max(1, Int(ceil(size.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        await markup.draw(in: context, frame: CGRect(origin: .zero, size: size))
        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.coderInvalidValue) }
        return output as Data
    }
}
