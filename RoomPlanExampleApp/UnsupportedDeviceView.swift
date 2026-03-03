/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
View displayed when the device does not support RoomPlan (no LiDAR).
*/

import SwiftUI

struct UnsupportedDeviceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lidar.iphone")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Unsupported Device")
                .font(.title.bold())
            Text("This app requires a device with a LiDAR Scanner, such as iPhone 12 Pro or later.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
    }
}

#Preview {
    UnsupportedDeviceView()
}
