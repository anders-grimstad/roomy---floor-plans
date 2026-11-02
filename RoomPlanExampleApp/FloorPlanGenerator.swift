/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Converts a captured RoomPlan result into floor-plan geometry.
*/

import Foundation
import RoomPlan
import simd

// MARK: - Floor Plan Generator

class FloorPlanGenerator {
    
    private let capturedRoom: CapturedRoom
    private let wallThickness: CGFloat = 0.15 // 15cm default wall thickness
    
    init(capturedRoom: CapturedRoom) {
        self.capturedRoom = capturedRoom
    }
    
    /// Generate complete floor plan data from the captured room
    func generate() -> FloorPlanData {
        let outlines = extractFloorOutlines()
        let walls = extractWalls()
        let doors = extractDoors()
        let windows = extractWindows()
        let objects = extractObjects()
        let sections = extractSections()
        let bounds = calculateBounds(outlines: outlines, walls: walls, doors: doors, windows: windows, objects: objects)
        let dimensions = generateDimensions(outlines: outlines, bounds: bounds)
        let totalArea = outlines.reduce(0) { $0 + $1.area }
        
        return FloorPlanData(
            floorOutlines: outlines,
            walls: walls,
            doors: doors,
            windows: windows,
            objects: objects,
            sections: sections,
            dimensions: dimensions,
            bounds: bounds,
            totalArea: totalArea
        )
    }
    
    // MARK: - Extraction Methods
    
    /// Calculate endpoints for a linear element (wall/door/window)
    /// Matches Python's endpoints_from_transform_and_length
    private func endpointsFromTransform(_ transform: simd_float4x4, length: Float) -> (simd_float3, simd_float3) {
        let half = length / 2.0
        // Local segment runs along +X/-X in the element's local frame
        let p0Local = simd_float3(-half, 0, 0)
        let p1Local = simd_float3(half, 0, 0)
        return (transform.transformPoint(p0Local), transform.transformPoint(p1Local))
    }
    
    private func extractFloorOutlines() -> [FloorPlanOutline] {
        return capturedRoom.floors.compactMap { floor -> FloorPlanOutline? in
            guard !floor.polygonCorners.isEmpty else { return nil }
            
            let floorTransform = floor.transform
            
            let outline = floor.polygonCorners.map { localCorner -> FloorPlanPoint in
                // Transform local corner to world coordinates
                let localPoint = simd_float3(localCorner.x, localCorner.y, localCorner.z)
                let worldPoint = floorTransform.transformPoint(localPoint)
                return FloorPlanPoint.fromWorld(worldPoint)
            }
            
            let area = calculatePolygonArea(outline)
            
            return FloorPlanOutline(
                id: floor.identifier,
                outline: outline,
                story: floor.story,
                area: area
            )
        }
    }
    
    private func extractWalls() -> [FloorPlanWall] {
        return capturedRoom.walls.map { wall -> FloorPlanWall in
            let length = wall.dimensions.x
            let (p0World, p1World) = endpointsFromTransform(wall.transform, length: length)
            
            return FloorPlanWall(
                id: wall.identifier,
                start: FloorPlanPoint.fromWorld(p0World),
                end: FloorPlanPoint.fromWorld(p1World),
                thickness: wallThickness,
                length: CGFloat(length)
            )
        }
    }
    
    private func extractDoors() -> [FloorPlanDoor] {
        return capturedRoom.doors.map { door -> FloorPlanDoor in
            let width = door.dimensions.x
            let (p0World, p1World) = endpointsFromTransform(door.transform, length: width)
            let angle = door.transform.floorPlanRotation
            
            // Check if door is open from the category enum
            let isOpen: Bool
            if case .door(let open) = door.category {
                isOpen = open
            } else {
                isOpen = false
            }
            
            return FloorPlanDoor(
                id: door.identifier,
                start: FloorPlanPoint.fromWorld(p0World),
                end: FloorPlanPoint.fromWorld(p1World),
                width: CGFloat(width),
                angle: angle,
                isOpen: isOpen,
                parentWallId: door.parentIdentifier
            )
        }
    }
    
    private func extractWindows() -> [FloorPlanWindow] {
        return capturedRoom.windows.map { window -> FloorPlanWindow in
            let width = window.dimensions.x
            let (p0World, p1World) = endpointsFromTransform(window.transform, length: width)
            let angle = window.transform.floorPlanRotation
            
            return FloorPlanWindow(
                id: window.identifier,
                start: FloorPlanPoint.fromWorld(p0World),
                end: FloorPlanPoint.fromWorld(p1World),
                width: CGFloat(width),
                angle: angle,
                parentWallId: window.parentIdentifier
            )
        }
    }
    
    private func extractObjects() -> [FloorPlanObject] {
        return capturedRoom.objects.map { object -> FloorPlanObject in
            let transform = object.transform
            
            // Center is just the transform applied to origin
            let centerWorld = transform.transformPoint(simd_float3(0, 0, 0))
            let position = FloorPlanPoint.fromWorld(centerWorld)
            let angle = transform.floorPlanRotation
            let category = mapCategory(object.category)
            
            // Dimensions: x = width, y = height (vertical), z = depth
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
    
    private func extractSections() -> [FloorPlanSection] {
        return capturedRoom.sections.map { section -> FloorPlanSection in
            // Section centers are in world space
            let center = section.center
            let center3 = simd_float3(center.x, center.y, center.z)
            let position = FloorPlanPoint.fromWorld(center3)
            
            // Format label: convert camelCase to Title Case
            let formattedLabel = formatSectionLabel(String(describing: section.label))
            
            return FloorPlanSection(
                center: position,
                label: formattedLabel,
                story: section.story
            )
        }
    }
    
    /// Format section label from camelCase to Title Case
    /// Matches Python's format_section_label
    private func formatSectionLabel(_ label: String) -> String {
        let rawLabel = label
        // Insert space before capitals
        var result = ""
        for (i, char) in rawLabel.enumerated() {
            if char.isUppercase && i > 0 {
                result += " "
            }
            result.append(char)
        }
        return result.isEmpty ? "Room" : result.capitalized
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
    
    private func calculateBounds(
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
    
    private func generateDimensions(outlines: [FloorPlanOutline], bounds: CGRect) -> [FloorPlanDimension] {
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
    
    private func calculatePolygonArea(_ polygon: [FloorPlanPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        
        // Shoelace formula
        var area: CGFloat = 0
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            area += polygon[i].x * polygon[j].y
            area -= polygon[j].x * polygon[i].y
        }
        return abs(area) / 2
    }
}

