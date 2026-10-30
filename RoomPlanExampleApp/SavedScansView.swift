/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
SwiftUI view that lists saved scans with rename, delete, and 3D preview,
and opens a floor plan review.
*/

import SwiftUI

struct SavedScansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scans: [SavedScanRecord] = []
    @State private var renameTarget: SavedScanRecord?
    @State private var renameText = ""
    @State private var preview3D: USDZPreviewItem?
    @State private var showError = false
    @State private var errorMessage = ""

    private let store = SavedScansStore()

    var body: some View {
        Group {
            if scans.isEmpty {
                emptyState
            } else {
                scanList
            }
        }
        .navigationTitle("Saved Scans")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear(perform: reload)
        .alert("Rename Scan", isPresented: isRenamePresented) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $preview3D) { item in
            USDZPreviewRepresentable(url: item.url)
                .ignoresSafeArea()
        }
    }

    // MARK: - List

    private var scanList: some View {
        List {
            ForEach(scans) { record in
                NavigationLink {
                    if let exportData = store.loadFloorPlanExport(for: record.id) {
                        FloorPlanScreen(exportData: exportData, savedScanId: record.id, scanTitle: record.title)
                            .navigationBarHidden(true)
                    }
                } label: {
                    SavedScanRow(record: record, store: store) {
                        preview3D = USDZPreviewItem(url: store.roomUSDZURL(for: record.id))
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteScan(record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        beginRename(record)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    if store.hasUSDZ(for: record.id) {
                        Button {
                            preview3D = USDZPreviewItem(url: store.roomUSDZURL(for: record.id))
                        } label: {
                            Label("View in 3D", systemImage: "cube.transparent")
                        }
                    }
                    Button {
                        beginRename(record)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteScan(record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "graph.3d")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text("NO SCANS YET")
                .font(.custom("Silkscreen-Bold", size: 20))
            Text("Scan a room and it will show up here.\nGo bother your walls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() {
        scans = store.loadIndex()
    }

    private func deleteScan(_ record: SavedScanRecord) {
        do {
            try store.deleteScan(id: record.id)
            withAnimation {
                scans.removeAll { $0.id == record.id }
            }
        } catch {
            presentError("Failed to delete scan: \(error.localizedDescription)")
        }
    }

    private func beginRename(_ record: SavedScanRecord) {
        renameText = record.title
        renameTarget = record
    }

    private func commitRename() {
        guard let record = renameTarget else { return }
        renameTarget = nil
        let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != record.title else { return }
        do {
            try store.renameScan(id: record.id, to: newTitle)
            reload()
        } catch {
            presentError("Failed to rename scan: \(error.localizedDescription)")
        }
    }

    private var isRenamePresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - 3D Preview Item

private struct USDZPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Row

private struct SavedScanRow: View {
    let record: SavedScanRecord
    let store: SavedScansStore
    let onPreview3D: () -> Void

    @State private var thumbnail: UIImage?
    @State private var hasModel = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "square.split.bottomrightquarter")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasModel {
                Button(action: onPreview3D) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View in 3D")
            }
        }
        .frame(height: 76)
        .onAppear {
            thumbnail = store.loadThumbnail(for: record.id)
            hasModel = store.hasUSDZ(for: record.id)
        }
    }
}

#Preview {
    NavigationStack {
        SavedScansView()
    }
}
