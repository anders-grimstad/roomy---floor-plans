import SwiftUI
import PhotosUI
import FoundationModels
import ImageIO

struct RoomPhotoSuggestionView: View {
    let record: SavedScanRecord
    let onSaved: () -> Void

    var body: some View {
        if #available(iOS 27.0, *) {
            RoomPhotoSuggestionEditor(record: record, onSaved: onSaved)
        } else {
            NavigationStack {
                ContentUnavailableView("Photo Suggestions", systemImage: "photo.badge.sparkles", description: Text("Photo suggestions require iOS 27 and an Apple Intelligence-capable device. Your scans are still available in the library."))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { DismissPhotoSuggestionsButton() } }
            }
        }
    }
}

private struct DismissPhotoSuggestionsButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Close") { dismiss() } }
}

@available(iOS 27.0, *)
@MainActor
private struct RoomPhotoSuggestionEditor: View {
    let record: SavedScanRecord
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isLoadingPhoto = false
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var unavailableReason: String?
    @State private var errorMessage: String?
    @State private var draft = RoomPhotoSuggestionDraft(title: "", roomDescription: "")
    @State private var hasSuggestion = false
    @State private var latency: TimeInterval?

    var body: some View {
        let photoPickerTitle = photoData == nil ? "Choose Room Photo" : "Choose Another Photo"
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(photoPickerTitle, systemImage: "photo")
                    }
                    if isLoadingPhoto {
                        ProgressView("Loading photo…")
                    } else if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .accessibilityLabel("Selected room photo")
                    }
                    Text("Only the photo you choose is analyzed, on this device. Roomy does not save the photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if let unavailableReason {
                        Label(unavailableReason, systemImage: "info.circle")
                        Button("Check Availability") { refreshAvailability() }
                    }
                    if isGenerating {
                        ProgressView("Suggesting a name and description…")
                        Button("Cancel Generation", role: .cancel) { cancelGeneration() }
                    } else {
                        Button("Generate Suggestions", systemImage: "sparkles") { generate() }
                            .disabled(photoData == nil || isLoadingPhoto || unavailableReason != nil)
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                if hasSuggestion {
                    Section("Review and Edit") {
                        TextField("Scan name", text: $draft.title)
                        TextField("Description", text: $draft.roomDescription, axis: .vertical)
                            .lineLimit(3...8)
                        Text("Check the suggested details before saving. Suggestions do not change measured dimensions or area.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let latency {
                            Text(String(format: "Generated in %.1f seconds", latency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Accept and Save") { accept() }
                            .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                }
            }
            .navigationTitle("Photo Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { refreshAvailability() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshAvailability() }
            }
            .task(id: selection) { await loadPhoto() }
            .onDisappear {
                cancelGeneration()
                photoData = nil
            }
        }
    }

    private func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available: unavailableReason = nil
        case .unavailable(.deviceNotEligible): unavailableReason = "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): unavailableReason = "Turn on Apple Intelligence in Settings to generate suggestions."
        case .unavailable(.modelNotReady): unavailableReason = "The on-device model is not ready. Try again after it finishes downloading."
        case .unavailable: unavailableReason = "The on-device model is currently unavailable."
        }
    }

    private func loadPhoto() async {
        cancelGeneration()
        photoData = nil
        errorMessage = nil
        hasSuggestion = false
        latency = nil
        isLoadingPhoto = false
        guard let selection else { return }
        isLoadingPhoto = true
        defer { if !Task.isCancelled { isLoadingPhoto = false } }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw PhotoError.invalidImage
            }
            try Task.checkCancellation()
            photoData = data
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not load the photo: \(error.localizedDescription)"
        }
    }

    private func generate() {
        refreshAvailability()
        guard unavailableReason == nil, let photoData,
              let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let requestID = UUID()
        generationID = requestID
        isGenerating = true
        hasSuggestion = false
        errorMessage = nil
        latency = nil
        generationTask = Task { @MainActor in
            let started = Date()
            do {
                let suggestion = try await RoomPhotoSuggestionService.suggest(image: image, orientation: orientation)
                try Task.checkCancellation()
                guard generationID == requestID else { return }
                draft = suggestion
                latency = Date().timeIntervalSince(started)
                hasSuggestion = true
                isGenerating = false
                generationID = nil
                generationTask = nil
            } catch {
                guard generationID == requestID else { return }
                isGenerating = false
                generationID = nil
                generationTask = nil
                if !Task.isCancelled {
                    errorMessage = "Could not generate suggestions: \(error.localizedDescription)"
                    refreshAvailability()
                }
            }
        }
    }

    private func cancelGeneration() {
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func accept() {
        do {
            try SavedScansStore().acceptPhotoSuggestion(id: record.id, draft: draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Could not save your changes: \(error.localizedDescription)"
        }
    }

    private enum PhotoError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Choose a readable image file." }
    }
}
