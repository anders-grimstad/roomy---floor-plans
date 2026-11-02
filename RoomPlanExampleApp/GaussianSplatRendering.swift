import Foundation
import RealityKit
import Metal

// LowLevelBuffer lacks Sendable conformance. These buffers have one writer during
// preparation, then transfer to the main actor and are never mutated again.
@available(iOS 27.0, macOS 27.0, *)
struct GaussianSplatPreparedAsset: @unchecked Sendable {
    let cloud: GaussianSplatFile
    #if !targetEnvironment(simulator)
    fileprivate let position: GaussianSplatResource.BufferDescriptor
    fileprivate let scale: GaussianSplatResource.BufferDescriptor
    fileprivate let rotation: GaussianSplatResource.BufferDescriptor
    fileprivate let opacity: GaussianSplatResource.BufferDescriptor
    fileprivate let harmonics: GaussianSplatResource.BufferDescriptor
    #endif

    init(_ cloud: GaussianSplatFile) throws {
        try Task.checkCancellation()
        #if targetEnvironment(simulator)
        throw GaussianSplatFileError.invalid("Gaussian splats require a physical device.")
        #else
        func descriptor(_ values: [Float], tuple: Int) throws -> GaussianSplatResource.BufferDescriptor {
            try Task.checkCancellation()
            let byteCount = values.count * MemoryLayout<Float>.stride
            let alignedCount = (byteCount + 15) & ~15
            let buffer = try LowLevelBuffer(descriptor: .init(capacity: alignedCount, sizeMultiple: 16))
            var cancelled = false
            buffer.withUnsafeMutableBytes { destination in
                values.withUnsafeBytes { source in
                    for offset in stride(from: 0, to: byteCount, by: 1024 * 1024) {
                        if Task.isCancelled { cancelled = true; break }
                        let size = min(1024 * 1024, byteCount - offset)
                        destination.baseAddress!.advanced(by: offset).copyMemory(from: source.baseAddress!.advanced(by: offset), byteCount: size)
                    }
                }
            }
            if cancelled { throw CancellationError() }
            return .init(buffer: buffer, format: tuple == 4 ? .float4 : tuple == 1 ? .float : .float3,
                         stride: tuple * MemoryLayout<Float>.stride, offset: 0)
        }
        let shTriplets = (Int(cloud.degree) + 1) * (Int(cloud.degree) + 1)
        self.position = try descriptor(cloud.positions, tuple: 3)
        self.scale = try descriptor(cloud.scales, tuple: 3)
        self.rotation = try descriptor(cloud.rotations, tuple: 4)
        self.opacity = try descriptor(cloud.opacities, tuple: 1)
        self.harmonics = try descriptor(cloud.harmonics, tuple: shTriplets * 3)
        try Task.checkCancellation()
        self.cloud = cloud
        #endif
    }
}

@available(iOS 27.0, macOS 27.0, *)
@MainActor
func makeGaussianSplatEntity(_ prepared: GaussianSplatPreparedAsset) throws -> Entity {
    #if targetEnvironment(simulator)
    throw GaussianSplatFileError.invalid("Gaussian splats require a physical device.")
    #else
    let buffers = try GaussianSplatResource.BufferResource(count: prepared.cloud.count,
        position: prepared.position, scale: prepared.scale, rotation: prepared.rotation, opacity: prepared.opacity,
        sphericalHarmonics: (prepared.harmonics, .init(rawValue: prepared.cloud.degree)!))
    let resource = GaussianSplatResource(buffers)
    resource.scaleActivation = .exponential
    resource.opacityActivation = .sigmoid
    let entity = Entity()
    entity.components.set(GaussianSplatComponent(resource))
    return entity
    #endif
}
