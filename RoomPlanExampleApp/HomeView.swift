/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Home screen for starting scans and viewing saved scans.
Replaces the UIKit HomeViewController.
*/

import SwiftUI

struct HomeView: View {
    @State private var showScanner = false
    @State private var showSavedScans = false

    var body: some View {
        VStack {
            Spacer()

            Text("Roomy")
                .font(.system(size: 34, weight: .bold))

            Text("Create a floor plan by scanning your room, then save and review scans later.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 14) {
                Button("Start Scanning") {
                    showScanner = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(minWidth: 200)

                Button("Saved Scans") {
                    showSavedScans = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(minWidth: 200)
            }
            .padding(.bottom, 33)
        }
        .fullScreenCover(isPresented: $showScanner) {
            RoomCaptureSwiftUIView()
        }
        .fullScreenCover(isPresented: $showSavedScans) {
            NavigationStack {
                SavedScansView()
            }
        }
    }
}

#Preview {
    HomeView()
}
