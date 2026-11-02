/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Model layer that processes CapturedRoom data into drawable floor plan elements.
Coordinate transformation logic ported from conversionscript.py for consistency.
*/

import Foundation
import simd

// MARK: - Transform Matrix Extensions

extension simd_float4x4 {
    /// Extract euler angles from the transformation matrix
    /// x = rotation around X axis (pitch)
    /// y = rotation around Y axis (yaw)
    /// z = rotation around Z axis (roll)
    var eulerAngles: simd_float3 {
        // Clamp for asin stability (matching Python: max(-1.0, min(1.0, -at(2, 1))))
        let v = max(-1.0, min(1.0, -self[2][1]))
        return simd_float3(
            x: asin(v),
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
    /// Matches Python: -(roll - yaw)
    var floorPlanRotation: CGFloat {
        return -CGFloat(eulerAngles.z - eulerAngles.y)
    }

    /// Transform a 3D point by this matrix
    /// Matches Python's mat4_transform_point for column-major matrices
    func transformPoint(_ point: simd_float3) -> simd_float3 {
        let p = simd_float4(point.x, point.y, point.z, 1.0)
        let result = self * p
        // Handle perspective division if needed
        if abs(result.w - 1.0) > 1e-6 && result.w != 0 {
            return simd_float3(result.x / result.w, result.y / result.w, result.z / result.w)
        }
        return simd_float3(result.x, result.y, result.z)
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
    /// Matches Python's world_to_floorplan_2d: (-world[0], world[2])
    static func fromWorld(_ world: simd_float3) -> FloorPlanPoint {
        return FloorPlanPoint(-CGFloat(world.x), CGFloat(world.z))
    }

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

/// A door in the floor plan (now uses start/end like walls for consistency)
struct FloorPlanDoor: Identifiable {
    let id: UUID
    let start: FloorPlanPoint
    let end: FloorPlanPoint
    let width: CGFloat
    let angle: CGFloat
    let isOpen: Bool
    let parentWallId: UUID?

    var position: FloorPlanPoint {
        FloorPlanPoint((start.x + end.x) / 2, (start.y + end.y) / 2)
    }
}

/// A window in the floor plan (now uses start/end like walls for consistency)
struct FloorPlanWindow: Identifiable {
    let id: UUID
    let start: FloorPlanPoint
    let end: FloorPlanPoint
    let width: CGFloat
    let angle: CGFloat
    let parentWallId: UUID?

    var position: FloorPlanPoint {
        FloorPlanPoint((start.x + end.x) / 2, (start.y + end.y) / 2)
    }
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

    /// SF Symbol name for use with Image(systemName:)
    var icon: String {
        switch self {
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .table: return "table.furniture"
        case .bed: return "bed.double"
        case .storage: return "cabinet"
        case .refrigerator: return "refrigerator"
        case .stove, .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .washer, .dryer: return "washer"
        case .sink: return "sink"
        case .bathtub: return "bathtub"
        case .toilet: return "toilet"
        case .fireplace: return "fireplace"
        case .television: return "tv"
        case .stairs: return "stairs"
        case .unknown: return "shippingbox"
        }
    }

    /// Emoji representation for text display
    var emoji: String {
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

/// A section/room label in the floor plan
struct FloorPlanSection: Identifiable {
    let id = UUID()
    let center: FloorPlanPoint
    let label: String
    let story: Int?
}

/// A floor outline (supports multiple floors/rooms)
struct FloorPlanOutline: Identifiable {
    let id: UUID
    let outline: [FloorPlanPoint]
    let story: Int?
    let area: CGFloat

    var centroid: FloorPlanPoint {
        guard !outline.isEmpty else { return FloorPlanPoint(0, 0) }

        // Shoelace centroid calculation
        var a2: CGFloat = 0
        var cx6: CGFloat = 0
        var cy6: CGFloat = 0

        for i in 0..<outline.count {
            let p0 = outline[i]
            let p1 = outline[(i + 1) % outline.count]
            let cross = p0.x * p1.y - p1.x * p0.y
            a2 += cross
            cx6 += (p0.x + p1.x) * cross
            cy6 += (p0.y + p1.y) * cross
        }

        if abs(a2) < 1e-9 {
            // Fallback to average
            let ax = outline.reduce(0) { $0 + $1.x } / CGFloat(outline.count)
            let ay = outline.reduce(0) { $0 + $1.y } / CGFloat(outline.count)
            return FloorPlanPoint(ax, ay)
        }

        return FloorPlanPoint(cx6 / (3.0 * a2), cy6 / (3.0 * a2))
    }
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
    let floorOutlines: [FloorPlanOutline]
    let walls: [FloorPlanWall]
    let doors: [FloorPlanDoor]
    let windows: [FloorPlanWindow]
    let objects: [FloorPlanObject]
    let sections: [FloorPlanSection]
    let dimensions: [FloorPlanDimension]
    let bounds: CGRect
    let totalArea: CGFloat // in square meters

    /// Convenience accessor for single-room scenarios
    var roomOutline: [FloorPlanPoint] {
        floorOutlines.first?.outline ?? []
    }

    static let empty = FloorPlanData(
        floorOutlines: [],
        walls: [],
        doors: [],
        windows: [],
        objects: [],
        sections: [],
        dimensions: [],
        bounds: .zero,
        totalArea: 0
    )
}

extension FloorPlanPoint {
    func rotated(by angle: CGFloat) -> FloorPlanPoint {
        let cosAngle = cos(angle)
        let sinAngle = sin(angle)
        let rotatedX = x * cosAngle - y * sinAngle
        let rotatedY = x * sinAngle + y * cosAngle
        return FloorPlanPoint(rotatedX, rotatedY)
    }
}

extension FloorPlanData {
    func oriented(northAlignment: ScanNorthAlignment?, sourceIsNorthUpNormalized: Bool, desiredNorthUp: Bool) -> FloorPlanData {
        guard let northAlignment else { return self }
        guard sourceIsNorthUpNormalized != desiredNorthUp else { return self }

        let compassDeltaDegrees = desiredNorthUp
            ? northAlignment.normalizedRoomToNorthYawDegrees
            : -northAlignment.normalizedRoomToNorthYawDegrees
        let mathRotationDegrees = compassDeltaToMathRotationDegrees(compassDeltaDegrees)
        let radians = CGFloat(mathRotationDegrees) * .pi / 180
        return rotated(by: radians)
    }

    // Compass deltas increase clockwise, while our 2D math rotation is counterclockwise.
    // Negating the heading delta keeps north-up orientation correct in rendered coordinates.
    private func compassDeltaToMathRotationDegrees(_ degrees: Double) -> Double {
        -degrees
    }

    func rotated(by angle: CGFloat) -> FloorPlanData {
        guard abs(angle) > 0.0001 else { return self }

        let rotatedOutlines = floorOutlines.map { outline in
            FloorPlanOutline(
                id: outline.id,
                outline: outline.outline.map { $0.rotated(by: angle) },
                story: outline.story,
                area: outline.area
            )
        }

        let rotatedWalls = walls.map { wall in
            FloorPlanWall(
                id: wall.id,
                start: wall.start.rotated(by: angle),
                end: wall.end.rotated(by: angle),
                thickness: wall.thickness,
                length: wall.length
            )
        }

        let rotatedDoors = doors.map { door in
            FloorPlanDoor(
                id: door.id,
                start: door.start.rotated(by: angle),
                end: door.end.rotated(by: angle),
                width: door.width,
                angle: door.angle + angle,
                isOpen: door.isOpen,
                parentWallId: door.parentWallId
            )
        }

        let rotatedWindows = windows.map { window in
            FloorPlanWindow(
                id: window.id,
                start: window.start.rotated(by: angle),
                end: window.end.rotated(by: angle),
                width: window.width,
                angle: window.angle + angle,
                parentWallId: window.parentWallId
            )
        }

        let rotatedObjects = objects.map { object in
            FloorPlanObject(
                id: object.id,
                position: object.position.rotated(by: angle),
                width: object.width,
                depth: object.depth,
                angle: object.angle + angle,
                category: object.category,
                label: object.label
            )
        }

        let rotatedSections = sections.map { section in
            FloorPlanSection(
                center: section.center.rotated(by: angle),
                label: section.label,
                story: section.story
            )
        }

        let bounds = Self.calculateBounds(
            outlines: rotatedOutlines,
            walls: rotatedWalls,
            doors: rotatedDoors,
            windows: rotatedWindows,
            objects: rotatedObjects
        )
        let dimensions = Self.generateDimensions(outlines: rotatedOutlines, bounds: bounds)

        return FloorPlanData(
            floorOutlines: rotatedOutlines,
            walls: rotatedWalls,
            doors: rotatedDoors,
            windows: rotatedWindows,
            objects: rotatedObjects,
            sections: rotatedSections,
            dimensions: dimensions,
            bounds: bounds,
            totalArea: totalArea
        )
    }

    private static func calculateBounds(
        outlines: [FloorPlanOutline],
        walls: [FloorPlanWall],
        doors: [FloorPlanDoor],
        windows: [FloorPlanWindow],
        objects: [FloorPlanObject]
    ) -> CGRect {
        var allPoints: [FloorPlanPoint] = []

        for outline in outlines {
            allPoints.append(contentsOf: outline.outline)
        }

        for wall in walls {
            allPoints.append(wall.start)
            allPoints.append(wall.end)
        }

        for door in doors {
            allPoints.append(door.start)
            allPoints.append(door.end)
        }

        for window in windows {
            allPoints.append(window.start)
            allPoints.append(window.end)
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

    private static func generateDimensions(outlines: [FloorPlanOutline], bounds: CGRect) -> [FloorPlanDimension] {
        var dimensions: [FloorPlanDimension] = []

        guard let firstOutline = outlines.first else { return dimensions }
        let outline = firstOutline.outline
        guard !outline.isEmpty else { return dimensions }

        let xs = outline.map { $0.x }
        let ys = outline.map { $0.y }
        let actualMinX = xs.min()!
        let actualMaxX = xs.max()!
        let actualMinY = ys.min()!
        let actualMaxY = ys.max()!
        let actualWidth = actualMaxX - actualMinX
        let actualHeight = actualMaxY - actualMinY

        let dimOffset: CGFloat = 0.4

        let widthDim = FloorPlanDimension(
            start: FloorPlanPoint(actualMinX, actualMaxY + dimOffset),
            end: FloorPlanPoint(actualMaxX, actualMaxY + dimOffset),
            label: String(format: "%.2f m", actualWidth),
            offset: 0.3
        )
        dimensions.append(widthDim)

        let heightDim = FloorPlanDimension(
            start: FloorPlanPoint(actualMinX - dimOffset, actualMinY),
            end: FloorPlanPoint(actualMinX - dimOffset, actualMaxY),
            label: String(format: "%.2f m", actualHeight),
            offset: 0.3
        )
        dimensions.append(heightDim)

        for i in 0..<outline.count {
            let start = outline[i]
            let end = outline[(i + 1) % outline.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = sqrt(dx * dx + dy * dy)

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
}
