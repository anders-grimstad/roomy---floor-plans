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
    let scanHeading: ScanHeading?
    let northAlignment: ScanNorthAlignment?
    let sourceIsNorthUpNormalized: Bool
    let onRetake: (() -> Void)?

    @State private var baseFloorPlanData: FloorPlanData = .empty
    @State private var floorPlanData: FloorPlanData = .empty
    @State private var isNorthUpEnabled: Bool
    @State private var showExportFormatPicker = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    init(
        capturedRoom: CapturedRoom,
        scanHeading: ScanHeading? = nil,
        northAlignment: ScanNorthAlignment? = nil,
        onRetake: (() -> Void)? = nil
    ) {
        self.capturedRoom = capturedRoom
        self.exportData = nil
        self.scanHeading = scanHeading
        self.northAlignment = northAlignment
        self.sourceIsNorthUpNormalized = false
        self.onRetake = onRetake
        self._isNorthUpEnabled = State(initialValue: northAlignment?.isReliable ?? false)
    }

    init(exportData: FloorPlanExportData) {
        self.capturedRoom = nil
        self.exportData = exportData
        self.scanHeading = exportData.scanHeading
        self.northAlignment = exportData.northAlignment
        self.sourceIsNorthUpNormalized = exportData.isNorthUpNormalized ?? false
        self.onRetake = nil
        let alignmentIsUsable = exportData.northAlignment?.isReliable == true
        let initialNorthUp = alignmentIsUsable ? (exportData.isNorthUpNormalized ?? true) : false
        self._isNorthUpEnabled = State(initialValue: initialNorthUp)
    }

    var body: some View {
        FloorPlanView(
            floorPlanData: floorPlanData,
            scanHeading: scanHeading,
            yawDegrees: displayYawDegrees,
            isNorthUpEnabled: isNorthUpEnabled,
            canToggleNorthUp: isNorthUpAvailable,
            northUpStatusMessage: northUpStatusMessage,
            retakeTitle: "Back",
            onRetake: handleRetake,
            onSave: saveScan,
            onToggleNorthUp: toggleNorthUp,
            onExport: { showExportFormatPicker = true }
        )
        .statusBarHidden(false)
        .onAppear { generateFloorPlan() }
        .onChange(of: isNorthUpEnabled, initial: false) {
            applyFloorPlanOrientation()
        }
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
            baseFloorPlanData = exportData.toFloorPlanData()
        } else if let capturedRoom = capturedRoom {
            let generator = FloorPlanGenerator(capturedRoom: capturedRoom)
            baseFloorPlanData = generator.generate()
        } else {
            baseFloorPlanData = .empty
            floorPlanData = .empty
            showError("No room data available")
            return
        }

        applyFloorPlanOrientation()
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

        let exportPayload = FloorPlanExportData(
            from: floorPlanData,
            scanHeading: scanHeading,
            northAlignment: northAlignment,
            isNorthUpNormalized: isNorthUpEnabled
        )
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
        let svgString = exporter.export(floorPlanData, scanHeading: scanHeading)
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
        let exportPayload = FloorPlanExportData(
            from: floorPlanData,
            scanHeading: scanHeading,
            northAlignment: northAlignment,
            isNorthUpNormalized: isNorthUpEnabled
        )

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
                scanHeading: scanHeading,
                yawDegrees: displayYawDegrees,
                isNorthUpEnabled: isNorthUpEnabled,
                canToggleNorthUp: isNorthUpAvailable,
                northUpStatusMessage: northUpStatusMessage,
                retakeTitle: "",
                onRetake: {},
                onSave: {},
                onToggleNorthUp: {},
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

    private func toggleNorthUp() {
        guard isNorthUpAvailable else { return }
        isNorthUpEnabled.toggle()
    }

    private func applyFloorPlanOrientation() {
        let usableAlignment = isNorthUpAvailable ? northAlignment : nil
        floorPlanData = baseFloorPlanData.oriented(
            northAlignment: usableAlignment,
            sourceIsNorthUpNormalized: sourceIsNorthUpNormalized,
            desiredNorthUp: isNorthUpEnabled
        )
    }

    private var isNorthUpAvailable: Bool {
        northAlignment?.isReliable == true
    }

    private var northUpStatusMessage: String? {
        if let northAlignment {
            if northAlignment.isReliable {
                return northAlignment.statusLabel
            }
            return northAlignment.unavailableReason
        }

        if let scanHeading, !scanHeading.isReliable {
            if let accuracy = scanHeading.accuracyDegrees {
                return "North-up unavailable: heading accuracy is low (±\(Int(accuracy.rounded()))°)."
            }
            return "North-up unavailable: compass is uncalibrated."
        }
        return "North-up unavailable: no calibrated north alignment for this scan."
    }

    private var displayYawDegrees: Double? {
        if let calibrationYaw = northAlignment?.calibrationCameraYawDegrees {
            return normalizedDegrees(calibrationYaw)
        }
        guard let scanHeading, let northAlignment else { return nil }
        let cameraYaw = scanHeading.normalizedDegrees - northAlignment.normalizedRoomToNorthYawDegrees
        return normalizedDegrees(cameraYaw)
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
