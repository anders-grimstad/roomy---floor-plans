/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
UIKit view controller that hosts the SwiftUI floor plan view and provides export functionality.
*/

import UIKit
import SwiftUI
import RoomPlan

class FloorPlanViewController: UIViewController {
    
    // MARK: - Properties
    
    private var capturedRoom: CapturedRoom?
    private var floorPlanData: FloorPlanData = .empty
    private var hostingController: UIHostingController<FloorPlanView>?
    
    // MARK: - UI Elements
    
    private lazy var exportButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Export"
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor(red: 0.31, green: 0.80, blue: 0.64, alpha: 1.0) // #4ECCA3
        config.baseForegroundColor = .black
        
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(exportFloorPlan), for: .touchUpInside)
        return button
    }()
    
    private lazy var closeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.baseForegroundColor = .white.withAlphaComponent(0.7)
        
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissView), for: .touchUpInside)
        return button
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Floor Plan"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    
    convenience init(capturedRoom: CapturedRoom) {
        self.init()
        self.capturedRoom = capturedRoom
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        generateFloorPlan()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0) // #1A1A2E
        
        // Add close button
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Add title
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        
        // Add export button
        view.addSubview(exportButton)
        NSLayoutConstraint.activate([
            exportButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
    private func generateFloorPlan() {
        guard let capturedRoom = capturedRoom else {
            showError("No room data available")
            return
        }
        
        // Generate floor plan data
        let generator = FloorPlanGenerator(capturedRoom: capturedRoom)
        floorPlanData = generator.generate()
        
        // Create and embed SwiftUI view
        let floorPlanView = FloorPlanView(floorPlanData: floorPlanData)
        let hostingController = UIHostingController(rootView: floorPlanView)
        hostingController.view.backgroundColor = .clear
        
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(hostingController.view, at: 0)
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }
    
    // MARK: - Actions
    
    @objc private func dismissView() {
        dismiss(animated: true)
    }
    
    @objc private func exportFloorPlan() {
        let alert = UIAlertController(title: "Export Floor Plan", message: "Choose export format", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "PNG Image", style: .default) { [weak self] _ in
            self?.exportAsImage()
        })
        
        alert.addAction(UIAlertAction(title: "PDF Document", style: .default) { [weak self] _ in
            self?.exportAsPDF()
        })
        
        alert.addAction(UIAlertAction(title: "JSON Data", style: .default) { [weak self] _ in
            self?.exportAsJSON()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - Export Methods
    
    private func exportAsImage() {
        guard let hostingController = hostingController else { return }
        
        let renderer = UIGraphicsImageRenderer(size: hostingController.view.bounds.size)
        let image = renderer.image { context in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }
        
        shareItems([image], filename: "FloorPlan.png")
    }
    
    private func exportAsPDF() {
        guard let hostingController = hostingController else { return }
        
        let pdfData = NSMutableData()
        let bounds = hostingController.view.bounds
        
        UIGraphicsBeginPDFContextToData(pdfData, bounds, nil)
        UIGraphicsBeginPDFPage()
        
        guard let pdfContext = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndPDFContext()
            return
        }
        
        hostingController.view.layer.render(in: pdfContext)
        UIGraphicsEndPDFContext()
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.pdf")
        pdfData.write(to: tempURL, atomically: true)
        
        shareItems([tempURL], filename: "FloorPlan.pdf")
    }
    
    private func exportAsJSON() {
        let exportData = FloorPlanExportData(from: floorPlanData)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportData)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.json")
            try jsonData.write(to: tempURL)
            
            shareItems([tempURL], filename: "FloorPlan.json")
        } catch {
            showError("Failed to export JSON: \(error.localizedDescription)")
        }
    }
    
    private func shareItems(_ items: [Any], filename: String) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Export Data Model

struct FloorPlanExportData: Codable {
    var version: String = "1.0"
    let generatedAt: Date
    let totalArea: Double
    let bounds: BoundsData
    let outline: [[Double]]
    let doors: [DoorData]
    let windows: [WindowData]
    let objects: [ObjectData]
    
    struct BoundsData: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    
    struct DoorData: Codable {
        let id: String
        let x: Double
        let y: Double
        let width: Double
        let angle: Double
    }
    
    struct WindowData: Codable {
        let id: String
        let x: Double
        let y: Double
        let width: Double
        let angle: Double
    }
    
    struct ObjectData: Codable {
        let id: String
        let category: String
        let x: Double
        let y: Double
        let width: Double
        let depth: Double
        let angle: Double
    }
    
    init(from data: FloorPlanData) {
        self.generatedAt = Date()
        self.totalArea = Double(data.totalArea)
        self.bounds = BoundsData(
            x: Double(data.bounds.minX),
            y: Double(data.bounds.minY),
            width: Double(data.bounds.width),
            height: Double(data.bounds.height)
        )
        self.outline = data.roomOutline.map { [Double($0.x), Double($0.y)] }
        self.doors = data.doors.map { door in
            DoorData(
                id: door.id.uuidString,
                x: Double(door.position.x),
                y: Double(door.position.y),
                width: Double(door.width),
                angle: Double(door.angle)
            )
        }
        self.windows = data.windows.map { window in
            WindowData(
                id: window.id.uuidString,
                x: Double(window.position.x),
                y: Double(window.position.y),
                width: Double(window.width),
                angle: Double(window.angle)
            )
        }
        self.objects = data.objects.map { obj in
            ObjectData(
                id: obj.id.uuidString,
                category: obj.category.rawValue,
                x: Double(obj.position.x),
                y: Double(obj.position.y),
                width: Double(obj.width),
                depth: Double(obj.depth),
                angle: Double(obj.angle)
            )
        }
    }
}

