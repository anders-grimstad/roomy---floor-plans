/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view wrapping the RoomPlan scanning experience.
Replaces the UIKit RoomCaptureViewController.
*/

import SwiftUI
import ARKit
import RoomPlan

private enum NorthCalibrationSettings {
    static let headingMatchMaxAge: TimeInterval = 0.35
    static let maxHeadingAccuracyForSample: Double = 22
    static let maxHeadingAccuracyForLock: Double = 18
    static let minSamplesForLock = 4
    static let maxSamplesForLock = 12
    static let maxCollectionWindow: TimeInterval = 1.5
    static let minHeadingSampleSpacing: TimeInterval = 0.2
    static let outlierCutoffDegrees: Double = 12
    static let maxSpreadForLock: Double = 10
    static let trackingWarmupDuration: TimeInterval = 0.7
    static let minimumCalibrationFrameInterval: TimeInterval = 0.12
}

private struct NorthCalibrationSample {
    let headingDegrees: Double
    let cameraYawDegrees: Double
    let headingAccuracyDegrees: Double?
    let reference: ScanHeading.Reference
    let headingCapturedAt: Date
    let sampleDate: Date
}

private struct NorthCalibrationEstimate {
    let roomToNorthYawDegrees: Double
    let reference: ScanHeading.Reference
    let representativeAccuracyDegrees: Double
    let sampleCount: Int
    let spreadDegrees: Double
    let confidence: HeadingConfidenceState
    let calibrationMethod: String
    let calibrationHeadingDegrees: Double
    let calibrationCameraYawDegrees: Double
}

// MARK: - UIViewRepresentable wrapper for RoomCaptureView

@objc(RoomCaptureCoordinator)
class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ARSessionDelegate, NSCoding {
    var captureView: RoomCaptureView?
    var sessionRunning = false
    var preferNorthAlignedCapture: Bool
    let arSession: ARSession
    private var hasAppliedWorldAlignment = false
    private var hasCalibratedNorthAlignment = false
    private var lastRecalibrationToken = 0
    private var trackingBecameNormalAt: TimeInterval?
    private var lastCalibrationAttemptAt: TimeInterval = 0
    private let configuration = RoomCaptureSession.Configuration()
    private let onCaptureComplete: (CapturedRoom) -> Void
    private let onCalibrationSample: (Double, Date) -> Bool
    private let onError: (String) -> Void

    init(onCaptureComplete: @escaping (CapturedRoom) -> Void,
         onCalibrationSample: @escaping (Double, Date) -> Bool,
         onError: @escaping (String) -> Void,
         preferNorthAlignedCapture: Bool) {
        self.onCaptureComplete = onCaptureComplete
        self.onCalibrationSample = onCalibrationSample
        self.onError = onError
        self.preferNorthAlignedCapture = preferNorthAlignedCapture
        self.arSession = ARSession()
        super.init()
        self.arSession.delegate = self
        self.arSession.delegateQueue = .main
    }

    // NSCoding conformance required by RoomCaptureViewDelegate
    func encode(with coder: NSCoder) {}

    required init?(coder: NSCoder) {
        self.onCaptureComplete = { _ in }
        self.onCalibrationSample = { _, _ in false }
        self.onError = { _ in }
        self.preferNorthAlignedCapture = false
        self.arSession = ARSession()
        super.init()
        self.arSession.delegate = self
        self.arSession.delegateQueue = .main
    }

    func startSession() {
        guard !sessionRunning else { return }
        sessionRunning = true
        hasCalibratedNorthAlignment = false
        trackingBecameNormalAt = nil
        lastCalibrationAttemptAt = 0
        applyWorldAlignmentIfNeeded()
        captureView?.captureSession.run(configuration: configuration)
    }

    func stopSession() {
        guard sessionRunning else { return }
        sessionRunning = false
        captureView?.captureSession.stop()
        hasAppliedWorldAlignment = false
    }

    func handleRecalibrationToken(_ token: Int) {
        guard token > lastRecalibrationToken else { return }
        lastRecalibrationToken = token
        hasCalibratedNorthAlignment = false
        trackingBecameNormalAt = nil
        lastCalibrationAttemptAt = 0
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error = error {
            onError(error.localizedDescription)
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            onError(error.localizedDescription)
            return
        }
        onCaptureComplete(processedResult)
    }

    // MARK: - RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error = error {
            onError(error.localizedDescription)
        }
    }

    func applyWorldAlignmentIfNeeded() {
        guard preferNorthAlignedCapture, !hasAppliedWorldAlignment else { return }
        hasAppliedWorldAlignment = true
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard sessionRunning, !hasCalibratedNorthAlignment else { return }
        guard isTrackingStable(frame: frame) else { return }
        guard frame.timestamp - lastCalibrationAttemptAt >= NorthCalibrationSettings.minimumCalibrationFrameInterval else { return }
        lastCalibrationAttemptAt = frame.timestamp

        // ARKit camera forward is -Z in camera space. Use the forward vector in world space,
        // not the camera's positive Z axis (which points backward), to avoid 180-degree flips.
        let forwardX = -frame.camera.transform[2][0]
        let forwardZ = -frame.camera.transform[2][2]
        let cameraYawDegrees = Self.normalizedDegrees(
            atan2(forwardX, forwardZ) * 180 / .pi
        )
        let didCalibrate = onCalibrationSample(cameraYawDegrees, Self.frameDate(from: frame.timestamp))
        if didCalibrate {
            hasCalibratedNorthAlignment = true
        }
    }

    private func isTrackingStable(frame: ARFrame) -> Bool {
        if case .normal = frame.camera.trackingState {
            if trackingBecameNormalAt == nil {
                trackingBecameNormalAt = frame.timestamp
            }
            guard let trackingBecameNormalAt else { return false }
            return frame.timestamp - trackingBecameNormalAt >= NorthCalibrationSettings.trackingWarmupDuration
        } else {
            trackingBecameNormalAt = nil
            return false
        }
    }

    private static func frameDate(from timestamp: TimeInterval) -> Date {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let age = uptime - timestamp
        guard age.isFinite, age >= 0, age <= 5 else { return now }
        return now.addingTimeInterval(-age)
    }

    private static func normalizedDegrees(_ degrees: Float) -> Double {
        let value = Double(degrees).truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    let recalibrationToken: Int
    let preferNorthAlignedCapture: Bool
    let onCaptureComplete: (CapturedRoom) -> Void
    let onCalibrationSample: (Double, Date) -> Bool
    let onError: (String) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero, arSession: context.coordinator.arSession)
        captureView.captureSession.delegate = context.coordinator
        captureView.delegate = context.coordinator
        context.coordinator.captureView = captureView
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        let coordinator = context.coordinator
        coordinator.handleRecalibrationToken(recalibrationToken)
        coordinator.preferNorthAlignedCapture = preferNorthAlignedCapture
        if coordinator.sessionRunning {
            coordinator.applyWorldAlignmentIfNeeded()
        }
        if isScanning && !coordinator.sessionRunning {
            coordinator.startSession()
        } else if !isScanning && coordinator.sessionRunning {
            coordinator.stopSession()
        }
    }

    func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(
            onCaptureComplete: onCaptureComplete,
            onCalibrationSample: onCalibrationSample,
            onError: onError,
            preferNorthAlignedCapture: preferNorthAlignedCapture
        )
    }
}

// MARK: - Scanning Screen

struct RoomCaptureSwiftUIView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = true
    @State private var finalResults: CapturedRoom?
    @State private var isProcessing = false
    @State private var showFloorPlan = false
    @State private var showExportShare = false
    @State private var exportItems: [Any] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var scanHeading: ScanHeading?
    @State private var northAlignment: ScanNorthAlignment?
    @State private var recalibrationToken = 0
    @State private var calibrationWindowStart: Date?
    @State private var calibrationSamples: [NorthCalibrationSample] = []
    @StateObject private var headingManager = HeadingManager()

    var body: some View {
        ZStack {
            // Camera / scanning view
            RoomCaptureViewRepresentable(
                isScanning: $isScanning,
                recalibrationToken: recalibrationToken,
                preferNorthAlignedCapture: headingManager.status == .active,
                onCaptureComplete: { room in
                    finalResults = room
                    isProcessing = false
                    scanHeading = scanHeading ?? snapshotHeadingForDisplay()
                },
                onCalibrationSample: { cameraYawDegrees, sampleDate in
                    calibrateNorthAlignment(cameraYawDegrees: cameraYawDegrees, sampleDate: sampleDate)
                },
                onError: { message in
                    errorMessage = message
                    showError = true
                }
            )
            .ignoresSafeArea()

            // Overlaid controls
            VStack {
                // Top navigation bar
                topNavigationBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer()

                // Processing indicator
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                }

                Spacer()

                // Bottom buttons (visible after scanning stops)
                if !isScanning && !isProcessing {
                    bottomButtons
                        .padding(.bottom, 40)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 1.0), value: isScanning)
                }
            }
        }
        .fullScreenCover(isPresented: $showFloorPlan) {
            if let room = finalResults {
                FloorPlanScreen(capturedRoom: room, scanHeading: scanHeading, northAlignment: northAlignment, onRetake: {
                    showFloorPlan = false
                })
            }
        }
        .sheet(isPresented: $showExportShare) {
            ActivityViewControllerRepresentable(items: exportItems)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            if isScanning {
                headingManager.resetHistory()
                headingManager.start()
            }
        }
        .onDisappear {
            headingManager.stop()
        }
        .onChange(of: isScanning, initial: false) {
            let scanning = isScanning
            if scanning {
                resetCalibrationState(clearAlignment: true)
                headingManager.resetHistory()
                headingManager.start()
            } else {
                scanHeading = scanHeading ?? snapshotHeadingForDisplay()
                headingManager.stop()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var topNavigationBar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                topNavigationContent
            }
        } else {
            topNavigationContent
        }
    }

    @ViewBuilder
    private var topNavigationContent: some View {
        if !isScanning && !isProcessing && finalResults != nil {
            // Results shown: Retake | 3D View | Cancel
            resultsNavigationBar
        } else {
            // Scanning / Processing: Cancel | Done
            scanningNavigationBar
        }
    }

    private var scanningNavigationBar: some View {
        HStack {
            if #available(iOS 26.0, *) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
            } else {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            if isScanning {
                if #available(iOS 26.0, *) {
                    Button("Recalibrate") {
                        requestManualRecalibration()
                    }
                    .buttonStyle(.glass)
                    .disabled(headingManager.status != .active)
                } else {
                    Button("Recalibrate") {
                        requestManualRecalibration()
                    }
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
                    .disabled(headingManager.status != .active)
                }
            }

            Spacer()

            if isScanning {
                if #available(iOS 26.0, *) {
                    Button("Done") {
                        isScanning = false
                        isProcessing = true
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("Done") {
                        isScanning = false
                        isProcessing = true
                    }
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private var resultsNavigationBar: some View {
        HStack {
            if #available(iOS 26.0, *) {
                Button("Retake") { resetScanState() }
                    .buttonStyle(.glass)
            } else {
                Button("Retake") { resetScanState() }
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            Text("3D View")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            if #available(iOS 26.0, *) {
                Button("2D View") { showFloorPlan = true }
                    .buttonStyle(.glass)
            } else {
                Button("2D View") { showFloorPlan = true }
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                bottomButtonsContent
            }
        } else {
            bottomButtonsContent
        }
    }

    private var bottomButtonsContent: some View {
        VStack {
            if finalResults != nil {
                if #available(iOS 26.0, *) {
                    Button {
                        exportUSDZ()
                    } label: {
                        Label("Export 3D", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        exportUSDZ()
                    } label: {
                        Label("Export 3D", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func resetScanState() {
        finalResults = nil
        isProcessing = false
        isScanning = true
        resetCalibrationState(clearAlignment: true)
    }

    private func requestManualRecalibration() {
        guard isScanning else { return }
        resetCalibrationState(clearAlignment: true)
        recalibrationToken += 1
    }

    private func resetCalibrationState(clearAlignment: Bool) {
        calibrationWindowStart = nil
        calibrationSamples.removeAll()
        scanHeading = nil
        if clearAlignment {
            northAlignment = nil
        }
    }

    private func exportUSDZ() {
        guard let room = finalResults else { return }

        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")
        let metadataURL = destinationFolderURL.appending(path: "Room.metadata.json")

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            let jsonData = try JSONEncoder().encode(room)
            try jsonData.write(to: capturedRoomURL)
            try room.export(to: destinationURL, exportOptions: .mesh)

            let metadata = RoomExportMetadata(
                generatedAt: Date(),
                scanHeading: scanHeading,
                northAlignment: northAlignment
            )
            let metadataEncoder = JSONEncoder()
            metadataEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            metadataEncoder.dateEncodingStrategy = .iso8601
            let metadataData = try metadataEncoder.encode(metadata)
            try metadataData.write(to: metadataURL)

            exportItems = [destinationFolderURL]
            showExportShare = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func calibrateNorthAlignment(cameraYawDegrees: Double, sampleDate: Date) -> Bool {
        guard northAlignment == nil else { return true }
        if calibrationWindowStart == nil {
            calibrationWindowStart = sampleDate
        }

        calibrationSamples.removeAll {
            sampleDate.timeIntervalSince($0.sampleDate) > NorthCalibrationSettings.maxCollectionWindow
        }

        guard let heading = headingManager.bestCameraHeadingSample(
            near: sampleDate,
            maxAge: NorthCalibrationSettings.headingMatchMaxAge,
            maxAccuracy: NorthCalibrationSettings.maxHeadingAccuracyForSample
        ) else {
            rollCalibrationWindowIfNeeded(now: sampleDate)
            return false
        }
        if scanHeading == nil {
            scanHeading = headingManager.bestHeadingSample(
                near: sampleDate,
                maxAge: NorthCalibrationSettings.headingMatchMaxAge,
                maxAccuracy: NorthCalibrationSettings.maxHeadingAccuracyForSample
            ) ?? heading
        }

        if let lastSample = calibrationSamples.last,
           abs(lastSample.headingCapturedAt.timeIntervalSince(heading.capturedAt)) < NorthCalibrationSettings.minHeadingSampleSpacing {
            rollCalibrationWindowIfNeeded(now: sampleDate)
            return false
        }

        calibrationSamples.append(
            NorthCalibrationSample(
                headingDegrees: heading.normalizedDegrees,
                cameraYawDegrees: cameraYawDegrees,
                headingAccuracyDegrees: heading.accuracyDegrees,
                reference: heading.reference,
                headingCapturedAt: heading.capturedAt,
                sampleDate: sampleDate
            )
        )

        if calibrationSamples.count > NorthCalibrationSettings.maxSamplesForLock {
            calibrationSamples.removeFirst(calibrationSamples.count - NorthCalibrationSettings.maxSamplesForLock)
        }

        guard let estimate = buildCalibrationEstimate(from: calibrationSamples) else {
            rollCalibrationWindowIfNeeded(now: sampleDate)
            return false
        }

        northAlignment = ScanNorthAlignment(
            roomToNorthYawDegrees: estimate.roomToNorthYawDegrees,
            reference: estimate.reference,
            accuracyDegrees: estimate.representativeAccuracyDegrees,
            calibratedAt: sampleDate,
            calibrationMethod: estimate.calibrationMethod,
            calibrationHeadingDegrees: estimate.calibrationHeadingDegrees,
            calibrationCameraYawDegrees: estimate.calibrationCameraYawDegrees,
            sampleCount: estimate.sampleCount,
            spreadDegrees: estimate.spreadDegrees,
            confidence: estimate.confidence
        )
        return true
    }

    private func rollCalibrationWindowIfNeeded(now: Date) {
        guard let calibrationWindowStart else { return }
        guard now.timeIntervalSince(calibrationWindowStart) >= NorthCalibrationSettings.maxCollectionWindow else { return }
        self.calibrationWindowStart = now
        calibrationSamples.removeAll()
    }

    private func buildCalibrationEstimate(from samples: [NorthCalibrationSample]) -> NorthCalibrationEstimate? {
        let candidates = samples.filter {
            guard let accuracy = $0.headingAccuracyDegrees else { return false }
            return accuracy <= NorthCalibrationSettings.maxHeadingAccuracyForSample
        }
        guard candidates.count >= NorthCalibrationSettings.minSamplesForLock else { return nil }

        return evaluateCalibrationCandidate(
            from: candidates,
            methodName: "multiSampleCaptureStart_cameraForwardHeadingMinusYaw",
            transform: { sample in
                normalizedDegrees(sample.headingDegrees - sample.cameraYawDegrees)
            }
        )
    }

    private func evaluateCalibrationCandidate(
        from candidates: [NorthCalibrationSample],
        methodName: String,
        transform: (NorthCalibrationSample) -> Double
    ) -> NorthCalibrationEstimate? {
        let deltas = candidates.map(transform)
        let initialMean = circularMean(deltas)
        let inliers = zip(candidates, deltas).filter { _, delta in
            angularDistanceDegrees(delta, initialMean) <= NorthCalibrationSettings.outlierCutoffDegrees
        }
        guard inliers.count >= NorthCalibrationSettings.minSamplesForLock else { return nil }

        let inlierDeltas = inliers.map { $0.1 }
        let finalYaw = circularMean(inlierDeltas)
        let spread = circularRmsDistance(inlierDeltas, around: finalYaw)
        guard spread <= NorthCalibrationSettings.maxSpreadForLock else { return nil }

        let inlierSamples = inliers.map { $0.0 }
        let representativeAccuracy = median(inlierSamples.compactMap(\.headingAccuracyDegrees))
        guard let representativeAccuracy else { return nil }
        guard representativeAccuracy <= NorthCalibrationSettings.maxHeadingAccuracyForLock else { return nil }

        let reference: ScanHeading.Reference = inlierSamples.contains(where: { $0.reference == .trueNorth }) ? .trueNorth : .magneticNorth
        let confidence = alignmentConfidence(
            reference: reference,
            representativeAccuracy: representativeAccuracy,
            spread: spread,
            sampleCount: inlierSamples.count
        )

        return NorthCalibrationEstimate(
            roomToNorthYawDegrees: finalYaw,
            reference: reference,
            representativeAccuracyDegrees: representativeAccuracy,
            sampleCount: inlierSamples.count,
            spreadDegrees: spread,
            confidence: confidence,
            calibrationMethod: methodName,
            calibrationHeadingDegrees: circularMean(inlierSamples.map(\.headingDegrees)),
            calibrationCameraYawDegrees: circularMean(inlierSamples.map(\.cameraYawDegrees))
        )
    }

    private func alignmentConfidence(
        reference: ScanHeading.Reference,
        representativeAccuracy: Double,
        spread: Double,
        sampleCount: Int
    ) -> HeadingConfidenceState {
        if sampleCount >= 6 && spread <= 4 && representativeAccuracy <= 8 && reference == .trueNorth {
            return .high
        }
        if sampleCount >= NorthCalibrationSettings.minSamplesForLock &&
            spread <= NorthCalibrationSettings.maxSpreadForLock &&
            representativeAccuracy <= NorthCalibrationSettings.maxHeadingAccuracyForLock {
            return .medium
        }
        if representativeAccuracy <= ScanHeading.lowConfidenceAccuracyThreshold {
            return .low
        }
        return .uncalibrated
    }

    private func circularMean(_ degrees: [Double]) -> Double {
        guard !degrees.isEmpty else { return 0 }

        let sumSin = degrees.reduce(0.0) { partial, value in
            partial + sin(value * .pi / 180)
        }
        let sumCos = degrees.reduce(0.0) { partial, value in
            partial + cos(value * .pi / 180)
        }
        if abs(sumSin) < 0.0001 && abs(sumCos) < 0.0001 {
            return normalizedDegrees(degrees[0])
        }
        return normalizedDegrees(atan2(sumSin, sumCos) * 180 / .pi)
    }

    private func angularDistanceDegrees(_ a: Double, _ b: Double) -> Double {
        let delta = (a - b + 540).truncatingRemainder(dividingBy: 360) - 180
        return abs(delta)
    }

    private func circularRmsDistance(_ degrees: [Double], around center: Double) -> Double {
        guard !degrees.isEmpty else { return 0 }
        let squared = degrees.map { value in
            let distance = angularDistanceDegrees(value, center)
            return distance * distance
        }
        let meanSquared = squared.reduce(0, +) / Double(squared.count)
        return sqrt(meanSquared)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func snapshotHeadingForDisplay() -> ScanHeading? {
        if let calibratedAt = northAlignment?.calibratedAt,
           let headingAtCalibration = headingManager.snapshotHeading(near: calibratedAt, maxAge: 2.0) {
            return headingAtCalibration
        }
        return headingManager.snapshotHeading()
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

#Preview {
    RoomCaptureSwiftUIView()
}
