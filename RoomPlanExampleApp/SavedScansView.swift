/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view that lists saved scans and opens a floor plan review.
Replaces the UIKit SavedScansViewController.
*/

import SwiftUI

struct SavedScansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [SavedScanRecord] = []

    var body: some View {
        List(scans, id: \.id) { record in
            NavigationLink {
                if let exportData = SavedScansStore().loadFloorPlanExport(for: record.id) {
                    FloorPlanScreen(exportData: exportData)
                        .navigationBarHidden(true)
                }
            } label: {
                SavedScanRow(record: record)
            }
        }
        .navigationTitle("Saved Scans")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear { scans = SavedScansStore().loadIndex() }
    }
}

// MARK: - Row

private struct SavedScanRow: View {
    let record: SavedScanRecord
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.system(size: 16, weight: .semibold))
                Text(record.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 72)
        .onAppear { thumbnail = SavedScansStore().loadThumbnail(for: record.id) }
    }
}

#Preview {
    NavigationStack {
        SavedScansView()
    }
}
