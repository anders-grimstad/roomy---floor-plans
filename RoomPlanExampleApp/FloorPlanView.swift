/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view that renders a 2D floor plan using Canvas.
*/

import SwiftUI
import RoomPlan

// MARK: - Floor Plan Color Scheme

struct FloorPlanColors {
    let background = Color(hex: "1A1A2E")
    let floor = Color(hex: "16213E")
    let wall = Color(hex: "E8E8E8")
    let wallStroke = Color(hex: "CCCCCC")
    let door = Color(hex: "4ECCA3")
    let doorSwing = Color(hex: "4ECCA3").opacity(0.3)
    let window = Color(hex: "00D9FF")
    let furniture = Color(hex: "FF6B6B").opacity(0.6)
    let furnitureStroke = Color(hex: "FF6B6B")
    let dimension = Color(hex: "888888")
    let dimensionText = Color(hex: "AAAAAA")
    let gridLine = Color(hex: "2A2A4A")
    let areaText = Color(hex: "4ECCA3")
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
    let colors = FloorPlanColors()
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    @State private var showDimensions: Bool = true
    @State private var showFurniture: Bool = true
    @State private var showGrid: Bool = true
    
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
                    
                    drawFloor(context: context, transform: transform)
                    drawWalls(context: context, transform: transform)
                    drawWindows(context: context, transform: transform)
                    drawDoors(context: context, transform: transform)
                    
                    if showFurniture {
                        drawObjects(context: context, transform: transform)
                    }
                    
                    if showDimensions {
                        drawDimensions(context: context, transform: transform)
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
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
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                
                // Controls overlay
                VStack {
                    Spacer()
                    controlsBar
                        .padding(.bottom, 20)
                }
                
                // Area display
                VStack {
                    HStack {
                        Spacer()
                        areaDisplay
                            .padding(.top, 60)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
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
        let offsetX = (size.width - scaledWidth) / 2 - bounds.minX * fitScale
        let offsetY = (size.height - scaledHeight) / 2 - bounds.minY * fitScale
        
        return CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: fitScale, y: fitScale)
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
    
    private func drawFloor(context: GraphicsContext, transform: CGAffineTransform) {
        guard !floorPlanData.roomOutline.isEmpty else { return }
        
        var floorPath = Path()
        let firstPoint = floorPlanData.roomOutline[0].cgPoint.applying(transform)
        floorPath.move(to: firstPoint)
        
        for point in floorPlanData.roomOutline.dropFirst() {
            floorPath.addLine(to: point.cgPoint.applying(transform))
        }
        floorPath.closeSubpath()
        
        context.fill(floorPath, with: .color(colors.floor))
    }
    
    private func drawWalls(context: GraphicsContext, transform: CGAffineTransform) {
        // Draw walls from the room outline
        guard floorPlanData.roomOutline.count >= 2 else { return }
        
        let outline = floorPlanData.roomOutline
        let wallThickness: CGFloat = 8 // pixels
        
        for i in 0..<outline.count {
            let start = outline[i].cgPoint.applying(transform)
            let end = outline[(i + 1) % outline.count].cgPoint.applying(transform)
            
            var wallPath = Path()
            wallPath.move(to: start)
            wallPath.addLine(to: end)
            
            context.stroke(
                wallPath,
                with: .color(colors.wall),
                style: StrokeStyle(lineWidth: wallThickness, lineCap: .square, lineJoin: .miter)
            )
        }
    }
    
    private func drawDoors(context: GraphicsContext, transform: CGAffineTransform) {
        for door in floorPlanData.doors {
            let center = door.position.cgPoint.applying(transform)
            let scaledWidth = door.width * transform.a // Get scale from transform
            
            // Draw door opening (gap in wall)
            let halfWidth = scaledWidth / 2
            
            let start = CGPoint(
                x: center.x - cos(door.angle) * halfWidth,
                y: center.y - sin(door.angle) * halfWidth
            )
            let end = CGPoint(
                x: center.x + cos(door.angle) * halfWidth,
                y: center.y + sin(door.angle) * halfWidth
            )
            
            // Draw door line
            var doorPath = Path()
            doorPath.move(to: start)
            doorPath.addLine(to: end)
            context.stroke(doorPath, with: .color(colors.door), lineWidth: 3)
            
            // Draw door swing arc
            let swingRadius = scaledWidth * 0.9
            var arcPath = Path()
            arcPath.addArc(
                center: start,
                radius: swingRadius,
                startAngle: Angle(radians: door.angle),
                endAngle: Angle(radians: door.angle + .pi / 2),
                clockwise: false
            )
            context.stroke(arcPath, with: .color(colors.doorSwing), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            
            // Draw door leaf
            let leafEnd = CGPoint(
                x: start.x + cos(door.angle + .pi / 4) * swingRadius,
                y: start.y + sin(door.angle + .pi / 4) * swingRadius
            )
            var leafPath = Path()
            leafPath.move(to: start)
            leafPath.addLine(to: leafEnd)
            context.stroke(leafPath, with: .color(colors.door), lineWidth: 2)
        }
    }
    
    private func drawWindows(context: GraphicsContext, transform: CGAffineTransform) {
        for window in floorPlanData.windows {
            let center = window.position.cgPoint.applying(transform)
            let scaledWidth = window.width * transform.a
            
            let halfWidth = scaledWidth / 2
            let start = CGPoint(
                x: center.x - cos(window.angle) * halfWidth,
                y: center.y - sin(window.angle) * halfWidth
            )
            let end = CGPoint(
                x: center.x + cos(window.angle) * halfWidth,
                y: center.y + sin(window.angle) * halfWidth
            )
            
            // Draw window (triple line)
            var windowPath = Path()
            windowPath.move(to: start)
            windowPath.addLine(to: end)
            
            context.stroke(windowPath, with: .color(colors.window), lineWidth: 6)
            context.stroke(windowPath, with: .color(colors.background), lineWidth: 3)
            context.stroke(windowPath, with: .color(colors.window), lineWidth: 1)
        }
    }
    
    private func drawObjects(context: GraphicsContext, transform: CGAffineTransform) {
        for object in floorPlanData.objects {
            let center = object.position.cgPoint.applying(transform)
            let scaledWidth = object.width * transform.a
            let scaledDepth = object.depth * transform.a
            
            // Draw rotated rectangle for furniture
            var objectContext = context
            objectContext.translateBy(x: center.x, y: center.y)
            objectContext.rotate(by: Angle(radians: object.angle))
            
            let rect = CGRect(
                x: -scaledWidth / 2,
                y: -scaledDepth / 2,
                width: scaledWidth,
                height: scaledDepth
            )
            
            let objectPath = Path(roundedRect: rect, cornerRadius: 4)
            objectContext.fill(objectPath, with: .color(colors.furniture))
            objectContext.stroke(objectPath, with: .color(colors.furnitureStroke), lineWidth: 1)
            
            // Draw label
            let label = Text(object.category.icon)
                .font(.system(size: min(scaledWidth, scaledDepth) * 0.5))
            objectContext.draw(label, at: .zero)
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
            
            // Draw label background and text
            let label = Text(dimension.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(colors.dimensionText)
            
            context.draw(label, at: midPoint, anchor: .center)
        }
    }
    
    // MARK: - UI Components
    
    private var controlsBar: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $showGrid) {
                Image(systemName: "grid")
            }
            .toggleStyle(ControlToggleStyle())
            
            Toggle(isOn: $showDimensions) {
                Image(systemName: "ruler")
            }
            .toggleStyle(ControlToggleStyle())
            
            Toggle(isOn: $showFurniture) {
                Image(systemName: "sofa")
            }
            .toggleStyle(ControlToggleStyle())
            
            Divider()
                .frame(height: 24)
            
            Button {
                withAnimation(.spring()) {
                    scale = min(scale * 1.5, 5.0)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.white)
            }
            
            Button {
                withAnimation(.spring()) {
                    scale = max(scale / 1.5, 0.5)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var areaDisplay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("AREA")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(colors.dimensionText)
            Text(String(format: "%.1f m²", floorPlanData.totalArea))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(colors.areaText)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Custom Toggle Style

struct ControlToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .foregroundColor(configuration.isOn ? .white : .gray)
                .padding(8)
                .background(
                    configuration.isOn ? Color.white.opacity(0.2) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
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
        
        let sampleData = FloorPlanData(
            roomOutline: sampleOutline,
            walls: [],
            doors: [
                FloorPlanDoor(
                    id: UUID(),
                    position: FloorPlanPoint(2.5, 0),
                    width: 0.9,
                    angle: 0,
                    isOpen: false,
                    parentWallId: nil
                )
            ],
            windows: [
                FloorPlanWindow(
                    id: UUID(),
                    position: FloorPlanPoint(5, 2),
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
            dimensions: [],
            bounds: CGRect(x: -0.5, y: -0.5, width: 6, height: 5),
            totalArea: 20
        )
        
        FloorPlanView(floorPlanData: sampleData)
    }
}

