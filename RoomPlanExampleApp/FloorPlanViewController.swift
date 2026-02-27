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
    private var exportData: FloorPlanExportData?
    private var onRetake: (() -> Void)?
    private var floorPlanData: FloorPlanData = .empty
    private var hostingController: UIHostingController<FloorPlanView>?
    private var wasNavBarHidden: Bool?
    
    // MARK: - Initialization
    
    init(capturedRoom: CapturedRoom, onRetake: (() -> Void)? = nil) {
        self.capturedRoom = capturedRoom
        self.onRetake = onRetake
        super.init(nibName: nil, bundle: nil)
    }

    init(exportData: FloorPlanExportData) {
        self.exportData = exportData
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    convenience init(capturedRoom: CapturedRoom) {
        self.init(capturedRoom: capturedRoom, onRetake: nil)
        self.capturedRoom = capturedRoom
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0) // #1A1A2E
        generateFloorPlan()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let navigationController = navigationController {
            wasNavBarHidden = navigationController.isNavigationBarHidden
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationItem.hidesBackButton = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let navigationController = navigationController, let wasNavBarHidden = wasNavBarHidden {
            navigationController.setNavigationBarHidden(wasNavBarHidden, animated: false)
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    private func generateFloorPlan() {
        if let exportData = exportData {
            floorPlanData = exportData.toFloorPlanData()
        } else if let capturedRoom = capturedRoom {
            let generator = FloorPlanGenerator(capturedRoom: capturedRoom)
            floorPlanData = generator.generate()
        } else {
            showError("No room data available")
            return
        }
        
        // Create and embed SwiftUI view
        let retakeTitle = capturedRoom == nil ? "Back" : "Retake"
        let floorPlanView = FloorPlanView(
            floorPlanData: floorPlanData,
            retakeTitle: retakeTitle,
            onRetake: { [weak self] in
                self?.handleRetake()
            },
            onSave: { [weak self] in
                self?.saveScan()
            },
            onExport: { [weak self] in
                self?.exportFloorPlan()
            }
        )
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
    
    @objc private func exportFloorPlan() {
        let alert = UIAlertController(title: "Export Floor Plan", message: "Choose export format", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "SVG Image", style: .default) { [weak self] _ in
            self?.exportAsSVG()
        })
        
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
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        
        present(alert, animated: true)
    }
    
    // MARK: - Export Methods
    
    private func exportAsSVG() {
        let exporter = SVGExporter()
        let svgString = exporter.export(floorPlanData)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.svg")
        
        do {
            try svgString.write(to: tempURL, atomically: true, encoding: .utf8)
            shareItems([tempURL], filename: "FloorPlan.svg")
        } catch {
            showError("Failed to export SVG: \(error.localizedDescription)")
        }
    }
    
    private func exportAsImage() {
        guard let image = renderFloorPlanImage() else { return }
        guard let pngData = image.pngData() else {
            showError("Failed to generate PNG data.")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.png")
        do {
            try pngData.write(to: tempURL, options: .atomic)
            let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size]) as? NSNumber
            shareItems([tempURL], filename: "FloorPlan.png")
        } catch {
            showError("Failed to export PNG: \(error.localizedDescription)")
        }
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
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func handleRetake() {
        if let navigationController = navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
        onRetake?()
    }

    private func renderFloorPlanImage() -> UIImage? {
        guard let hostingController = hostingController else { return nil }
        hostingController.view.layoutIfNeeded()
        let size = hostingController.view.bounds.size == .zero ? view.bounds.size : hostingController.view.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            hostingController.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private func saveScan() {
        guard let thumbnail = renderFloorPlanImage() else {
            showError("Failed to generate preview image.")
            return
        }

        let exportData = FloorPlanExportData(from: floorPlanData)
        let title = "Scan \(formatDate(Date()))"

        do {
            let store = SavedScansStore()
            let record = try store.saveScan(title: title, exportData: exportData, thumbnail: thumbnail)
            var usdzErrorMessage: String?

            if let capturedRoom = capturedRoom {
                do {
                    let usdzURL = store.roomUSDZURL(for: record.id)
                    try capturedRoom.export(to: usdzURL, exportOptions: .mesh)
                } catch {
                    usdzErrorMessage = error.localizedDescription
                }
            }

            let alertTitle = usdzErrorMessage == nil ? "Saved" : "Saved with Issues"
            let alertMessage: String
            if let usdzErrorMessage = usdzErrorMessage {
                alertMessage = "Scan saved, but USDZ export failed: \(usdzErrorMessage)"
            } else {
                alertMessage = "This scan is now available in Saved scans."
            }

            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            showError("Failed to save scan: \(error.localizedDescription)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

