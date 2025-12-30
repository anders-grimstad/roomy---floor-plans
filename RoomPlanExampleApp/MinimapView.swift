/*
See the LICENSE.txt file for this sample's licensing information.
 
Abstract:
Lightweight, UniFi-style minimap overlay rendered with CAShapeLayer.
The map is centered on the scanner and rotates heading-up.
*/

import UIKit
import CoreGraphics
import QuartzCore

final class MinimapView: UIView {
    
    struct Style {
        var pixelsPerMeter: CGFloat = 40.0
        var strokeWidthPx: CGFloat = 2.0
        var doorStrokeWidthPx: CGFloat = 2.0
        var windowStrokeWidthPx: CGFloat = 2.0
        
        var backgroundColor: UIColor = UIColor.black.withAlphaComponent(0.35)
        var borderColor: UIColor = UIColor.white.withAlphaComponent(0.10)
        
        var currentRoomColor: UIColor = UIColor.systemGreen
        var roomPalette: [UIColor] = [
            UIColor.white,
            UIColor.systemGreen,
            UIColor.systemTeal,
            UIColor.systemOrange,
            UIColor.systemPurple,
            UIColor.systemPink
        ]
        
        var wallColorForCompletedRooms: UIColor = UIColor.white
        var doorColor: UIColor = UIColor.white.withAlphaComponent(0.85)
        var windowColor: UIColor = UIColor.white.withAlphaComponent(0.85)
        
        var markerFill: UIColor = UIColor.systemBlue
        var markerStroke: UIColor = UIColor.white.withAlphaComponent(0.35)
        var markerArrowFill: UIColor = UIColor.systemBlue.withAlphaComponent(0.65)
        
        var cornerRadius: CGFloat = 16.0
        var showBorder: Bool = true
    }
    
    // MARK: - Layers
    
    /// Container for all map geometry (in floorplan meters). We apply transform to this layer.
    private let mapContainerLayer = CALayer()
    
    /// Completed room groups (each contains walls/doors/windows).
    private var completedRoomGroupLayers: [CALayer] = []
    
    /// Current/in-progress room group.
    private let currentRoomGroupLayer = CALayer()
    private let currentWallsLayer = CAShapeLayer()
    private let currentDoorsLayer = CAShapeLayer()
    private let currentWindowsLayer = CAShapeLayer()
    
    /// Device marker at screen center (not affected by map transforms).
    private let markerDotLayer = CAShapeLayer()
    private let markerArrowLayer = CAShapeLayer()
    
    // MARK: - State
    
    private var style: Style
    private var paletteIndex: Int = 0
    
    /// Last known pose in floorplan meters.
    private var lastPosition2D: CGPoint = .zero
    private var lastHeadingRad: CGFloat = 0
    
    // MARK: - Init
    
    init(style: Style = Style()) {
        self.style = style
        super.init(frame: .zero)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        self.style = Style()
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        
        layer.cornerRadius = style.cornerRadius
        layer.masksToBounds = true
        
        // Background fill via a sublayer so we can keep main view clear.
        let bg = CALayer()
        bg.backgroundColor = style.backgroundColor.cgColor
        bg.name = "minimap.background"
        layer.addSublayer(bg)
        
        if style.showBorder {
            layer.borderWidth = 1.0
            layer.borderColor = style.borderColor.cgColor
        }
        
        layer.addSublayer(mapContainerLayer)
        mapContainerLayer.addSublayer(currentRoomGroupLayer)
        
        // Current room layers
        configureRoomShapeLayer(currentWallsLayer, stroke: style.currentRoomColor, fill: UIColor.clear)
        configureRoomShapeLayer(currentDoorsLayer, stroke: style.currentRoomColor.withAlphaComponent(0.9), fill: UIColor.clear)
        configureRoomShapeLayer(currentWindowsLayer, stroke: style.currentRoomColor.withAlphaComponent(0.9), fill: UIColor.clear)
        currentRoomGroupLayer.addSublayer(currentWallsLayer)
        currentRoomGroupLayer.addSublayer(currentWindowsLayer)
        currentRoomGroupLayer.addSublayer(currentDoorsLayer)
        
        // Marker layers (centered in layoutSubviews)
        markerDotLayer.fillColor = style.markerFill.cgColor
        markerDotLayer.strokeColor = style.markerStroke.cgColor
        markerDotLayer.lineWidth = 1.0
        layer.addSublayer(markerDotLayer)
        
        markerArrowLayer.fillColor = style.markerArrowFill.cgColor
        markerArrowLayer.strokeColor = UIColor.clear.cgColor
        layer.addSublayer(markerArrowLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Background sublayer
        if let bg = layer.sublayers?.first(where: { $0.name == "minimap.background" }) {
            bg.frame = bounds
        }
        
        mapContainerLayer.frame = bounds
        currentRoomGroupLayer.frame = bounds
        
        // Marker layers must have a frame; their paths are defined in this view’s coordinate space.
        markerDotLayer.frame = bounds
        markerArrowLayer.frame = bounds
        
        // Device marker at center
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        markerDotLayer.path = UIBezierPath(
            ovalIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
        ).cgPath
        
        // Small “cone” arrow pointing up (since map is heading-up)
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: center.x, y: center.y - 20))
        arrow.addLine(to: CGPoint(x: center.x - 10, y: center.y - 4))
        arrow.addLine(to: CGPoint(x: center.x + 10, y: center.y - 4))
        arrow.close()
        markerArrowLayer.path = arrow.cgPath
        
        // Re-apply pose-driven transform with new bounds.
        applyPoseTransform()
    }
    
    // MARK: - Public API
    
    func clearCompletedRooms() {
        for layer in completedRoomGroupLayers {
            layer.removeFromSuperlayer()
        }
        completedRoomGroupLayers.removeAll()
        paletteIndex = 0
    }
    
    func appendCompletedRoom(_ data: FloorPlanData) {
        let color = nextRoomColor()
        let group = makeRoomGroupLayer(from: data, strokeColor: color)
        completedRoomGroupLayers.append(group)
        mapContainerLayer.insertSublayer(group, below: currentRoomGroupLayer)
    }
    
    func setCurrentRoom(_ data: FloorPlanData?) {
        guard let data else {
            currentWallsLayer.path = nil
            currentDoorsLayer.path = nil
            currentWindowsLayer.path = nil
            return
        }
        
        let ppm = style.pixelsPerMeter
        let wallWidthMeters = style.strokeWidthPx / ppm
        let doorWidthMeters = style.doorStrokeWidthPx / ppm
        let windowWidthMeters = style.windowStrokeWidthPx / ppm
        
        currentWallsLayer.lineWidth = wallWidthMeters
        currentDoorsLayer.lineWidth = doorWidthMeters
        currentWindowsLayer.lineWidth = windowWidthMeters
        
        currentWallsLayer.path = makeSegmentPath(data.walls.map { ($0.start.cgPoint, $0.end.cgPoint) })
        currentDoorsLayer.path = makeSegmentPath(data.doors.map { ($0.start.cgPoint, $0.end.cgPoint) })
        currentWindowsLayer.path = makeSegmentPath(data.windows.map { ($0.start.cgPoint, $0.end.cgPoint) })
    }
    
    /// Update the map transform from the current pose.
    /// - position2D: floorplan meters (x = -worldX, y = worldZ)
    /// - headingRad: floorplan heading radians (0 = +x, pi/2 = +y)
    func updatePose(position2D: CGPoint, headingRad: CGFloat) {
        lastPosition2D = position2D
        lastHeadingRad = headingRad
        applyPoseTransform()
    }
    
    // MARK: - Internals
    
    private func applyPoseTransform() {
        let centerX = bounds.midX
        let centerY = bounds.midY
        let ppm = style.pixelsPerMeter
        
        // Apply in this order to points:
        // 1) translate by -position (anchor on scanner)
        // 2) rotate by -heading (heading-up)
        // 3) scale to pixels (flip Y for UIKit)
        // 4) translate to view center
        let transform = CGAffineTransform(translationX: -lastPosition2D.x, y: -lastPosition2D.y)
            .concatenating(CGAffineTransform(rotationAngle: -lastHeadingRad))
            .concatenating(CGAffineTransform(scaleX: ppm, y: -ppm))
            .concatenating(CGAffineTransform(translationX: centerX, y: centerY))
        
        mapContainerLayer.setAffineTransform(transform)
    }
    
    private func configureRoomShapeLayer(_ layer: CAShapeLayer, stroke: UIColor, fill: UIColor) {
        layer.strokeColor = stroke.cgColor
        layer.fillColor = fill.cgColor
        layer.lineCap = .round
        layer.lineJoin = .round
    }
    
    private func nextRoomColor() -> UIColor {
        defer { paletteIndex += 1 }
        if style.roomPalette.isEmpty { return style.wallColorForCompletedRooms }
        return style.roomPalette[paletteIndex % style.roomPalette.count]
    }
    
    private func makeRoomGroupLayer(from data: FloorPlanData, strokeColor: UIColor) -> CALayer {
        let group = CALayer()
        
        let ppm = style.pixelsPerMeter
        let wallWidthMeters = style.strokeWidthPx / ppm
        let doorWidthMeters = style.doorStrokeWidthPx / ppm
        let windowWidthMeters = style.windowStrokeWidthPx / ppm
        
        let wallsLayer = CAShapeLayer()
        configureRoomShapeLayer(wallsLayer, stroke: strokeColor, fill: UIColor.clear)
        wallsLayer.lineWidth = wallWidthMeters
        wallsLayer.path = makeSegmentPath(data.walls.map { ($0.start.cgPoint, $0.end.cgPoint) })
        
        let doorsLayer = CAShapeLayer()
        configureRoomShapeLayer(doorsLayer, stroke: strokeColor.withAlphaComponent(0.9), fill: UIColor.clear)
        doorsLayer.lineWidth = doorWidthMeters
        doorsLayer.path = makeSegmentPath(data.doors.map { ($0.start.cgPoint, $0.end.cgPoint) })
        
        let windowsLayer = CAShapeLayer()
        configureRoomShapeLayer(windowsLayer, stroke: strokeColor.withAlphaComponent(0.9), fill: UIColor.clear)
        windowsLayer.lineWidth = windowWidthMeters
        windowsLayer.path = makeSegmentPath(data.windows.map { ($0.start.cgPoint, $0.end.cgPoint) })
        
        group.addSublayer(wallsLayer)
        group.addSublayer(windowsLayer)
        group.addSublayer(doorsLayer)
        
        return group
    }
    
    private func makeSegmentPath(_ segments: [(CGPoint, CGPoint)]) -> CGPath? {
        guard !segments.isEmpty else { return nil }
        let path = CGMutablePath()
        for (a, b) in segments {
            path.move(to: a)
            path.addLine(to: b)
        }
        return path
    }
}


