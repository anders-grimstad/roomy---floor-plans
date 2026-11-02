/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
View displayed when the device does not support RoomPlan (no LiDAR).
*/

import SwiftUI

struct UnsupportedDeviceView: View {
    @State private var showSplatExperiment = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lidar.iphone")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Room Scanning Unavailable")
                .font(.title.bold())
            Text("Room scanning requires a device with a LiDAR Scanner, such as iPhone 12 Pro. You can still try the splat viewer below.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Button("Try Gaussian Splats (Experimental)") {
                showSplatExperiment = true
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showSplatExperiment) {
            GaussianSplatViewerScreen()
        }
    }
}

#Preview {
    UnsupportedDeviceView()
}
