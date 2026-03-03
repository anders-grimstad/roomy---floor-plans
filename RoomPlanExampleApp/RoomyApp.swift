/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI app entry point. Replaces AppDelegate and SceneDelegate.
*/

import SwiftUI
import RoomPlan

@main
struct RoomyApp: App {
    var body: some Scene {
        WindowGroup {
            if RoomCaptureSession.isSupported {
                HomeView()
            } else {
                UnsupportedDeviceView()
            }
        }
    }
}
