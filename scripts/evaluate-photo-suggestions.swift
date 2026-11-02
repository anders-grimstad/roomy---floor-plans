import Foundation
import FoundationModels
import ImageIO

// Compile with RoomPhotoMetadata.swift and RoomPhotoSuggestionService.swift.
// Uses only Apple's on-device model and explicitly supplied image paths.
@main
struct PhotoEvaluation {
    @MainActor
    static func main() async {
        guard #available(macOS 27.0, *) else {
            print("Requires macOS 27 or newer.")
            return
        }
        guard case .available = SystemLanguageModel.default.availability else {
            print("Model unavailable: \(SystemLanguageModel.default.availability)")
            return
        }
        for path in CommandLine.arguments.dropFirst() {
            let start = Date()
            do {
                let url = URL(fileURLWithPath: path)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let orientation = CGImagePropertyOrientation(rawValue: properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1) ?? .up
                let draft = try await RoomPhotoSuggestionService.suggest(image: image, orientation: orientation)
                let result: [String: Any] = ["image": url.lastPathComponent, "title": draft.title,
                    "description": draft.roomDescription, "seconds": Date().timeIntervalSince(start)]
                let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: json, as: UTF8.self))
            } catch {
                print("FAILED \(URL(fileURLWithPath: path).lastPathComponent): \(error)")
            }
        }
    }
}
