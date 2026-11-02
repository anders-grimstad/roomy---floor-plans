import Foundation
import FoundationModels

@main
struct ModelProbe {
    static func main() {
        if #available(macOS 27.0, *) {
            print("On-device Foundation Models availability: \(SystemLanguageModel.default.availability)")
        } else {
            print("Image understanding requires macOS 27 or a supported iOS 27 device.")
        }
    }
}
