/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view that renders a 2D floor plan using Canvas.
Updated to match conversionscript.py rendering style.
*/

import SwiftUI
import RoomPlan
import UIKit

// MARK: - Floor Plan Color Scheme

struct FloorPlanColors {
    let background = Color(hex: "1A1A2E")
    let floor = Color(hex: "16213E")
    let wall = Color(hex: "E8E8E8")
    let wallStroke = Color(hex: "111111")
    let door = Color(hex: "2E8B57")       // SeaGreen matching Python
    let doorSwing = Color(hex: "2E8B57").opacity(0.3)
    let window = Color(hex: "00AEEF")     // Cyan matching Python
    let furniture = Color(hex: "FF6B6B").opacity(0.25)
    let furnitureStroke = Color(hex: "FF6B6B")
    let furnitureLabel = Color(hex: "AA2E2E")
    let dimension = Color(hex: "888888")
    let dimensionText = Color(hex: "AAAAAA")
    let gridLine = Color(hex: "2A2A4A")
    let areaText = Color(hex: "2E8B57")   // SeaGreen matching Python
    let sectionLabel = Color(hex: "666666")
    let roomLabel = Color(hex: "333333")
    let outline = Color(hex: "888888")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Floor Plan View

struct FloorPlanView: View {
    let floorPlanData: FloorPlanData
    let retakeTitle: String
    let onRetake: () -> Void
    let onSave: () -> Void
    let onExport: () -> Void
    let colors = FloorPlanColors()
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    
    @State private var showDimensions: Bool = false
    @State private var showFurniture: Bool = true
    @State private var showGrid: Bool = false
    @State private var showLabels: Bool = true
    @State private var show3D: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                colors.background.ignoresSafeArea()
                
                // Floor plan canvas
                Canvas { context, size in
                    let transform = calculateTransform(size: size)
                    
                    if showGrid {
                        drawGrid(context: context, size: size, transform: transform)
                    }
                    
                    drawFloors(context: context, transform: transform)
                    drawOutlines(context: context, transform: transform)
                    drawWalls(context: context, transform: transform)
                    drawWindows(context: context, transform: transform)
                    drawDoors(context: context, transform: transform)
                    
                    if showFurniture {
                        drawObjects(context: context, transform: transform)
                    }
                    
                    if showLabels {
                        drawSectionLabels(context: context, transform: transform)
                    }
                    
                    if showDimensions {
                        drawDimensions(context: context, transform: transform)
                    }
                }
                .scaleEffect(scale)
                .offset(CGSize(
                    width: offset.width + dragTranslation.width,
                    height: offset.height + dragTranslation.height
                ))
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            offset = CGSize(
                                width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height
                            )
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                            }
                        }
                )
                
                headerOverlay
                zoomControlsOverlay
                viewOptionsDockOverlay
            }
        }
    }
    
    // MARK: - Transform Calculation
    
    private func calculateTransform(size: CGSize) -> CGAffineTransform {
        let bounds = floorPlanData.bounds
        guard bounds.width > 0 && bounds.height > 0 else {
            return .identity
        }
        
        let padding: CGFloat = 60
        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2
        
        let scaleX = availableWidth / bounds.width
        let scaleY = availableHeight / bounds.height
        let fitScale = min(scaleX, scaleY)
        
        // Center the floor plan
        let scaledWidth = bounds.width * fitScale
        let scaledHeight = bounds.height * fitScale
        let left = (size.width - scaledWidth) / 2
        let top = (size.height - scaledHeight) / 2
        
        // Match conversionscript.py / SVGExporter mapping:
        //   x_px = (x - minX) * scale + left
        //   y_px = (maxY - y) * scale + top
        //
        // This is equivalent to:
        //   x_px = x * scale + (left - minX * scale)
        //   y_px = y * (-scale) + (top + maxY * scale)
        let tx = left - bounds.minX * fitScale
        let ty = top + bounds.maxY * fitScale
        
        // Build explicit affine transform to avoid scaling the translation component by accident.
        return CGAffineTransform(a: fitScale, b: 0, c: 0, d: -fitScale, tx: tx, ty: ty)
    }
    
    // MARK: - Drawing Methods
    
    private func drawGrid(context: GraphicsContext, size: CGSize, transform: CGAffineTransform) {
        let bounds = floorPlanData.bounds
        let gridSpacing: CGFloat = 1.0 // 1 meter grid
        
        var gridPath = Path()
        
        // Vertical lines
        var x = floor(bounds.minX)
        while x <= ceil(bounds.maxX) {
            let start = CGPoint(x: x, y: bounds.minY).applying(transform)
            let end = CGPoint(x: x, y: bounds.maxY).applying(transform)
            gridPath.move(to: start)
            gridPath.addLine(to: end)
            x += gridSpacing
        }
        
        // Horizontal lines
        var y = floor(bounds.minY)
        while y <= ceil(bounds.maxY) {
            let start = CGPoint(x: bounds.minX, y: y).applying(transform)
            let end = CGPoint(x: bounds.maxX, y: y).applying(transform)
            gridPath.move(to: start)
            gridPath.addLine(to: end)
            y += gridSpacing
        }
        
        context.stroke(gridPath, with: .color(colors.gridLine), lineWidth: 0.5)
    }
    
    private func drawFloors(context: GraphicsContext, transform: CGAffineTransform) {
        // Draw all floor outlines filled
        for floorOutline in floorPlanData.floorOutlines {
            guard !floorOutline.outline.isEmpty else { continue }
            
            var floorPath = Path()
            let firstPoint = floorOutline.outline[0].cgPoint.applying(transform)
            floorPath.move(to: firstPoint)
            
            for point in floorOutline.outline.dropFirst() {
                floorPath.addLine(to: point.cgPoint.applying(transform))
            }
            floorPath.closeSubpath()
            
            context.fill(floorPath, with: .color(colors.floor))
        }
    }
    
    private func drawOutlines(context: GraphicsContext, transform: CGAffineTransform) {
        // Draw floor outline strokes (thin lines, matching Python's outline style)
        for floorOutline in floorPlanData.floorOutlines {
            guard floorOutline.outline.count >= 2 else { continue }
            
            var outlinePath = Path()
            let firstPoint = floorOutline.outline[0].cgPoint.applying(transform)
            outlinePath.move(to: firstPoint)
            
            for point in floorOutline.outline.dropFirst() {
                outlinePath.addLine(to: point.cgPoint.applying(transform))
            }
            outlinePath.closeSubpath()
            
            context.stroke(
                outlinePath,
                with: .color(colors.outline),
                style: StrokeStyle(lineWidth: 2, lineCap: .square)
            )
        }
    }
    
    private func drawWalls(context: GraphicsContext, transform: CGAffineTransform) {
        // Wall thickness: ~6cm in meters scaled to pixels
        let wallPixelWidth = max(2.0, abs(transform.a) * 0.06)
        
        for wall in floorPlanData.walls {
            let start = wall.start.cgPoint.applying(transform)
            let end = wall.end.cgPoint.applying(transform)
            
            var wallPath = Path()
            wallPath.move(to: start)
            wallPath.addLine(to: end)
            
            context.stroke(
                wallPath,
                with: .color(colors.wallStroke),
                style: StrokeStyle(lineWidth: wallPixelWidth, lineCap: .square, lineJoin: .miter)
            )
        }
    }
    
    private func drawDoors(context: GraphicsContext, transform: CGAffineTransform) {
        let wallPixelWidth = max(2.0, abs(transform.a) * 0.06)
        
        for door in floorPlanData.doors {
            // Use pre-calculated start/end points
            let start = door.start.cgPoint.applying(transform)
            let end = door.end.cgPoint.applying(transform)
            
            // Draw gap in wall (background color to "erase" wall)
            var gapPath = Path()
            gapPath.move(to: start)
            gapPath.addLine(to: end)
            context.stroke(
                gapPath,
                with: .color(colors.background),
                style: StrokeStyle(lineWidth: wallPixelWidth + 2, lineCap: .square)
            )
            
            // Draw door line
            var doorPath = Path()
            doorPath.move(to: start)
            doorPath.addLine(to: end)
            context.stroke(
                doorPath,
                with: .color(colors.door),
                style: StrokeStyle(lineWidth: max(2.0, wallPixelWidth * 0.6), lineCap: .square)
            )
            
            // Draw door swing arc
            let dx = end.x - start.x
            let dy = end.y - start.y
            let doorLength = sqrt(dx * dx + dy * dy)
            let doorAngle = atan2(dy, dx)
            
            var arcPath = Path()
            arcPath.addArc(
                center: start,
                radius: doorLength * 0.9,
                startAngle: Angle(radians: doorAngle),
                endAngle: Angle(radians: doorAngle + .pi / 2),
                clockwise: false
            )
            context.stroke(
                arcPath,
                with: .color(colors.doorSwing),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            
            // Draw door leaf
            let leafEnd = CGPoint(
                x: start.x + cos(doorAngle + .pi / 4) * doorLength * 0.9,
                y: start.y + sin(doorAngle + .pi / 4) * doorLength * 0.9
            )
            var leafPath = Path()
            leafPath.move(to: start)
            leafPath.addLine(to: leafEnd)
            context.stroke(leafPath, with: .color(colors.door), lineWidth: 2)
        }
    }
    
    private func drawWindows(context: GraphicsContext, transform: CGAffineTransform) {
        let wallPixelWidth = max(2.0, abs(transform.a) * 0.06)
        
        for window in floorPlanData.windows {
            // Use pre-calculated start/end points
            let start = window.start.cgPoint.applying(transform)
            let end = window.end.cgPoint.applying(transform)
            
            // Draw gap in wall
            var gapPath = Path()
            gapPath.move(to: start)
            gapPath.addLine(to: end)
            context.stroke(
                gapPath,
                with: .color(colors.background),
                style: StrokeStyle(lineWidth: wallPixelWidth + 2, lineCap: .square)
            )
            
            // Draw window (triple line effect for glass appearance)
            var windowPath = Path()
            windowPath.move(to: start)
            windowPath.addLine(to: end)
            
            let windowWidth = max(2.0, wallPixelWidth * 0.7)
            context.stroke(windowPath, with: .color(colors.window), lineWidth: windowWidth)
            context.stroke(windowPath, with: .color(colors.background), lineWidth: windowWidth * 0.5)
            context.stroke(windowPath, with: .color(colors.window), lineWidth: 1)
        }
    }
    
    private func drawObjects(context: GraphicsContext, transform: CGAffineTransform) {
        for object in floorPlanData.objects {
            let center = object.position.cgPoint.applying(transform)
            let scale = abs(transform.a)
            let scaledWidth = max(4.0, object.width * scale)
            let scaledDepth = max(4.0, object.depth * scale)
            
            // Draw rotated rectangle for furniture
            var objectContext = context
            objectContext.translateBy(x: center.x, y: center.y)
            // Negate angle because we flip Y in coordinate transform
            objectContext.rotate(by: Angle(radians: -object.angle))
            
            let rect = CGRect(
                x: -scaledWidth / 2,
                y: -scaledDepth / 2,
                width: scaledWidth,
                height: scaledDepth
            )
            
            let objectPath = Path(roundedRect: rect, cornerRadius: 4)
            objectContext.fill(objectPath, with: .color(colors.furniture))
            objectContext.stroke(objectPath, with: .color(colors.furnitureStroke), lineWidth: 1)
            
            // Draw emoji icon for the object
            let emoji = Text(object.category.emoji)
                .font(.system(size: min(scaledWidth, scaledDepth) * 0.4))
            objectContext.draw(emoji, at: .zero)
        }
    }
    
    private func drawSectionLabels(context: GraphicsContext, transform: CGAffineTransform) {
        for section in floorPlanData.sections {
            let center = section.center.cgPoint.applying(transform)
            
            let label = Text(section.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.sectionLabel)
            
            context.draw(label, at: center, anchor: .center)
        }
        
        // If no sections, draw room labels with area for each floor outline
        if floorPlanData.sections.isEmpty {
            for (index, outline) in floorPlanData.floorOutlines.enumerated() {
                let centroid = outline.centroid.cgPoint.applying(transform)
                
                let roomLabel = Text("Room \(index + 1)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.wall)
                
                let areaLabel = Text(String(format: "%.1f m²", outline.area))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.areaText)
                
                context.draw(roomLabel, at: CGPoint(x: centroid.x, y: centroid.y - 10), anchor: .center)
                context.draw(areaLabel, at: CGPoint(x: centroid.x, y: centroid.y + 10), anchor: .center)
            }
        }
    }
    
    private func drawDimensions(context: GraphicsContext, transform: CGAffineTransform) {
        for dimension in floorPlanData.dimensions {
            let start = dimension.start.cgPoint.applying(transform)
            let end = dimension.end.cgPoint.applying(transform)
            
            // Calculate perpendicular offset
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = sqrt(dx * dx + dy * dy)
            guard length > 0 else { continue }
            
            let perpX = -dy / length * 15
            let perpY = dx / length * 15
            
            let offsetStart = CGPoint(x: start.x + perpX, y: start.y + perpY)
            let offsetEnd = CGPoint(x: end.x + perpX, y: end.y + perpY)
            let midPoint = CGPoint(x: (offsetStart.x + offsetEnd.x) / 2, y: (offsetStart.y + offsetEnd.y) / 2)
            
            // Draw dimension line
            var dimPath = Path()
            dimPath.move(to: offsetStart)
            dimPath.addLine(to: offsetEnd)
            context.stroke(dimPath, with: .color(colors.dimension), style: StrokeStyle(lineWidth: 1))
            
            // Draw end ticks
            let tickLength: CGFloat = 6
            let tickPerpX = -perpX / 15 * tickLength
            let tickPerpY = -perpY / 15 * tickLength
            
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: offsetStart.x - tickPerpX, y: offsetStart.y - tickPerpY))
            tickPath.addLine(to: CGPoint(x: offsetStart.x + tickPerpX, y: offsetStart.y + tickPerpY))
            tickPath.move(to: CGPoint(x: offsetEnd.x - tickPerpX, y: offsetEnd.y - tickPerpY))
            tickPath.addLine(to: CGPoint(x: offsetEnd.x + tickPerpX, y: offsetEnd.y + tickPerpY))
            context.stroke(tickPath, with: .color(colors.dimension), lineWidth: 1)
            
            // Draw label
            let label = Text(dimension.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(colors.dimensionText)
            
            context.draw(label, at: midPoint, anchor: .center)
        }
    }
    
    // MARK: - UI Components
    
    private var headerOverlay: some View {
        VStack(spacing: 12) {
            HStack {
                CapsuleButton(title: retakeTitle) {
                    onRetake()
                }
                Spacer()
                Text("Floor Plan")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                CapsuleButton(title: "Save") {
                    onSave()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            
            AreaPill(area: floorPlanData.totalArea)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var zoomControlsOverlay: some View {
        VStack(spacing: 10) {
            ZoomButton(symbol: "plus") {
                let newScale = min(scale * 1.2, 5.0)
                withAnimation(.spring()) {
                    scale = newScale
                }
            }
            ZoomButton(symbol: "minus") {
                let newScale = max(scale / 1.2, 0.5)
                withAnimation(.spring()) {
                    scale = newScale
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, 228)
    }
    
    private var viewOptionsDockOverlay: some View {
        VStack(spacing: 14) {
            Text("VIEW OPTIONS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(Color.white.opacity(0.7))
            
            HStack(spacing: 16) {
                OptionToggleButton(
                    systemImage: "sofa",
                    isOn: $showFurniture
                )
                OptionToggleButton(
                    text: "Aa",
                    isOn: $showLabels
                )
                OptionToggleButton(
                    systemImage: "ruler",
                    isOn: $showDimensions
                )
                OptionToggleButton(
                    systemImage: "cube.transparent",
                    isOn: $show3D
                )
            }
            
            Button {
                onExport()
            } label: {
                Label("Export floor plan", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "6D7BFF"))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}

// MARK: - Controls

private struct CapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
            Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
            .buttonStyle(.plain)
    }
}

private struct AreaPill: View {
    let area: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.resize")
                .font(.system(size: 13, weight: .semibold))
            Text(formatArea(area))
                .font(.system(size: 16, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func formatArea(_ value: CGFloat) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.decimalSeparator = ","
        let number = formatter.string(from: NSNumber(value: Double(value))) ?? String(format: "%.1f", Double(value))
        return "\(number) m²"
    }
}

private struct ZoomButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OptionToggleButton: View {
    let systemImage: String?
    let text: String?
    @Binding var isOn: Bool

    @State private var isPressed = false
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    init(systemImage: String, isOn: Binding<Bool>) {
        self.systemImage = systemImage
        self.text = nil
        self._isOn = isOn
    }

    init(text: String, isOn: Binding<Bool>) {
        self.systemImage = nil
        self.text = text
        self._isOn = isOn
    }

    var body: some View {
        let gradient = LinearGradient(
            colors: [Color(hex: "5B5CFF"), Color(hex: "7A5CFF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let background = isOn ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.white.opacity(0.1))
        let foreground = isOn ? Color.white : Color.white.opacity(0.6)

        return ZStack {
            Circle()
                .fill(background)
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(foreground)
            } else if let text = text {
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(foreground)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.interpolatingSpring(stiffness: 260, damping: 16), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        feedback.prepare()
                        feedback.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    isOn.toggle()
                }
        )
    }
}

// MARK: - Preview

struct FloorPlanView_Previews: PreviewProvider {
    static var previews: some View {
        // Create sample data for preview
        let sampleOutline = [
            FloorPlanPoint(0, 0),
            FloorPlanPoint(5, 0),
            FloorPlanPoint(5, 4),
            FloorPlanPoint(0, 4)
        ]
        
        let sampleFloorOutline = FloorPlanOutline(
            id: UUID(),
            outline: sampleOutline,
            story: 0,
            area: 20
        )
        
        let sampleData = FloorPlanData(
            floorOutlines: [sampleFloorOutline],
            walls: [],
            doors: [
                FloorPlanDoor(
                    id: UUID(),
                    start: FloorPlanPoint(2.0, 0),
                    end: FloorPlanPoint(3.0, 0),
                    width: 0.9,
                    angle: 0,
                    isOpen: false,
                    parentWallId: nil
                )
            ],
            windows: [
                FloorPlanWindow(
                    id: UUID(),
                    start: FloorPlanPoint(5, 1.5),
                    end: FloorPlanPoint(5, 2.5),
                    width: 1.2,
                    angle: .pi / 2,
                    parentWallId: nil
                )
            ],
            objects: [
                FloorPlanObject(
                    id: UUID(),
                    position: FloorPlanPoint(2.5, 2),
                    width: 2.0,
                    depth: 1.0,
                    angle: 0,
                    category: .sofa,
                    label: "Sofa"
                )
            ],
            sections: [],
            dimensions: [],
            bounds: CGRect(x: -0.5, y: -0.5, width: 6, height: 5),
            totalArea: 20
        )
        
        FloorPlanView(
            floorPlanData: sampleData,
            retakeTitle: "Retake",
            onRetake: {},
            onSave: {},
            onExport: {}
        )
    }
}
