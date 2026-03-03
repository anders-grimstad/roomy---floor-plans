/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view wrapping the RoomPlan scanning experience.
Replaces the UIKit RoomCaptureViewController.
*/

import SwiftUI
import RoomPlan

// MARK: - UIViewRepresentable wrapper for RoomCaptureView

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    let onCaptureComplete: (CapturedRoom) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = context.coordinator
        captureView.delegate = context.coordinator
        context.coordinator.captureView = captureView
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        let coordinator = context.coordinator
        if isScanning && !coordinator.sessionRunning {
            coordinator.startSession()
        } else if !isScanning && coordinator.sessionRunning {
            coordinator.stopSession()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptureComplete: onCaptureComplete, onError: onError)
    }

    class Coordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
        var captureView: RoomCaptureView?
        var sessionRunning = false
        private let configuration = RoomCaptureSession.Configuration()
        private let onCaptureComplete: (CapturedRoom) -> Void
        private let onError: (String) -> Void

        init(onCaptureComplete: @escaping (CapturedRoom) -> Void,
             onError: @escaping (String) -> Void) {
            self.onCaptureComplete = onCaptureComplete
            self.onError = onError
        }

        func startSession() {
            guard !sessionRunning else { return }
            sessionRunning = true
            captureView?.captureSession.run(configuration: configuration)
        }

        func stopSession() {
            guard sessionRunning else { return }
            sessionRunning = false
            captureView?.captureSession.stop()
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

    var body: some View {
        ZStack {
            // Camera / scanning view
            RoomCaptureViewRepresentable(
                isScanning: $isScanning,
                onCaptureComplete: { room in
                    finalResults = room
                    isProcessing = false
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
                HStack {
                    Button(isScanning ? "Cancel" : "Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    if isScanning {
                        Button("Done") {
                            isScanning = false
                            isProcessing = true
                        }
                        .foregroundStyle(.white)
                    }
                }
                .font(.system(size: 17, weight: .semibold))
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
                    HStack(spacing: 16) {
                        if finalResults != nil {
                            Button {
                                exportUSDZ()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)

                            Button {
                                showFloorPlan = true
                            } label: {
                                Label("Floor Plan", systemImage: "square.split.bottomrightquarter")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.31, green: 0.80, blue: 0.64))
                            .foregroundStyle(.black)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.bottom, 40)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 1.0), value: isScanning)
                }
            }
        }
        .fullScreenCover(isPresented: $showFloorPlan) {
            if let room = finalResults {
                FloorPlanScreen(capturedRoom: room, onRetake: {
                    showFloorPlan = false
                    resetScanState()
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
    }

    // MARK: - Actions

    private func resetScanState() {
        finalResults = nil
        isProcessing = false
        isScanning = true
    }

    private func exportUSDZ() {
        guard let room = finalResults else { return }

        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")

        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            let jsonData = try JSONEncoder().encode(room)
            try jsonData.write(to: capturedRoomURL)
            try room.export(to: destinationURL, exportOptions: .mesh)

            exportItems = [destinationFolderURL]
            showExportShare = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    RoomCaptureSwiftUIView()
}
