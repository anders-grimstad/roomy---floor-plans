import Foundation
import RealityKit
import Metal

@main
struct SplatGPURegression {
    @MainActor
    static func main() async throws {
        guard #available(macOS 27.0, *) else {
            print("SKIP: macOS 27 is required for the native GPU resource check")
            return
        }
        guard let gpu = MTLCreateSystemDefaultDevice(), gpu.supportsFamily(.apple7) else {
            print("SKIP: Apple7 GPU family support is unavailable")
            return
        }
        guard CommandLine.arguments.count == 2 else {
            fatalError("Pass a compatible Gaussian PLY file path")
        }
        let cloud = try GaussianSplatFile.read(URL(fileURLWithPath: CommandLine.arguments[1]))
        let preparation = Task.detached { try GaussianSplatPreparedAsset(cloud) }
        let entity = try makeGaussianSplatEntity(try await preparation.value)
        guard let component = entity.components[GaussianSplatComponent.self],
              component.splatResource.bufferResource?.count == cloud.count else {
            fatalError("Loaded Gaussian resource must retain the complete cloud")
        }
        print("Created native GPU Gaussian resource: \(cloud.count) splats on \(gpu.name). Visual rendering remains a separate device check.")
        let gate = AsyncStream<Void>.makeStream()
        let cancelled = Task.detached {
            for await _ in gate.stream { }
            return try GaussianSplatPreparedAsset(cloud)
        }
        cancelled.cancel()
        gate.continuation.finish()
        do {
            _ = try await cancelled.value
            fatalError("Cancelled preparation must not upload a splat asset")
        } catch is CancellationError { }
        print("PASS: cancelled native buffer preparation does not publish an asset")
    }
}
