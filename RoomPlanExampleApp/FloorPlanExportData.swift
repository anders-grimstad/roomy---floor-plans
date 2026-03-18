/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Codable export format for floor plans and conversion helpers.
*/

import Foundation

struct FloorPlanExportData: Codable {
    var version: String = "2.3"
    let generatedAt: Date
    let scanHeading: ScanHeading?
    let northAlignment: ScanNorthAlignment?
    let isNorthUpNormalized: Bool?
    let totalArea: Double
    let bounds: BoundsData
    let floorOutlines: [FloorOutlineData]
    let walls: [WallData]
    let doors: [DoorData]
    let windows: [WindowData]
    let objects: [ObjectData]
    let sections: [SectionData]

    struct BoundsData: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct FloorOutlineData: Codable {
        let id: String
        let story: Int?
        let area: Double
        let outline: [[Double]]
    }

    struct WallData: Codable {
        let id: String
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
        let length: Double
    }

    struct DoorData: Codable {
        let id: String
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
        let width: Double
        let angle: Double
        let isOpen: Bool
    }

    struct WindowData: Codable {
        let id: String
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
        let width: Double
        let angle: Double
    }

    struct ObjectData: Codable {
        let id: String
        let category: String
        let label: String
        let x: Double
        let y: Double
        let width: Double
        let depth: Double
        let angle: Double
    }

    struct SectionData: Codable {
        let label: String
        let x: Double
        let y: Double
        let story: Int?
    }

    init(
        from data: FloorPlanData,
        scanHeading: ScanHeading? = nil,
        northAlignment: ScanNorthAlignment? = nil,
        isNorthUpNormalized: Bool? = nil
    ) {
        self.generatedAt = Date()
        self.scanHeading = scanHeading
        self.northAlignment = northAlignment
        self.isNorthUpNormalized = isNorthUpNormalized
        self.totalArea = Double(data.totalArea)
        self.bounds = BoundsData(
            x: Double(data.bounds.minX),
            y: Double(data.bounds.minY),
            width: Double(data.bounds.width),
            height: Double(data.bounds.height)
        )
        self.floorOutlines = data.floorOutlines.map { outline in
            FloorOutlineData(
                id: outline.id.uuidString,
                story: outline.story,
                area: Double(outline.area),
                outline: outline.outline.map { [Double($0.x), Double($0.y)] }
            )
        }
        self.walls = data.walls.map { wall in
            WallData(
                id: wall.id.uuidString,
                startX: Double(wall.start.x),
                startY: Double(wall.start.y),
                endX: Double(wall.end.x),
                endY: Double(wall.end.y),
                length: Double(wall.length)
            )
        }
        self.doors = data.doors.map { door in
            DoorData(
                id: door.id.uuidString,
                startX: Double(door.start.x),
                startY: Double(door.start.y),
                endX: Double(door.end.x),
                endY: Double(door.end.y),
                width: Double(door.width),
                angle: Double(door.angle),
                isOpen: door.isOpen
            )
        }
        self.windows = data.windows.map { window in
            WindowData(
                id: window.id.uuidString,
                startX: Double(window.start.x),
                startY: Double(window.start.y),
                endX: Double(window.end.x),
                endY: Double(window.end.y),
                width: Double(window.width),
                angle: Double(window.angle)
            )
        }
        self.objects = data.objects.map { obj in
            ObjectData(
                id: obj.id.uuidString,
                category: obj.category.rawValue,
                label: obj.label,
                x: Double(obj.position.x),
                y: Double(obj.position.y),
                width: Double(obj.width),
                depth: Double(obj.depth),
                angle: Double(obj.angle)
            )
        }
        self.sections = data.sections.map { section in
            SectionData(
                label: section.label,
                x: Double(section.center.x),
                y: Double(section.center.y),
                story: section.story
            )
        }
    }
}

extension FloorPlanExportData {
    func toFloorPlanData() -> FloorPlanData {
        let outlines = floorOutlines.map { outline -> FloorPlanOutline in
            let points = outline.outline.map { FloorPlanPoint(CGFloat($0[0]), CGFloat($0[1])) }
            return FloorPlanOutline(
                id: UUID(uuidString: outline.id) ?? UUID(),
                outline: points,
                story: outline.story,
                area: CGFloat(outline.area)
            )
        }

        let walls = self.walls.map { wall in
            FloorPlanWall(
                id: UUID(uuidString: wall.id) ?? UUID(),
                start: FloorPlanPoint(CGFloat(wall.startX), CGFloat(wall.startY)),
                end: FloorPlanPoint(CGFloat(wall.endX), CGFloat(wall.endY)),
                thickness: 0.15,
                length: CGFloat(wall.length)
            )
        }

        let doors = self.doors.map { door in
            FloorPlanDoor(
                id: UUID(uuidString: door.id) ?? UUID(),
                start: FloorPlanPoint(CGFloat(door.startX), CGFloat(door.startY)),
                end: FloorPlanPoint(CGFloat(door.endX), CGFloat(door.endY)),
                width: CGFloat(door.width),
                angle: CGFloat(door.angle),
                isOpen: door.isOpen,
                parentWallId: nil
            )
        }

        let windows = self.windows.map { window in
            FloorPlanWindow(
                id: UUID(uuidString: window.id) ?? UUID(),
                start: FloorPlanPoint(CGFloat(window.startX), CGFloat(window.startY)),
                end: FloorPlanPoint(CGFloat(window.endX), CGFloat(window.endY)),
                width: CGFloat(window.width),
                angle: CGFloat(window.angle),
                parentWallId: nil
            )
        }

        let objects = self.objects.map { object in
            FloorPlanObject(
                id: UUID(uuidString: object.id) ?? UUID(),
                position: FloorPlanPoint(CGFloat(object.x), CGFloat(object.y)),
                width: CGFloat(object.width),
                depth: CGFloat(object.depth),
                angle: CGFloat(object.angle),
                category: FloorPlanObjectCategory(rawValue: object.category) ?? .unknown,
                label: object.label
            )
        }

        let sections = self.sections.map { section in
            FloorPlanSection(
                center: FloorPlanPoint(CGFloat(section.x), CGFloat(section.y)),
                label: section.label,
                story: section.story
            )
        }

        let boundsRect = CGRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
        )

        let dimensions = Self.generateDimensions(for: outlines, bounds: boundsRect)

        return FloorPlanData(
            floorOutlines: outlines,
            walls: walls,
            doors: doors,
            windows: windows,
            objects: objects,
            sections: sections,
            dimensions: dimensions,
            bounds: boundsRect,
            totalArea: CGFloat(totalArea)
        )
    }
}

extension FloorPlanExportData {
    private static func generateDimensions(for outlines: [FloorPlanOutline], bounds: CGRect) -> [FloorPlanDimension] {
        var dimensions: [FloorPlanDimension] = []

        guard let firstOutline = outlines.first else { return dimensions }
        let outline = firstOutline.outline
        guard !outline.isEmpty else { return dimensions }

        let xs = outline.map { $0.x }
        let ys = outline.map { $0.y }
        guard let actualMinX = xs.min(),
              let actualMaxX = xs.max(),
              let actualMinY = ys.min(),
              let actualMaxY = ys.max() else {
            return dimensions
        }

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
