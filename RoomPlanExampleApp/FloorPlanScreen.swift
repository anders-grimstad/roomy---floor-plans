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
    let scanTitle: String?
    let onRetake: (() -> Void)?

    @State private var baseFloorPlanData: FloorPlanData = .empty
    @State private var floorPlanData: FloorPlanData = .empty
    @State private var isNorthUpEnabled: Bool
    @State private var savedScanId: String?
    @State private var showExportFormatPicker = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var toastMessage: String?
    @State private var annotationDocument: FloorPlanAnnotationDocument?
    @State private var annotationsLoaded = false
    @State private var annotationsFailedToLoad = false
    @State private var showAnnotationEditor = false

    init(
        capturedRoom: CapturedRoom,
        scanHeading: ScanHeading? = nil,
        northAlignment: ScanNorthAlignment? = nil,
        savedScanId: String? = nil,
        scanTitle: String? = nil,
        onRetake: (() -> Void)? = nil
    ) {
        self.capturedRoom = capturedRoom
        self.exportData = nil
        self.scanHeading = scanHeading
        self.northAlignment = northAlignment
        self.sourceIsNorthUpNormalized = false
        self.scanTitle = scanTitle
        self.onRetake = onRetake
        self._isNorthUpEnabled = State(initialValue: northAlignment?.isReliable ?? false)
        self._savedScanId = State(initialValue: savedScanId)
    }

    init(exportData: FloorPlanExportData, savedScanId: String? = nil, scanTitle: String? = nil) {
        self.capturedRoom = nil
        self.exportData = exportData
        self.scanHeading = exportData.scanHeading
        self.northAlignment = exportData.northAlignment
        self.sourceIsNorthUpNormalized = exportData.isNorthUpNormalized ?? false
        self.scanTitle = scanTitle
        self.onRetake = nil
        let alignmentIsUsable = exportData.northAlignment?.isReliable == true
        let initialNorthUp = alignmentIsUsable ? (exportData.isNorthUpNormalized ?? true) : false
        self._isNorthUpEnabled = State(initialValue: initialNorthUp)
        self._savedScanId = State(initialValue: savedScanId)
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
            onExport: { showExportFormatPicker = true },
            annotationPreview: annotationPreview,
            annotationRotationRadians: annotationRotationRadians,
            onAnnotate: annotationAction
        )
        .statusBarHidden(false)
        .onAppear {
            generateFloorPlan()
            loadAnnotations()
        }
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
        .fullScreenCover(isPresented: $showAnnotationEditor) {
            if #available(iOS 27.0, *), let savedScanId {
                FloorPlanAnnotationEditor(
                    document: annotationDocument,
                    canonicalGeometry: annotationGeometry,
                    displayedPlan: floorPlanData,
                    rotationRadians: annotationRotationRadians,
                    onSave: { document in
                        try FloorPlanAnnotationStore(scanFolder: SavedScansStore().scanFolderURL(for: savedScanId)).save(document)
                        annotationDocument = document
                        toastMessage = "Annotations saved"
                    },
                    onClose: { showAnnotationEditor = false }
                )
                .interactiveDismissDisabled()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .toast(message: $toastMessage)
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

    // MARK: - Annotations

    private var annotationPreview: FloorPlanAnnotationPreview? {
        annotationDocument.flatMap(FloorPlanAnnotationPreview.init)
    }

    private var annotationGeometry: FloorPlanAnnotationGeometry {
        if let annotationDocument { return annotationDocument.geometry }
        let rawPlan = baseFloorPlanData.oriented(
            northAlignment: isNorthUpAvailable ? northAlignment : nil,
            sourceIsNorthUpNormalized: sourceIsNorthUpNormalized,
            desiredNorthUp: false
        )
        return FloorPlanAnnotationGeometry(worldBounds: rawPlan.bounds)
    }

    private var annotationRotationRadians: CGFloat {
        guard isNorthUpEnabled, isNorthUpAvailable, let northAlignment else { return 0 }
        return -CGFloat(northAlignment.normalizedRoomToNorthYawDegrees) * .pi / 180
    }

    private var annotationAction: (() -> Void)? {
        if #available(iOS 27.0, *), !annotationsFailedToLoad,
           floorPlanData.bounds.width > 0, floorPlanData.bounds.height > 0 {
            return openAnnotations
        }
        return nil
    }

    private func loadAnnotations() {
        guard !annotationsLoaded, let savedScanId else { return }
        annotationsLoaded = true
        do {
            annotationDocument = try FloorPlanAnnotationStore(scanFolder: SavedScansStore().scanFolderURL(for: savedScanId)).load()
            if let annotationDocument, FloorPlanAnnotationPreview(document: annotationDocument) == nil {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            annotationsFailedToLoad = true
            showError("Saved annotations could not be opened. Their data has been preserved. \(error.localizedDescription)")
        }
    }

    private func openAnnotations() {
        if savedScanId == nil { saveScan() }
        guard savedScanId != nil else { return }
        loadAnnotations()
        guard !annotationsFailedToLoad else { return }
        showAnnotationEditor = true
    }

    // MARK: - Save

    private func saveScan() {
        guard let thumbnail = renderThumbnailImage() else {
            showError("Failed to generate preview image.")
            return
        }

        let exportPayload = FloorPlanExportData(
            from: floorPlanData,
            scanHeading: scanHeading,
            northAlignment: northAlignment,
            isNorthUpNormalized: isNorthUpEnabled
        )

        do {
            let store = SavedScansStore()
            if let savedScanId {
                try store.updateScan(id: savedScanId, exportData: exportPayload, thumbnail: thumbnail)
                ensureRawAssets(store: store, scanId: savedScanId)
                toastMessage = "Scan updated"
            } else {
                let title = scanTitle ?? "Scan \(formatDate(Date()))"
                let record = try store.saveScan(title: title, exportData: exportPayload, thumbnail: thumbnail)
                savedScanId = record.id
                ensureRawAssets(store: store, scanId: record.id)
                toastMessage = "Saved to library"
            }
        } catch {
            showError("Failed to save scan: \(error.localizedDescription)")
        }
    }

    /// Writes the 3D model and raw RoomPlan data alongside the saved plan when available,
    /// so the scan can be re-viewed in 3D and re-processed later.
    private func ensureRawAssets(store: SavedScansStore, scanId: String) {
        guard let capturedRoom else { return }

        if !store.hasUSDZ(for: scanId) {
            do {
                try capturedRoom.export(to: store.roomUSDZURL(for: scanId), exportOptions: .mesh)
            } catch {
                toastMessage = nil
                showAlert(title: "Saved with Issues", message: "Scan saved, but USDZ export failed: \(error.localizedDescription)")
            }
        }

        let roomJSONURL = store.roomJSONURL(for: scanId)
        if !FileManager.default.fileExists(atPath: roomJSONURL.path) {
            try? JSONEncoder().encode(capturedRoom).write(to: roomJSONURL)
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
        guard let image = renderExportImage(scale: 2) else {
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

    @MainActor
    private func exportAsPDF() {
        let renderer = ImageRenderer(content: exportDocumentView())
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("FloorPlan.pdf")

        var succeeded = false
        renderer.render { size, render in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let context = CGContext(tempURL as CFURL, mediaBox: &mediaBox, nil) else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
            succeeded = true
        }

        guard succeeded else {
            showError("Failed to generate PDF.")
            return
        }
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

    private func exportDocumentView(showsTitleBlock: Bool = true) -> FloorPlanExportView {
        FloorPlanExportView(
            floorPlanData: floorPlanData,
            title: scanTitle ?? "Floor Plan",
            capturedAt: Date(),
            showsTitleBlock: showsTitleBlock,
            annotationPreview: annotationPreview,
            annotationRotationRadians: annotationRotationRadians
        )
    }

    @MainActor
    private func renderExportImage(scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: exportDocumentView())
        renderer.scale = scale
        return renderer.uiImage
    }

    @MainActor
    private func renderThumbnailImage() -> UIImage? {
        let renderer = ImageRenderer(content: exportDocumentView(showsTitleBlock: false))
        renderer.scale = 1
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

// MARK: - Document Export Rendering

/// Chrome-free, document-style floor plan render used for PNG/PDF exports and thumbnails.
/// Sized by the plan's real-world extent (not the phone screen) and finished with a
/// title block — name, date, area, and a scale bar — like an architectural sheet.
struct FloorPlanExportView: View {
    let floorPlanData: FloorPlanData
    let title: String
    let capturedAt: Date
    var showsTitleBlock = true
    var annotationPreview: FloorPlanAnnotationPreview? = nil
    var annotationRotationRadians: CGFloat = 0

    private static let margin: CGFloat = 48
    private static let titleBlockHeight: CGFloat = 96

    private let colors = FloorPlanColors()

    private var drawingBounds: CGRect {
        floorPlanData.bounds.union(annotationPreview?.document.geometry.displayedWorldBounds(rotationRadians: annotationRotationRadians) ?? .null)
    }

    /// Points per meter chosen so the plan's longest side renders around 1000pt.
    private var pointsPerMeter: CGFloat {
        let extent = max(drawingBounds.width, drawingBounds.height)
        guard extent > 0 else { return 100 }
        return min(max(1000 / extent, 50), 250)
    }

    private var canvasSize: CGSize {
        let width = drawingBounds.width * pointsPerMeter + Self.margin * 2
        let height = drawingBounds.height * pointsPerMeter + Self.margin * 2
        return CGSize(width: max(width, 320), height: max(height, 320))
    }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                var drawing = FloorPlanDrawing(data: floorPlanData, colors: colors)
                drawing.options.showDimensions = true
                let transform = drawing.fittingTransform(in: size, padding: Self.margin, including: drawingBounds)
                drawing.draw(in: context, size: size, transform: transform)
                annotationPreview?.draw(in: context, rotationRadians: annotationRotationRadians, worldToView: transform)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            if showsTitleBlock {
                titleBlock
                    .frame(width: canvasSize.width, height: Self.titleBlockHeight)
            }
        }
        .background(colors.background)
        .environment(\.colorScheme, .light)
    }

    private var titleBlock: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ROOMY")
                        .font(.custom("Silkscreen-Bold", size: 16))
                        .tracking(1.5)
                    scaleBar
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: capturedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f m²", Double(floorPlanData.totalArea)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.areaText)
                }
            }
            .padding(.horizontal, Self.margin / 2)
            .frame(maxHeight: .infinity)
        }
    }

    private var scaleBar: some View {
        let candidates: [CGFloat] = [0.5, 1, 2, 5, 10]
        let maxBarWidth = canvasSize.width * 0.3
        let meters = candidates.last(where: { $0 * pointsPerMeter <= maxBarWidth }) ?? 0.5
        let barWidth = meters * pointsPerMeter
        let label = meters == meters.rounded() ? "\(Int(meters)) m" : String(format: "%.1f m", meters)

        return VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .frame(width: barWidth, height: 3)
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
