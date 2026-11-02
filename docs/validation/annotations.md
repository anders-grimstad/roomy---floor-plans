# Floor-plan annotations

Annotations are stored in `annotations.json` inside the saved scan's folder. This optional sidecar contains the native PaperKit document, its canonical page-to-scan coordinate mapping, and a transparent PNG preview. Existing `floorplan.json`, `room.json`, and `room.usdz` files retain their previous formats. Deleting a scan removes its annotations with the rest of the folder.

The editor is available on iOS 27 and later. It uses PaperKit's native drawing, selection, text and shape insertion controls, PencilKit's tool picker, and the native undo manager. The toolbar also exposes selection, drawing, deletion, undo, and redo. Save commits active text editing before taking the markup snapshot; Cancel leaves the saved document intact. Saving an annotation first saves a newly captured plan if it has no saved-scan identifier yet.

The floor plan is an uneditable background view, separate from editable markup. Annotation pages use the original scan coordinate system at 100 points per meter with a 50-point margin. Opening a north-up plan rotates the markup into the editor's coordinates; Save applies the inverse transform. A rigid transform updates element centers and rotations without changing their local dimensions. This avoids a native `transformContent` behavior observed on macOS 27.2 that changed an arrow's bounding box while leaving its rotation unchanged.

The floor-plan viewer and PNG/PDF exports draw the same transparent annotation preview through the page-to-view transform. Thus annotations follow the plan's zoom, pan and north-up rotation. Older OS versions retain their existing plan viewer and can show the stored preview, but do not expose the editor. SVG and JSON exports retain their existing geometry-only behavior.

Saving grows the separate annotation page when transformed notes extend beyond its original bounds. Reopening includes the entire saved page; viewer and export fitting include its footprint. This preserves notes in rotated editor corners and page margins without expanding measured floor-plan geometry.

Missing annotation sidecars mean the scan has no annotations. Corrupt or unsupported sidecars produce a visible load error and are preserved; opening the plan does not replace them with an empty document. Each annotation save writes the entire sidecar atomically.

## Local evidence

All fixtures below are synthetic. No physical room capture or finger/Apple Pencil interaction is claimed by these checks.

- `tests/AnnotationTests.swift` exercises the production coordinate mapper and sidecar store: fixed page margins, a hand-computed 90-degree north-up coordinate, inverse-transform round-trip, opening a legacy scan without annotations, exact save/reopen of markup/preview/mapping, unchanged measured-geometry bytes, and corrupt-data error reporting. The initial identity mapping failed the page-size assertion before implementation; the implemented mapper and store passed.
- `tests/AnnotationRendering.swift` creates real PaperKit text, a rectangle, an arrow and a PencilKit stroke. It serializes and reopens native markup, rasterizes it with the production rasterizer, checks that an upper-left marker is not vertically flipped, verifies arrow rotation and inverse orientation, and produces raw/north-up PNG and north-up PDF artifacts. The arrow-direction regression failed when using native bounding-box-only transformation and passed with the rigid transform.
- Native text/shape/arrow/ink rendering completed on macOS 27.2. PencilKit ink rendering required running the executable outside the restricted sandbox for GPU access; running it inside the sandbox trapped in Apple's `PKDrawing.draw` implementation. The successful run returned exit code 0.
- Root integration also rendered the actual floor-plan drawing and export-view bodies with a macOS semantic color/image adapter, then inspected both PNG exports and PDF rasterizations. The raw and north-up composites preserved annotation alignment, the title block and the scale bar. See `scripts/render-export-qa.py` and `tests/ExportRendering.swift`.
- `tests/AnnotationBoundarySave.swift` verifies a corner note outside the original canonical page through native saving, preview rendering and repeated orientation changes, with a hand-calculated world-coordinate assertion. `tests/AnnotationEdgeRendering.swift` checks red page-edge marker pixels in actual exports at 0°, 45° and 90°; it failed against the previous fitting behavior and passes with annotation-page fitting. Both run in `scripts/verify-native.sh`.
- The annotation implementation was typechecked against the installed iOS 27.2 SDK with an iOS 18.6 deployment target. The root implementation owns the final integrated app build and its recorded result.

To rerun the focused checks from the repository root:

```sh
xcrun swiftc -module-cache-path /tmp/roomy-annotation-module-cache RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift tests/AnnotationTests.swift -o /tmp/roomy-annotation-tests
/tmp/roomy-annotation-tests

xcrun swiftc -module-cache-path /tmp/roomy-annotation-render-cache RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift RoomPlanExampleApp/FloorPlanAnnotationRendering.swift tests/AnnotationRendering.swift -o /tmp/roomy-annotation-rendering
/tmp/roomy-annotation-rendering
```

The native rendering executable produces `/tmp/roomy-annotation-preview.png`, `/tmp/roomy-annotation-north-up.png`, and `/tmp/roomy-annotation-north-up.pdf`. Permit GPU access when running it through a restricted automation environment.

## Physical-device checklist — pending

Use a saved scan with a reliable north alignment on an iOS 27 device. Record the device, OS build, scan identifier and results for each step.

1. Open the plan in raw orientation. Annotate a specific wall corner with ink, a text note, a rectangle and an arrow. Confirm that the floor plan itself cannot be selected or moved in the editor.
2. Switch between Draw and Select. Move, resize and rotate individual annotations. Delete one, Undo the deletion, then Redo it. Verify that Undo/Redo also works after adding a native text or shape element.
3. While the text keyboard is still open, change the note and immediately tap Save. Reopen the editor and confirm the final text was saved.
4. Zoom and pan the plan. Confirm each annotation remains anchored to its original room feature. Toggle north-up, reopen the editor and verify that text, arrow direction and ink rotate with the plan.
5. Save in north-up orientation, leave the scan, reopen it, and toggle back to raw. Verify there is no position, size or rotation drift across repeated cycles.
6. Export PNG and PDF in both orientations. Inspect the files outside Roomy for matching wall/annotation positions, readable text and arrows, preserved title/scale information, and absence of editor controls. SVG and JSON should remain usable geometry exports.
7. Make edits and tap Cancel. Reopen to confirm the previously saved annotations remain unchanged. Return to the scan library, relaunch the app and confirm saved annotations survive.
8. Open a legacy scan with no sidecar. Confirm normal viewing and exports work, then create its first annotations. On an older supported OS, verify the existing viewer and exports still work and any saved preview is visible without exposing an unavailable editor.
9. With a disposable scan fixture, corrupt the sidecar and reopen. Confirm the app reports the problem and does not overwrite the damaged file or measured scan files. Restore the fixture afterward.

The installed CoreSimulator service initially did not match Xcode's framework version. It later recovered, and an iOS 26.5 simulator launch check passed. Native iOS 27 editor interaction and real-device export/sharing remain unverified until this checklist is performed; local rendering and compilation do not substitute for those checks.

## Apple references

- [Unwrap PaperKit, WWDC26](https://developer.apple.com/videos/play/wwdc2026/372/)
- [Integrating PaperKit into your app](https://developer.apple.com/documentation/paperkit/getting-started-with-paperkit)
- [PaperMarkupViewController contentView](https://developer.apple.com/documentation/paperkit/papermarkupviewcontroller/contentview-4aeda)
- [Rendering PaperMarkup](https://developer.apple.com/documentation/paperkit/papermarkup/draw(in:frame:options:))

API names and availability were checked against the installed iOS 27.2 PaperKit/PencilKit Swift interfaces as well as Apple's documentation.
