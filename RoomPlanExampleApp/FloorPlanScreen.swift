/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI screen that hosts FloorPlanView and provides export/save functionality.
Replaces the UIKit FloorPlanViewController.
*/

import SwiftUI
import RoomPlan

struct FloorPlanScreen: View {
    @Environment(\.dismiss) private var dismiss

    let capturedRoom: CapturedRoom?
    let exportData: FloorPlanExportData?
    let onRetake: (() -> Void)?

    @State private var floorPlanData: FloorPlanData = .empty
    @State private var showExportFormatPicker = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    init(capturedRoom: CapturedRoom, onRetake: (() -> Void)? = nil) {
        self.capturedRoom = capturedRoom
        self.exportData = nil
        self.onRetake = onRetake
    }

    init(exportData: FloorPlanExportData) {
        self.capturedRoom = nil
        self.exportData = exportData
        self.onRetake = nil
    }

    var body: some View {
        FloorPlanView(
            floorPlanData: floorPlanData,
            retakeTitle: "Back",
            onRetake: handleRetake,
            onSave: saveScan,
            onExport: { showExportFormatPicker = true }
        )
        .statusBarHidden(false)
        .onAppear { generateFloorPlan() }
        .confirmationDialog("Export Floor Plan", isPresented: $showExportFormatPicker, titleVisibility: .visible) {
            Button("SVG Image") { exportAsSVG() }
            Button("PNG Image") { exportAsImage() }
            Button("PDF Document") { exportAsPDF() }
            Button("JSON Data") { exportAsJSON() }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerRepresentable(items: shareItems)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Floor Plan Generation

    private func generateFloorPlan() {
        if let exportData = exportData {
            floorPlanData = exportData.toFloorPlanData()
        } else if let capturedRoom = capturedRoom {
            let generator = FloorPlanGenerator(capturedRoom: capturedRoom)
            floorPlanData = generator.generate()
        } else {
            showError("No room data available")
        }
    }

    // MARK: - Navigation

    private func handleRetake() {
        dismiss()
        onRetake?()
    }

    // MARK: - Save

    private func saveScan() {
        guard let image = renderFloorPlanImage() else {
            showError("Failed to generate preview image.")
            return
        }

        let exportPayload = FloorPlanExportData(from: floorPlanData)
        let title = "Scan \(formatDate(Date()))"

        do {
            let store = SavedScansStore()
            let record = try store.saveScan(title: title, exportData: exportPayload, thumbnail: image)
            var usdzErrorMessage: String?

            if let capturedRoom = capturedRoom {
                do {
                    let usdzURL = store.roomUSDZURL(for: record.id)
                    try capturedRoom.export(to: usdzURL, exportOptions: .mesh)
                } catch {
                    usdzErrorMessage = error.localizedDescription
                }
            }

            if let usdzError = usdzErrorMessage {
                showAlert(title: "Saved with Issues", message: "Scan saved, but USDZ export failed: \(usdzError)")
            } else {
                showAlert(title: "Saved", message: "This scan is now available in Saved scans.")
            }
        } catch {
            showError("Failed to save scan: \(error.localizedDescription)")
        }
    }

    // MARK: - Export Methods

    private func exportAsSVG() {
        let exporter = SVGExporter()
        let svgString = exporter.export(floorPlanData)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.svg")

        do {
            try svgString.write(to: tempURL, atomically: true, encoding: .utf8)
            presentShareSheet(items: [tempURL])
        } catch {
            showError("Failed to export SVG: \(error.localizedDescription)")
        }
    }

    private func exportAsImage() {
        guard let image = renderFloorPlanImage() else {
            showError("Failed to generate image.")
            return
        }
        guard let pngData = image.pngData() else {
            showError("Failed to generate PNG data.")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.png")
        do {
            try pngData.write(to: tempURL, options: .atomic)
            presentShareSheet(items: [tempURL])
        } catch {
            showError("Failed to export PNG: \(error.localizedDescription)")
        }
    }

    private func exportAsPDF() {
        guard let image = renderFloorPlanImage() else {
            showError("Failed to generate image for PDF.")
            return
        }

        let pdfData = NSMutableData()
        let imageSize = image.size
        let bounds = CGRect(origin: .zero, size: imageSize)

        UIGraphicsBeginPDFContextToData(pdfData, bounds, nil)
        UIGraphicsBeginPDFPage()

        image.draw(in: bounds)
        UIGraphicsEndPDFContext()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.pdf")
        pdfData.write(to: tempURL, atomically: true)
        presentShareSheet(items: [tempURL])
    }

    private func exportAsJSON() {
        let exportPayload = FloorPlanExportData(from: floorPlanData)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportPayload)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.json")
            try jsonData.write(to: tempURL)
            presentShareSheet(items: [tempURL])
        } catch {
            showError("Failed to export JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func presentShareSheet(items: [Any]) {
        shareItems = items
        showShareSheet = true
    }

    @MainActor
    private func renderFloorPlanImage() -> UIImage? {
        let renderer = ImageRenderer(content:
            FloorPlanView(
                floorPlanData: floorPlanData,
                retakeTitle: "",
                onRetake: {},
                onSave: {},
                onExport: {}
            )
            .frame(width: 390, height: 844)
        )
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private func showError(_ message: String) {
        showAlert(title: "Error", message: message)
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
