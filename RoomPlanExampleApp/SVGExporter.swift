/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SVG export functionality for floor plans.
Ported from conversionscript.py for consistent output.
*/

import Foundation
import CoreGraphics

/// Configuration for SVG export
struct SVGExportConfig {
    var pixelsPerMeter: CGFloat = 120.0
    var marginPx: CGFloat = 40.0
    var drawRoomLabels: Bool = true
    var drawAreaText: Bool = true
    var drawSectionLabels: Bool = true
    var drawObjects: Bool = true
    var drawObjectLabels: Bool = true
    var drawDimensions: Bool = false
    var backgroundColor: String = "#ffffff"
    var wallColor: String = "#111111"
    var outlineColor: String = "#888888"
    var doorColor: String = "#2E8B57"
    var windowColor: String = "#00AEEF"
    var objectFillColor: String = "#FF6B6B"
    var objectStrokeColor: String = "#FF6B6B"
    var labelColor: String = "#333333"
    var areaColor: String = "#2E8B57"
    var sectionLabelColor: String = "#666666"
    var dimensionColor: String = "#888888"
}

/// Generates SVG output from FloorPlanData
/// Matches the output style of conversionscript.py
class SVGExporter {
    
    private let config: SVGExportConfig
    
    init(config: SVGExportConfig = SVGExportConfig()) {
        self.config = config
    }
    
    /// Export floor plan data to SVG string
    func export(_ data: FloorPlanData, scanHeading: ScanHeading? = nil) -> String {
        let bounds = data.bounds
        guard bounds.width > 0 && bounds.height > 0 else {
            return createEmptySVG()
        }
        
        let ppm = config.pixelsPerMeter
        let margin = config.marginPx
        
        let viewWidth = bounds.width * ppm + margin * 2
        let viewHeight = bounds.height * ppm + margin * 2
        
        var elements: [String] = []
        
        // Header
        elements.append(svgHeader(width: viewWidth, height: viewHeight))
        
        // Background
        elements.append(svgRect(x: 0, y: 0, width: viewWidth, height: viewHeight, fill: config.backgroundColor))

        if let scanHeading {
            elements.append("<!-- Heading -->")
            let label = scanHeading.exportLabel
            let headingX = margin
            let headingY = margin * 0.6
            elements.append(svgTextAnchored(
                x: headingX,
                y: headingY,
                text: label,
                fontSize: 12,
                fill: config.labelColor,
                anchor: "start",
                baseline: "hanging"
            ))
        }
        
        // Floor outlines (thin strokes)
        elements.append("<!-- Floor Outlines -->")
        for outline in data.floorOutlines {
            guard !outline.outline.isEmpty else { continue }
            let points = outline.outline.map { toSVGSpace($0, bounds: bounds, ppm: ppm, margin: margin) }
            elements.append(svgPolyline(points: points, stroke: config.outlineColor, strokeWidth: 2.0, fill: "none", close: true))
        }
        
        // Walls (thick lines)
        elements.append("<!-- Walls -->")
        let wallWidth = max(2.0, ppm * 0.06)
        for wall in data.walls {
            let a = toSVGSpace(wall.start, bounds: bounds, ppm: ppm, margin: margin)
            let b = toSVGSpace(wall.end, bounds: bounds, ppm: ppm, margin: margin)
            elements.append(svgLine(x1: a.x, y1: a.y, x2: b.x, y2: b.y, stroke: config.wallColor, strokeWidth: wallWidth))
        }
        
        // Windows (cyan lines overlay)
        elements.append("<!-- Windows -->")
        let windowWidth = max(2.0, wallWidth * 0.7)
        for window in data.windows {
            let a = toSVGSpace(window.start, bounds: bounds, ppm: ppm, margin: margin)
            let b = toSVGSpace(window.end, bounds: bounds, ppm: ppm, margin: margin)
            elements.append(svgLine(x1: a.x, y1: a.y, x2: b.x, y2: b.y, stroke: config.windowColor, strokeWidth: windowWidth))
        }
        
        // Doors (green lines overlay)
        elements.append("<!-- Doors -->")
        let doorWidth = max(2.0, wallWidth * 0.6)
        for door in data.doors {
            let a = toSVGSpace(door.start, bounds: bounds, ppm: ppm, margin: margin)
            let b = toSVGSpace(door.end, bounds: bounds, ppm: ppm, margin: margin)
            elements.append(svgLine(x1: a.x, y1: a.y, x2: b.x, y2: b.y, stroke: config.doorColor, strokeWidth: doorWidth, opacity: 0.9))
        }
        
        // Objects/Furniture
        if config.drawObjects {
            elements.append("<!-- Objects -->")
            for obj in data.objects {
                let center = toSVGSpace(obj.position, bounds: bounds, ppm: ppm, margin: margin)
                let w = max(4.0, obj.width * ppm)
                let h = max(4.0, obj.depth * ppm)
                // Negate angle because SVG Y grows down
                let angleDeg = -obj.angle * 180.0 / .pi
                
                elements.append(svgRectRotated(
                    cx: center.x,
                    cy: center.y,
                    width: w,
                    height: h,
                    angleDeg: angleDeg,
                    fill: config.objectFillColor,
                    fillOpacity: 0.25,
                    stroke: config.objectStrokeColor,
                    strokeWidth: 1.0,
                    rx: 4.0
                ))
                
                if config.drawObjectLabels {
                    elements.append(svgTextAnchored(
                        x: center.x,
                        y: center.y,
                        text: obj.label,
                        fontSize: 10,
                        fill: "#AA2E2E"
                    ))
                }
            }
        }
        
        // Section labels
        if config.drawSectionLabels && !data.sections.isEmpty {
            elements.append("<!-- Section Labels -->")
            for section in data.sections {
                let pos = toSVGSpace(section.center, bounds: bounds, ppm: ppm, margin: margin)
                elements.append(svgTextAnchored(
                    x: pos.x,
                    y: pos.y,
                    text: section.label,
                    fontSize: 13,
                    fill: config.sectionLabelColor
                ))
            }
        }
        
        // Room labels (if no sections or always show)
        if config.drawRoomLabels && data.sections.isEmpty {
            elements.append("<!-- Room Labels -->")
            for (index, outline) in data.floorOutlines.enumerated() {
                let centroid = toSVGSpace(outline.centroid, bounds: bounds, ppm: ppm, margin: margin)
                
                let label = "Room \(index + 1)"
                elements.append(svgTextAnchored(
                    x: centroid.x,
                    y: centroid.y - (config.drawAreaText ? 10 : 0),
                    text: label,
                    fontSize: 16,
                    fill: config.labelColor
                ))
                
                if config.drawAreaText {
                    elements.append(svgTextAnchored(
                        x: centroid.x,
                        y: centroid.y + 10,
                        text: String(format: "%.1f m²", outline.area),
                        fontSize: 14,
                        fill: config.areaColor
                    ))
                }
            }
        }
        
        // Dimensions
        if config.drawDimensions {
            elements.append("<!-- Dimensions -->")
            for dimension in data.dimensions {
                let start = toSVGSpace(dimension.start, bounds: bounds, ppm: ppm, margin: margin)
                let end = toSVGSpace(dimension.end, bounds: bounds, ppm: ppm, margin: margin)
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                
                // Dimension line
                elements.append(svgLine(
                    x1: start.x, y1: start.y,
                    x2: end.x, y2: end.y,
                    stroke: config.dimensionColor,
                    strokeWidth: 1
                ))
                
                // Dimension label
                elements.append(svgTextAnchored(
                    x: mid.x,
                    y: mid.y - 5,
                    text: dimension.label,
                    fontSize: 10,
                    fill: config.dimensionColor
                ))
            }
        }
        
        // Footer
        elements.append(svgFooter())
        
        return elements.joined(separator: "\n")
    }
    
    /// Export to file at given URL
    func exportToFile(_ data: FloorPlanData, scanHeading: ScanHeading? = nil, url: URL) throws {
        let svgString = export(data, scanHeading: scanHeading)
        try svgString.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Coordinate Transformation
    
    /// Map floorplan meters to SVG pixels
    /// Flips Y so "up" in floor plan becomes "up" visually (SVG y grows down)
    private func toSVGSpace(_ point: FloorPlanPoint, bounds: CGRect, ppm: CGFloat, margin: CGFloat) -> CGPoint {
        let xPx = (point.x - bounds.minX) * ppm + margin
        let yPx = (bounds.maxY - point.y) * ppm + margin
        return CGPoint(x: xPx, y: yPx)
    }
    
    // MARK: - SVG Element Helpers
    
    private func svgHeader(width: CGFloat, height: CGFloat) -> String {
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(format(width))" height="\(format(height))" viewBox="0 0 \(format(width)) \(format(height))">
        """
    }
    
    private func svgFooter() -> String {
        return "</svg>"
    }
    
    private func svgRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fill: String) -> String {
        return """
        <rect x="\(format(x))" y="\(format(y))" width="\(format(width))" height="\(format(height))" fill="\(fill)" />
        """
    }
    
    private func svgLine(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, stroke: String, strokeWidth: CGFloat, opacity: CGFloat = 1.0) -> String {
        var attrs = """
        <line x1="\(format(x1))" y1="\(format(y1))" x2="\(format(x2))" y2="\(format(y2))" stroke="\(stroke)" stroke-width="\(format(strokeWidth))" stroke-linecap="square"
        """
        if opacity < 1.0 {
            attrs += " opacity=\"\(String(format: "%.3f", opacity))\""
        }
        attrs += " />"
        return attrs
    }
    
    private func svgPolyline(points: [CGPoint], stroke: String, strokeWidth: CGFloat, fill: String = "none", close: Bool = false) -> String {
        var pts = points
        if close && !pts.isEmpty {
            pts.append(pts[0])
        }
        let pointsStr = pts.map { "\(format($0.x)),\(format($0.y))" }.joined(separator: " ")
        return """
        <polyline points="\(pointsStr)" stroke="\(stroke)" fill="\(fill)" stroke-width="\(format(strokeWidth))" />
        """
    }
    
    private func svgTextAnchored(x: CGFloat, y: CGFloat, text: String, fontSize: CGFloat, fill: String, anchor: String = "middle", baseline: String = "middle") -> String {
        let safeText = escapeXML(text)
        return """
        <text x="\(format(x))" y="\(format(y))" text-anchor="\(anchor)" dominant-baseline="\(baseline)" font-family="Menlo, monospace" font-size="\(Int(fontSize))" fill="\(fill)">\(safeText)</text>
        """
    }
    
    private func svgRectRotated(cx: CGFloat, cy: CGFloat, width: CGFloat, height: CGFloat, angleDeg: CGFloat, fill: String, fillOpacity: CGFloat, stroke: String, strokeWidth: CGFloat, rx: CGFloat = 3.0) -> String {
        let x = -width / 2.0
        let y = -height / 2.0
        return """
        <g transform="translate(\(format(cx)) \(format(cy))) rotate(\(format(angleDeg)))"><rect x="\(format(x))" y="\(format(y))" width="\(format(width))" height="\(format(height))" rx="\(format(rx))" fill="\(fill)" fill-opacity="\(String(format: "%.3f", fillOpacity))" stroke="\(stroke)" stroke-width="\(format(strokeWidth))" /></g>
        """
    }
    
    private func createEmptySVG() -> String {
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
        <text x="50" y="50" text-anchor="middle" font-family="sans-serif" font-size="12">No data</text>
        </svg>
        """
    }
    
    // MARK: - Formatting Helpers
    
    private func format(_ value: CGFloat) -> String {
        return String(format: "%.2f", value)
    }
    
    private func escapeXML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

