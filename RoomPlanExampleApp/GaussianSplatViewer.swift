import SwiftUI
import RealityKit
import Metal
import UniformTypeIdentifiers

struct GaussianSplatViewerScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 27.0, *) {
                    GaussianSplatExperiment()
                } else {
                    ContentUnavailableView("Requires iOS 27", systemImage: "cube.transparent", description: Text("Gaussian splat viewing is available on supported devices running iOS 27 or later."))
                }
            }
            .navigationTitle("Gaussian Splats · Experimental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

@available(iOS 27.0, *)
private struct GaussianSplatExperiment: View {
    @State private var cloud: GaussianSplatFile?
    @State private var entity: Entity?
    @State private var assetName = "Apple plant scan"
    @State private var sourceNote = "Apple sample · © 2026 Apple Inc. · MIT license"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.25
    @State private var zoom: Float = 1
    @State private var dragStart = SIMD2<Float>(0, 0.25)
    @State private var pinchStart: Float = 1

    private var unsupportedReason: String? {
        #if targetEnvironment(simulator)
        return "Gaussian splats require a physical device. Run Roomy on an iPhone or iPad to view this experiment."
        #else
        guard let gpu = MTLCreateSystemDefaultDevice(), gpu.supportsFamily(.apple7) else {
            return "This device does not support the GPU features required for Gaussian splats."
        }
        return nil
        #endif
    }

    var body: some View {
        VStack(spacing: 12) {
            if let reason = unsupportedReason {
                ContentUnavailableView("Device not supported", systemImage: "cube.transparent", description: Text(reason))
            } else {
                ZStack {
                    if let entity, let cloud {
                        GaussianSplatScene(entity: entity, cloud: cloud, yaw: yaw, pitch: pitch, zoom: zoom)
                            .gesture(DragGesture()
                                .onChanged { value in
                                    yaw = dragStart.x - Float(value.translation.width) * 0.008
                                    pitch = min(max(dragStart.y + Float(value.translation.height) * 0.008, -1.4), 1.4)
                                }
                                .onEnded { _ in dragStart = SIMD2(yaw, pitch) })
                            .simultaneousGesture(MagnificationGesture()
                                .onChanged { value in zoom = min(max(pinchStart / Float(value), 0.05), 5) }
                                .onEnded { _ in pinchStart = zoom })
                            .accessibilityLabel("Gaussian splat preview. Drag to orbit and pinch to zoom.")
                    } else {
                        ContentUnavailableView("Open a Gaussian splat", systemImage: "cube.transparent", description: Text("Load the Apple plant sample or import a room scan in Gaussian PLY format."))
                    }
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView("Loading splats…")
                            Button("Cancel") { cancelLoad() }
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if let cloud, entity != nil {
                    Text("\(assetName) · \(cloud.count.formatted()) splats")
                        .font(.headline)
                    Text(sourceNote).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "plus.magnifyingglass")
                        Slider(value: Binding(get: { zoom }, set: { zoom = $0; pinchStart = $0 }), in: 0.05...5)
                            .accessibilityLabel("Camera distance")
                        Image(systemName: "minus.magnifyingglass")
                        Button("Reset", systemImage: "arrow.counterclockwise") { resetCamera() }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Button("Load sample", systemImage: "leaf") { loadSample() }
                    Spacer()
                    Button("Import PLY", systemImage: "square.and.arrow.down") { showImporter = true }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Text("Drag to orbit · Pinch or use the slider to zoom. This experiment displays existing splats; it does not capture or measure rooms.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "ply") ?? .data]) { result in
            switch result {
            case .success(let url): load(url, sample: false)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .task { if unsupportedReason == nil && entity == nil { loadSample() } }
        .onDisappear { cancelLoad() }
    }

    private func loadSample() {
        guard let url = Bundle.main.url(forResource: "plant", withExtension: "ply", subdirectory: "SplatAssets")
                ?? Bundle.main.url(forResource: "plant", withExtension: "ply") else {
            errorMessage = "The bundled plant sample is missing. You can still import a compatible Gaussian PLY file."
            return
        }
        load(url, sample: true)
    }

    private func load(_ url: URL, sample: Bool) {
        cancelLoad()
        isLoading = true
        errorMessage = nil
        loadingTask = Task { @MainActor in
            let parseTask = Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try GaussianSplatPreparedAsset(GaussianSplatFile.read(url))
            }
            do {
                let prepared = try await withTaskCancellationHandler {
                    try await parseTask.value
                } onCancel: { parseTask.cancel() }
                try Task.checkCancellation()
                let loaded = try makeGaussianSplatEntity(prepared)
                try Task.checkCancellation()
                cloud = prepared.cloud
                entity = loaded
                assetName = sample ? "Apple plant scan" : url.deletingPathExtension().lastPathComponent
                sourceNote = sample ? "Apple sample · © 2026 Apple Inc. · MIT license" : "Imported Gaussian PLY · Original capture lighting"
                resetCamera()
                isLoading = false
            } catch is CancellationError {
                // A replacement task owns the loading state after cancellation.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func cancelLoad() {
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
    }

    private func resetCamera() {
        yaw = 0; pitch = 0.25; zoom = 1
        dragStart = SIMD2(0, 0.25); pinchStart = 1
    }
}

@available(iOS 27.0, *)
private struct GaussianSplatScene: UIViewRepresentable {
    let entity: Entity
    let cloud: GaussianSplatFile
    let yaw: Float
    let pitch: Float
    let zoom: Float

    final class Coordinator {
        let camera = PerspectiveCamera()
        let anchor = AnchorEntity(world: .zero)
        var attachedEntity: Entity?
        var center = SIMD3<Float>.zero
        var radius: Float = 1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.systemBackground)
        context.coordinator.camera.camera.fieldOfViewInDegrees = 50
        context.coordinator.camera.camera.near = 0.001
        context.coordinator.camera.camera.far = 10000
        context.coordinator.anchor.addChild(context.coordinator.camera)
        view.scene.addAnchor(context.coordinator.anchor)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.attachedEntity !== entity {
            coordinator.attachedEntity?.removeFromParent()
            coordinator.anchor.addChild(entity)
            coordinator.attachedEntity = entity
            var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for index in stride(from: 0, to: cloud.positions.count, by: 3) {
                let point = SIMD3(cloud.positions[index], cloud.positions[index + 1], cloud.positions[index + 2])
                minimum = simd_min(minimum, point)
                maximum = simd_max(maximum, point)
            }
            coordinator.center = (minimum + maximum) / 2
            coordinator.radius = max(simd_length(maximum - minimum) / 2, 0.01)
        }
        let distance = coordinator.radius * 2.8 * zoom
        let offset = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        coordinator.camera.look(at: coordinator.center, from: coordinator.center + offset, relativeTo: nil)
    }
}
