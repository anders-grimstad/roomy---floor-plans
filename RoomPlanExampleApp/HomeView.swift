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
    @State private var scanBounce = 0
    @State private var archiveBounce = 0

    var body: some View {
        if #available(iOS 26.0, *) {
            homeContent_iOS26
                .fullScreenCover(isPresented: $showScanner) {
                    RoomCaptureSwiftUIView()
                }
                .fullScreenCover(isPresented: $showSavedScans) {
                    NavigationStack {
                        SavedScansView()
                    }
                }
        } else {
            homeContentLegacy
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

    // MARK: - Information Card

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROOMY")
                .font(.custom("Silkscreen-Bold", size: 48))
                .foregroundStyle(.white)
                .tracking(2)

            Text(" BY KRUSEDULL STUDIOS")
                .font(.custom("Silkscreen-Regular", size: 10))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(1)

            Text("A small project to  harness the power of LiDAR and bring accurate floor plans to the people. Because who wants to get their tommestokk or their pocket laser and notebooks and spend hours measuring, second guessing, and ultimately hiring a professional when you have the power of laser technology in your pocket!!!")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 362, alignment: .leading)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButton(
        icon: String,
        title: String,
        subtitle: String,
        bounceValue: Int
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .symbolEffect(.bounce, value: bounceValue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - iOS 26+ (Liquid Glass)

    @available(iOS 26.0, *)
    private var homeContent_iOS26: some View {
        ZStack {
            Image("HomeBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(Color.black.opacity(0.4))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Glass information card
                informationCard
                    .glassEffect(.clear.tint(Color.black.opacity(0.6)), in: .rect(cornerRadius: 24))

                Spacer()

                // Action buttons
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            showScanner = true
                        } label: {
                            actionButton(
                                icon: "graph.3d",
                                title: "Scan",
                                subtitle: "your home",
                                bounceValue: scanBounce
                            )
                        }
                        .buttonStyle(.glass(.clear.tint(Color.black.opacity(0.6))))

                        Button {
                            showSavedScans = true
                        } label: {
                            actionButton(
                                icon: "archivebox",
                                title: "View",
                                subtitle: "old scans",
                                bounceValue: archiveBounce
                            )
                        }
                        .buttonStyle(.glass(.clear.tint(Color.black.opacity(0.6))))
                    }
                    .frame(maxWidth: 362)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            scanBounce += 1
            archiveBounce += 1
        }
    }

    // MARK: - Legacy (pre-iOS 26)

    private var homeContentLegacy: some View {
        ZStack {
            Image("HomeBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(Color.black.opacity(0.4))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Information card with material background
                informationCard
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        showScanner = true
                    } label: {
                        actionButton(
                            icon: "graph.3d",
                            title: "Scan",
                            subtitle: "your home",
                            bounceValue: scanBounce
                        )
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    Button {
                        showSavedScans = true
                    } label: {
                        actionButton(
                            icon: "archivebox",
                            title: "View",
                            subtitle: "old scans",
                            bounceValue: archiveBounce
                        )
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: 362)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            scanBounce += 1
            archiveBounce += 1
        }
    }
}

#Preview {
    HomeView()
}
