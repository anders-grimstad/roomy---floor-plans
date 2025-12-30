/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Model layer that processes CapturedRoom data into drawable floor plan elements.
*/

import Foundation
import RoomPlan
import simd

// MARK: - Transform Matrix Extensions (from guide)

extension simd_float4x4 {
    /// Extract euler angles from the transformation matrix
    /// x = rotation around X axis (pitch)
    /// y = rotation around Y axis (yaw)
    /// z = rotation around Z axis (roll)
    var eulerAngles: simd_float3 {
        simd_float3(
            x: asin(-self[2][1]),
            y: atan2(self[2][0], self[2][2]),
            z: atan2(self[0][1], self[1][1])
        )
    }
    
    /// Extract position from the transformation matrix (column 3)
    var position: simd_float3 {
        simd_float3(
            x: self.columns.3.x,
            y: self.columns.3.y,
            z: self.columns.3.z
        )
    }
    
    /// Get the 2D rotation for floor plan (guide formula)
    /// This is the rotation to apply when viewing from above
    var floorPlanRotation: CGFloat {
        return -CGFloat(eulerAngles.z - eulerAngles.y)
    }
}

// MARK: - Floor Plan Data Models

/// Represents a 2D point in the floor plan coordinate system (meters)
/// Note: RoomPlan uses X = right, Y = up (height), Z = forward
/// For top-down 2D view, we map: -World X → FloorPlan x, World Z → FloorPlan y
/// (X is negated to match the guide's coordinate transformation)
struct FloorPlanPoint: Equatable {
    let x: CGFloat  // -World X (negated)
    let y: CGFloat  // World Z
    
    init(_ x: CGFloat, _ y: CGFloat) {
        self.x = x
        self.y = y
    }
    
    /// Create from world coordinates (applies the negation to X)
    static func fromWorld(x: Float, z: Float) -> FloorPlanPoint {
        return FloorPlanPoint(-CGFloat(x), CGFloat(z))
    }
    
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

/// A wall segment in the floor plan
struct FloorPlanWall: Identifiable {
    let id: UUID
    let start: FloorPlanPoint
    let end: FloorPlanPoint
    let thickness: CGFloat
    let length: CGFloat
    
    var midpoint: FloorPlanPoint {
        FloorPlanPoint((start.x + end.x) / 2, (start.y + end.y) / 2)
    }
    
    var angle: CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }
}

/// A door in the floor plan
struct FloorPlanDoor: Identifiable {
    let id: UUID
    let position: FloorPlanPoint
    let width: CGFloat
    let angle: CGFloat
    let isOpen: Bool
    let parentWallId: UUID?
}

/// A window in the floor plan
struct FloorPlanWindow: Identifiable {
    let id: UUID
    let position: FloorPlanPoint
    let width: CGFloat
    let angle: CGFloat
    let parentWallId: UUID?
}

/// Furniture/object categories for icons
enum FloorPlanObjectCategory: String {
    case sofa
    case chair
    case table
    case bed
    case storage
    case refrigerator
    case stove
    case oven
    case dishwasher
    case washer
    case dryer
    case sink
    case bathtub
    case toilet
    case fireplace
    case television
    case stairs
    case unknown
    
    var icon: String {
        switch self {
        case .sofa: return "🛋️"
        case .chair: return "🪑"
        case .table: return "🪑"
        case .bed: return "🛏️"
        case .storage: return "🗄️"
        case .refrigerator: return "🧊"
        case .stove, .oven: return "🍳"
        case .dishwasher: return "🍽️"
        case .washer, .dryer: return "🧺"
        case .sink: return "🚰"
        case .bathtub: return "🛁"
        case .toilet: return "🚽"
        case .fireplace: return "🔥"
        case .television: return "📺"
        case .stairs: return "🪜"
        case .unknown: return "📦"
        }
    }
}

/// An object/furniture piece in the floor plan
struct FloorPlanObject: Identifiable {
    let id: UUID
    let position: FloorPlanPoint
    let width: CGFloat
    let depth: CGFloat
    let angle: CGFloat
    let category: FloorPlanObjectCategory
    let label: String
}

/// Dimension annotation for measurements
struct FloorPlanDimension: Identifiable {
    let id = UUID()
    let start: FloorPlanPoint
    let end: FloorPlanPoint
    let label: String
    let offset: CGFloat // perpendicular offset from the line
    
    var length: CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }
}

/// Complete floor plan data ready for rendering
struct FloorPlanData {
    let roomOutline: [FloorPlanPoint]
    let walls: [FloorPlanWall]
    let doors: [FloorPlanDoor]
    let windows: [FloorPlanWindow]
    let objects: [FloorPlanObject]
    let dimensions: [FloorPlanDimension]
    let bounds: CGRect
    let totalArea: CGFloat // in square meters
    
    static let empty = FloorPlanData(
        roomOutline: [],
        walls: [],
        doors: [],
        windows: [],
        objects: [],
        dimensions: [],
        bounds: .zero,
        totalArea: 0
    )
}

// MARK: - Floor Plan Generator

class FloorPlanGenerator {
    
    private let capturedRoom: CapturedRoom
    private let wallThickness: CGFloat = 0.15 // 15cm default wall thickness
    
    init(capturedRoom: CapturedRoom) {
        self.capturedRoom = capturedRoom
    }
    
    /// Generate complete floor plan data from the captured room
    func generate() -> FloorPlanData {
        let outline = extractRoomOutline()
        let walls = extractWalls()
        let doors = extractDoors()
        let windows = extractWindows()
        let objects = extractObjects()
        let bounds = calculateBounds(outline: outline, walls: walls, objects: objects)
        let dimensions = generateDimensions(outline: outline, bounds: bounds)
        let area = calculateArea(outline: outline)
        
        return FloorPlanData(
            roomOutline: outline,
            walls: walls,
            doors: doors,
            windows: windows,
            objects: objects,
            dimensions: dimensions,
            bounds: bounds,
            totalArea: area
        )
    }
    
    // MARK: - Extraction Methods
    
    private func extractRoomOutline() -> [FloorPlanPoint] {
        guard let floor = capturedRoom.floors.first else { return [] }
        
        // IMPORTANT: polygonCorners are in the floor's LOCAL coordinate space!
        // We need to transform them to world coordinates using the floor's transform matrix
        let floorTransform = floor.transform
        
        return floor.polygonCorners.map { localCorner in
            // Transform local corner to world coordinates
            // localCorner is in the floor's local 2D space (x, y, 0)
            let localPoint = simd_float4(localCorner.x, localCorner.y, localCorner.z, 1.0)
            let worldPoint = floorTransform * localPoint
            
            // Guide's coordinate mapping: FloorPlan X = -World X, FloorPlan Y = World Z
            return FloorPlanPoint.fromWorld(x: worldPoint.x, z: worldPoint.z)
        }
    }
    
    private func extractWalls() -> [FloorPlanWall] {
        return capturedRoom.walls.compactMap { wall -> FloorPlanWall? in
            let transform = wall.transform
            let length = CGFloat(wall.dimensions.x)  // dimensions.x = wall length
            let halfLength = length / 2
            
            // Guide's approach:
            // 1. Position: -X for floor plan X, Z for floor plan Y
            // 2. Rotation: -(eulerAngles.z - eulerAngles.y)
            let centerX = -CGFloat(transform.position.x)  // Negate X per guide
            let centerY = CGFloat(transform.position.z)
            let rotation = transform.floorPlanRotation
            
            // Calculate endpoints from center, half-length, and rotation
            // Points A and B are at (-halfLength, 0) and (halfLength, 0) in local space
            // Rotated and translated to world space
            let dx = cos(rotation) * halfLength
            let dy = sin(rotation) * halfLength
            
            let start = FloorPlanPoint(centerX - dx, centerY - dy)
            let end = FloorPlanPoint(centerX + dx, centerY + dy)
            
            return FloorPlanWall(
                id: wall.identifier,
                start: start,
                end: end,
                thickness: wallThickness,
                length: length
            )
        }
    }
    
    private func extractDoors() -> [FloorPlanDoor] {
        return capturedRoom.doors.map { door in
            let transform = door.transform
            
            // Guide's coordinate mapping: -X for floor plan X, Z for floor plan Y
            let position = FloorPlanPoint.fromWorld(
                x: transform.position.x,
                z: transform.position.z
            )
            
            // Guide's rotation formula
            let angle = transform.floorPlanRotation
            
            // Check if door is open from the category enum
            let isOpen: Bool
            if case .door(let open) = door.category {
                isOpen = open
            } else {
                isOpen = false
            }
            
            return FloorPlanDoor(
                id: door.identifier,
                position: position,
                width: CGFloat(door.dimensions.x),
                angle: angle,
                isOpen: isOpen,
                parentWallId: door.parentIdentifier
            )
        }
    }
    
    private func extractWindows() -> [FloorPlanWindow] {
        return capturedRoom.windows.map { window in
            let transform = window.transform
            
            // Guide's coordinate mapping: -X for floor plan X, Z for floor plan Y
            let position = FloorPlanPoint.fromWorld(
                x: transform.position.x,
                z: transform.position.z
            )
            
            // Guide's rotation formula
            let angle = transform.floorPlanRotation
            
            return FloorPlanWindow(
                id: window.identifier,
                position: position,
                width: CGFloat(window.dimensions.x),
                angle: angle,
                parentWallId: window.parentIdentifier
            )
        }
    }
    
    private func extractObjects() -> [FloorPlanObject] {
        return capturedRoom.objects.map { object in
            let transform = object.transform
            
            // Guide's coordinate mapping: -X for floor plan X, Z for floor plan Y
            let position = FloorPlanPoint.fromWorld(
                x: transform.position.x,
                z: transform.position.z
            )
            
            // Guide's rotation formula
            let angle = transform.floorPlanRotation
            
            let category = mapCategory(object.category)
            
            // Dimensions: x = width, y = height (vertical), z = depth
            // For top-down 2D floor plan: width = x, depth = z
            return FloorPlanObject(
                id: object.identifier,
                position: position,
                width: CGFloat(object.dimensions.x),
                depth: CGFloat(object.dimensions.z),
                angle: angle,
                category: category,
                label: categoryLabel(object.category)
            )
        }
    }
    
    private func mapCategory(_ category: CapturedRoom.Object.Category) -> FloorPlanObjectCategory {
        switch category {
        case .storage: return .storage
        case .refrigerator: return .refrigerator
        case .stove: return .stove
        case .bed: return .bed
        case .sink: return .sink
        case .washerDryer: return .washer
        case .toilet: return .toilet
        case .bathtub: return .bathtub
        case .oven: return .oven
        case .dishwasher: return .dishwasher
        case .table: return .table
        case .sofa: return .sofa
        case .chair: return .chair
        case .fireplace: return .fireplace
        case .television: return .television
        case .stairs: return .stairs
        @unknown default: return .unknown
        }
    }
    
    private func categoryLabel(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return "Storage"
        case .refrigerator: return "Fridge"
        case .stove: return "Stove"
        case .bed: return "Bed"
        case .sink: return "Sink"
        case .washerDryer: return "Washer/Dryer"
        case .toilet: return "Toilet"
        case .bathtub: return "Bathtub"
        case .oven: return "Oven"
        case .dishwasher: return "Dishwasher"
        case .table: return "Table"
        case .sofa: return "Sofa"
        case .chair: return "Chair"
        case .fireplace: return "Fireplace"
        case .television: return "TV"
        case .stairs: return "Stairs"
        @unknown default: return "Object"
        }
    }
    
    // MARK: - Calculation Methods
    
    private func calculateBounds(outline: [FloorPlanPoint], walls: [FloorPlanWall], objects: [FloorPlanObject]) -> CGRect {
        var allPoints: [FloorPlanPoint] = outline
        
        for wall in walls {
            allPoints.append(wall.start)
            allPoints.append(wall.end)
        }
        
        for object in objects {
            allPoints.append(object.position)
        }
        
        guard !allPoints.isEmpty else { return .zero }
        
        let xs = allPoints.map { $0.x }
        let ys = allPoints.map { $0.y }
        
        let minX = xs.min()! - 0.5
        let maxX = xs.max()! + 0.5
        let minY = ys.min()! - 0.5
        let maxY = ys.max()! + 0.5
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func generateDimensions(outline: [FloorPlanPoint], bounds: CGRect) -> [FloorPlanDimension] {
        var dimensions: [FloorPlanDimension] = []
        
        // Calculate actual room extents from outline (not padded bounds)
        guard !outline.isEmpty else { return dimensions }
        
        let xs = outline.map { $0.x }
        let ys = outline.map { $0.y }
        let actualMinX = xs.min()!
        let actualMaxX = xs.max()!
        let actualMinY = ys.min()!
        let actualMaxY = ys.max()!
        let actualWidth = actualMaxX - actualMinX
        let actualHeight = actualMaxY - actualMinY
        
        // Add overall room dimensions (positioned outside the room)
        let dimOffset: CGFloat = 0.4
        
        // Width dimension (bottom)
        let widthDim = FloorPlanDimension(
            start: FloorPlanPoint(actualMinX, actualMaxY + dimOffset),
            end: FloorPlanPoint(actualMaxX, actualMaxY + dimOffset),
            label: String(format: "%.2f m", actualWidth),
            offset: 0.3
        )
        dimensions.append(widthDim)
        
        // Height dimension (left side)
        let heightDim = FloorPlanDimension(
            start: FloorPlanPoint(actualMinX - dimOffset, actualMinY),
            end: FloorPlanPoint(actualMinX - dimOffset, actualMaxY),
            label: String(format: "%.2f m", actualHeight),
            offset: 0.3
        )
        dimensions.append(heightDim)
        
        // Add wall segment dimensions for each edge of the outline
        for i in 0..<outline.count {
            let start = outline[i]
            let end = outline[(i + 1) % outline.count]
            
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = sqrt(dx * dx + dy * dy)
            
            // Only add dimensions for walls longer than 0.5 meter
            if length > 0.5 {
                let wallDim = FloorPlanDimension(
                    start: start,
                    end: end,
                    label: String(format: "%.2f m", length),
                    offset: 0.25
                )
                dimensions.append(wallDim)
            }
        }
        
        return dimensions
    }
    
    private func calculateArea(outline: [FloorPlanPoint]) -> CGFloat {
        guard outline.count >= 3 else { return 0 }
        
        // Shoelace formula for polygon area
        var area: CGFloat = 0
        for i in 0..<outline.count {
            let j = (i + 1) % outline.count
            area += outline[i].x * outline[j].y
            area -= outline[j].x * outline[i].y
        }
        return abs(area) / 2
    }
}

