import SwiftUI
import UIKit
import PaperKit
import PencilKit

/// The native markup remains editable; this transparent preview also works on older OS versions.
struct FloorPlanAnnotationPreview {
    let document: FloorPlanAnnotationDocument
    let image: UIImage

    init?(document: FloorPlanAnnotationDocument) {
        guard let image = UIImage(data: document.previewPNG) else { return nil }
        self.document = document
        self.image = image
    }

    func draw(in context: GraphicsContext, rotationRadians: CGFloat, worldToView: CGAffineTransform) {
        var layer = context
        layer.concatenate(document.geometry.pageToView(rotationRadians: rotationRadians, worldToView: worldToView))
        layer.draw(Image(uiImage: image), in: document.geometry.pageBounds)
    }
}

@available(iOS 27.0, *)
struct FloorPlanAnnotationEditor: UIViewControllerRepresentable {
    let document: FloorPlanAnnotationDocument?
    let canonicalGeometry: FloorPlanAnnotationGeometry
    let displayedPlan: FloorPlanData
    let rotationRadians: CGFloat
    let onSave: (FloorPlanAnnotationDocument) throws -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let editor = FloorPlanAnnotationEditorController(
            document: document, canonicalGeometry: canonicalGeometry,
            displayedPlan: displayedPlan, rotationRadians: rotationRadians,
            onSave: onSave, onClose: onClose
        )
        return UINavigationController(rootViewController: editor)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) { }
}

@available(iOS 27.0, *)
private final class FloorPlanAnnotationEditorController: UIViewController, PaperMarkupViewController.Delegate {
    private let paper: PaperMarkupViewController
    private let canonicalGeometry: FloorPlanAnnotationGeometry
    private let canonicalToEditor: CGAffineTransform
    private let initialLoadError: Error?
    private let displayedPlan: FloorPlanData
    private let editorGeometry: FloorPlanAnnotationGeometry
    private let toolPicker = PKToolPicker()
    private let insertionController = MarkupEditViewController(supportedFeatureSet: .latest)
    private let onSave: (FloorPlanAnnotationDocument) throws -> Void
    private let onClose: () -> Void
    private var undoButton: UIBarButtonItem!
    private var redoButton: UIBarButtonItem!
    private var deleteButton: UIBarButtonItem!
    private var saveTask: Task<Void, Never>?

    init(document: FloorPlanAnnotationDocument?, canonicalGeometry: FloorPlanAnnotationGeometry,
         displayedPlan: FloorPlanData, rotationRadians: CGFloat,
         onSave: @escaping (FloorPlanAnnotationDocument) throws -> Void,
         onClose: @escaping () -> Void) {
        self.canonicalGeometry = canonicalGeometry
        self.displayedPlan = displayedPlan
        editorGeometry = FloorPlanAnnotationGeometry(
            worldBounds: displayedPlan.bounds.union(canonicalGeometry.displayedWorldBounds(rotationRadians: rotationRadians)),
            pointsPerMeter: canonicalGeometry.pointsPerMeter, margin: 0
        )
        canonicalToEditor = canonicalGeometry.pageToView(
            rotationRadians: rotationRadians, worldToView: editorGeometry.worldToPage
        )
        self.onSave = onSave
        self.onClose = onClose
        var markup = PaperMarkup(bounds: canonicalGeometry.pageBounds)
        var loadError: Error?
        if let document {
            do { markup = try PaperMarkup(dataRepresentation: document.markupData) }
            catch { loadError = error }
        }
        FloorPlanAnnotationTransform.apply(canonicalToEditor, to: &markup)
        markup.bounds = editorGeometry.pageBounds
        paper = PaperMarkupViewController(markup: markup, supportedFeatureSet: .latest)
        initialLoadError = loadError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Annotate Floor Plan"
        view.backgroundColor = .systemBackground
        addChild(paper)
        paper.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paper.view)
        NSLayoutConstraint.activate([
            paper.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paper.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paper.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            paper.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        paper.didMove(toParent: self)

        let renderer = ImageRenderer(content: FloorPlanAnnotationBackground(data: displayedPlan, geometry: editorGeometry))
        renderer.scale = 2
        let background = UIImageView(image: renderer.uiImage)
        background.contentMode = .scaleToFill
        paper.contentView = background
        paper.delegate = self
        paper.directTouchMode = .drawing
        paper.directTouchAutomaticallyDraws = true
        paper.drawingTool = PKInkingTool(.pen, color: .systemRed, width: 3)
        insertionController.delegate = paper
        toolPicker.addObserver(paper)
        paper.pencilKitResponderState.activeToolPicker = toolPicker
        paper.pencilKitResponderState.toolPickerVisibility = .visible

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        undoButton = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(undo))
        undoButton.accessibilityLabel = "Undo annotation"
        redoButton = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.forward"), style: .plain, target: self, action: #selector(redo))
        redoButton.accessibilityLabel = "Redo annotation"
        let select = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(selectElements))
        let draw = UIBarButtonItem(title: "Draw", style: .plain, target: self, action: #selector(drawElements))
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addElement))
        add.accessibilityLabel = "Add text, shape or arrow"
        deleteButton = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteSelection))
        deleteButton.accessibilityLabel = "Delete selected annotation"
        toolbarItems = [undoButton, redoButton, .flexibleSpace(), select, draw, .flexibleSpace(), deleteButton, add]
        navigationController?.setToolbarHidden(false, animated: false)
        updateUndoButtons()
        NotificationCenter.default.addObserver(self, selector: #selector(undoChanged), name: .NSUndoManagerDidUndoChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(undoChanged), name: .NSUndoManagerDidRedoChange, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        paper.becomeFirstResponder()
        paper.setContentVisibleFrame(editorGeometry.pageBounds, animated: false)
        if let initialLoadError {
            navigationItem.rightBarButtonItem?.isEnabled = false
            presentError("The saved annotations could not be opened. Their data has been preserved. \(initialLoadError.localizedDescription)")
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func cancel() {
        guard saveTask == nil else { return }
        onClose()
    }

    @objc private func undo() { paper.undoManager?.undo(); updateUndoButtons() }
    @objc private func redo() { paper.undoManager?.redo(); updateUndoButtons() }
    @objc private func undoChanged() { updateUndoButtons() }
    @objc private func selectElements() { paper.directTouchMode = .selection }
    @objc private func drawElements() { paper.directTouchMode = .drawing }
    @objc private func deleteSelection() {
        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.delete(_:)), to: paper, from: self, for: nil)
        updateUndoButtons()
    }

    @objc private func addElement(_ sender: UIBarButtonItem) {
        insertionController.modalPresentationStyle = .popover
        insertionController.popoverPresentationController?.barButtonItem = sender
        present(insertionController, animated: true)
    }

    @objc private func save() {
        guard saveTask == nil, initialLoadError == nil else { return }
        view.endEditing(true)
        guard let markup = paper.markup else { return }
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        paper.isEditable = false
        saveTask = Task { @MainActor in
            defer {
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
                navigationItem.leftBarButtonItem?.isEnabled = true
                paper.isEditable = true
            }
            do {
                let document = try await FloorPlanAnnotationTransform.document(from: markup, geometry: canonicalGeometry,
                    canonicalToEditor: canonicalToEditor)
                try onSave(document)
                onClose()
            } catch { presentError("Annotations could not be saved. \(error.localizedDescription)") }
        }
    }

    private func updateUndoButtons() {
        undoButton?.isEnabled = paper.undoManager?.canUndo == true
        redoButton?.isEnabled = paper.undoManager?.canRedo == true
        deleteButton?.isEnabled = !paper.selection.isEmpty
    }

    func paperMarkupViewControllerDidChangeMarkup(_ controller: PaperMarkupViewController) {
        updateUndoButtons()
    }

    func paperMarkupViewControllerDidChangeSelection(_ controller: PaperMarkupViewController) {
        updateUndoButtons()
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Annotations", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private struct FloorPlanAnnotationBackground: View {
    let data: FloorPlanData
    let geometry: FloorPlanAnnotationGeometry

    var body: some View {
        Canvas { context, size in
            var drawing = FloorPlanDrawing(data: data, colors: FloorPlanColors())
            drawing.options.showDimensions = true
            drawing.draw(in: context, size: size, transform: geometry.worldToPage)
        }
        .frame(width: geometry.pageBounds.width, height: geometry.pageBounds.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
