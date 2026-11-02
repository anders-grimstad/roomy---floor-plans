import Foundation
import RealityKit
import Metal
import CoreGraphics
import ImageIO

/// Offscreen native rendering of the real Apple object capture, not an iPhone UI test.
@main
struct SplatRendering {
    @MainActor
    static func main() async throws {
        guard #available(macOS 27.0, *), let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.apple7) else {
            print("SKIP: native rendering requires macOS 27 and an Apple7 GPU")
            return
        }
        let cloud = try GaussianSplatFile.read(URL(fileURLWithPath: "RoomPlanExampleApp/SplatAssets/plant.ply"))
        let preparation = Task.detached { try GaussianSplatPreparedAsset(cloud) }
        let entity = try makeGaussianSplatEntity(try await preparation.value)
        let camera = PerspectiveCamera()
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in stride(from: 0, to: cloud.positions.count, by: 3) {
            let p = SIMD3(cloud.positions[i], cloud.positions[i + 1], cloud.positions[i + 2])
            minimum = simd_min(minimum, p)
            maximum = simd_max(maximum, p)
        }
        let center = (minimum + maximum) / 2
        let radius = max(simd_length(maximum - minimum) / 2, 0.01)
        camera.camera.fieldOfViewInDegrees = 50
        camera.camera.near = 0.001
        camera.look(at: center, from: center + SIMD3(0, 0.7, 2.7) * radius, relativeTo: nil)
        let renderer = try RealityRenderer()
        renderer.entities.append(entity)
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0.96, alpha: 1))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 768, height: 768, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.featureUnsupported) }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        for _ in 0..<5 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in continuation.resume() })
                } catch { continuation.resume(throwing: error) }
            }
        }
        var pixels = [UInt8](repeating: 0, count: 768 * 768 * 4)
        texture.getBytes(&pixels, bytesPerRow: 768 * 4, from: MTLRegionMake2D(0, 0, 768, 768), mipmapLevel: 0)
        let varied = stride(from: 0, to: pixels.count, by: 4).filter { max(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) - min(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) > 20 }.count
        guard varied > 1000 else { throw NSError(domain: "SplatRendering", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rendered output has no visible colored splat scene."]) }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 768, height: 768, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 768 * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let url = URL(fileURLWithPath: "/tmp/roomy-splat-render.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        print("PASS: rendered \(cloud.count) real splats on \(device.name); \(varied) colored pixels; \(url.path)")
    }
}
