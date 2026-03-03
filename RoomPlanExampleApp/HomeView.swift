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
                .font(.title.bold())

            Text("Create a floor plan by scanning your room, then save and review scans later.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 14) {
                if #available(iOS 26.0, *) {
                    Button("Start Scanning") {
                        showScanner = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(minWidth: 200)

                    Button("Saved Scans") {
                        showSavedScans = true
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(minWidth: 200)
                } else {
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
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .frame(minWidth: 200)
                }
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
