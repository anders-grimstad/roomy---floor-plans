# Roomy implementation and verification

Changes were developed on `codex/roomy-wwdc-experiments`. The implementation
goal excluded publication; the user subsequently reviewed the work and
authorized committing and pushing this branch. No deployment is included.

| Deliverable | Implemented behavior | Evidence and limits |
| --- | --- | --- |
| Scan baseline | Capture-to-library/export trace, documented multi-room/storey limits, repeatable three-route device procedure | Synthetic geometry/JSON/orientation/SVG checks and real store lifecycle checks pass. No physical LiDAR captures were performed. |
| PaperKit | Native drawing/text/shapes/arrows; selection/edit/delete/undo/redo; separate persistent sidecar; overlays and PNG/PDF inclusion | Native markup round-trip/render tests pass. Raw/north-up PNG exports and PDF rasterizations were visually inspected using the actual export bodies with AppKit adapters. iPhone editor interactions remain pending. |
| Photo suggestions | Explicit photo selection and on-device generation; editable review and explicit acceptance; optional persisted descriptions; cancellation/error/unavailable states | Persistence and legacy compatibility pass. The production model request ran against two existing exterior photos on this Mac, in 2.85 s and 1.67 s. One output invented a second door; positive interior-photo evaluation and iPhone UX remain pending. |
| Gaussian splats | Experimental sample/import viewer, binary Gaussian PLY parsing, orbit/zoom/reset, compatibility/loading/error handling | Parser checks include Apple's real 51,352-splat plant. Native GPU upload and offscreen rendering succeed. Offscreen colors are dark but match Apple's unmodified loader under the same harness; on-device visual fidelity and performance remain pending. |

The final unsigned Debug iOS and simulator builds pass with Xcode 27.2.
The local CPU and native PaperKit/export/GPU suites also pass after the review
fixes. The built app still declares
minimum iOS **18.6**, and its bundled plant asset's SHA-256 matches the source;
Apple's license is included in the app bundle. New framework entry points use
availability checks rather than raising the deployment target.

Existing scan formats remain readable. Annotation saves are separate from the
measured plan, and accepted photo descriptions survive plan updates and manual
renaming. Existing SVG/JSON exports retain their geometry-only behavior.

## Reproduce local verification

```sh
bash scripts/verify-local.sh
bash scripts/verify-native.sh
xcodebuild -project RoomPlanExampleApp.xcodeproj -scheme RoomPlanExampleApp -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/roomy-goal-build CODE_SIGNING_ALLOWED=NO -quiet build
```

The CPU suite exercises production code and synthetic export/PLY fixtures. The
store and export harnesses adapt UIKit image/color APIs to AppKit on macOS;
they are not simulator or iPhone UI tests. The native suite needs macOS 27 and
supported Apple GPU hardware. Model availability and explicit-photo evaluation
tools are documented in the photo checklist; model inference is not run by the
regression suite.

## Remaining device validation

- [Capture routes, reference measurements, reopening, and all export formats](scan-baseline.md)
- [PaperKit gestures, editing, undo/redo, cancellation, and orientation](annotations.md)
- [Ten varied photos, model availability, review/cancellation, and accuracy](photo-suggestions.md)
- [Splat appearance/navigation, room assets, memory, frame timings, heat, and close/pull-back behavior](gaussian-splats.md)

CoreSimulator initially failed, then recovered outside the shell sandbox on
November 2. The simulator build passed, and the app installed and launched on
an existing iPhone 17 Pro simulator running iOS 26.5. Its launch screenshot was
visually inspected: the LiDAR-unavailable screen and experimental-viewer entry
rendered correctly. This is a startup/older-OS compatibility check, not an
annotation-editor or model-quality test. The connected physical iPhone was
unavailable. Real iPhone/iPad scanning, editing gestures, sharing and performance
remain explicitly unverified. The optional native sRGB color-space comparison also did
not run because automatic permission approval review timed out twice; no
color-fidelity result is claimed from it.

## Review

The full code review identified two confirmed issues: annotations could be
clipped outside the original canonical page after north-up editing, and splat
buffer allocation/copy ran synchronously on the main actor. Both were fixed.
Annotation saves now expand their separate page mapping, and viewing/export
fit includes that page without changing measured geometry. Native regressions
check a rotated corner note through save/reopen and page-edge export visibility
at 0°, 45° and 90°. Splat buffers are prepared off the main actor with periodic
cancellation checks; only RealityKit resource/entity creation remains on the
required main actor. A native regression covers cancelled preparation.

The review receipt covers the original snapshot; the fixes were verified
separately with the focused native regressions and final app builds. Physical
device checks above remain pending.
