## Components

This repo is an Apple RoomPlan sample app (UIKit-first capture) plus a small set of Python utilities for inspecting/exporting the `Room.json` output.

### iOS app (Swift)

#### App entry + scene selection

- **`RoomPlanExampleApp/AppDelegate.swift`**
  - **responsibility**: chooses the scene configuration at launch based on whether RoomPlan capture is supported on the device.
  - **key call**: `RoomCaptureSession.isSupported`
  - **storyboard routing**: `"Default Configuration"` → `Main.storyboard`, `"Unsupported Device"` → `UnsupportedDevice.storyboard`

- **`RoomPlanExampleApp/SceneDelegate.swift`**
  - **responsibility**: minimal scene delegate stub (no custom logic).

#### Onboarding + navigation

- **`RoomPlanExampleApp/OnboardingViewController.swift`**
  - **responsibility**: “Start Scanning” entry screen.
  - **navigation**: presents `RoomCaptureViewNavigationController` full-screen.

- **`RoomPlanExampleApp/Base.lproj/Main.storyboard`**
  - **responsibility**: defines the initial UI flow:
    - `OnboardingViewController` (initial)
    - `RoomCaptureViewNavigationController` (nav controller)
    - `RoomCaptureViewController` (root of the nav controller)

- **`RoomPlanExampleApp/Base.lproj/UnsupportedDevice.storyboard`**
  - **responsibility**: static “Unsupported Device” screen shown when `RoomCaptureSession.isSupported == false`.

#### Capture / scanning

- **`RoomPlanExampleApp/RoomCaptureViewController.swift`**
  - **responsibility**: owns the RoomPlan capture lifecycle and result handling.
  - **UI**:
    - embeds `RoomCaptureView` as the main background view
    - navigation bar: **Cancel** / **Done**
    - bottom: **Export** (storyboard) + **Floor Plan** (created programmatically)
  - **session lifecycle**:
    - `viewDidAppear` → `captureSession.run(configuration:)`
    - `viewWillDisappear` → `captureSession.stop()`
  - **RoomPlan delegate callbacks**:
    - `captureView(shouldPresent:...) -> Bool` returns `true` to allow post-processing
    - `captureView(didPresent processedResult: CapturedRoom, ...)` stores `finalResults` and enables export / floor plan buttons

#### Floor plan (2D) viewing + export

- **`RoomPlanExampleApp/FloorPlanViewController.swift`**
  - **responsibility**: UIKit controller that:
    - generates `FloorPlanData` from a `CapturedRoom`
    - hosts the SwiftUI renderer (`FloorPlanView`) via `UIHostingController`
    - provides export UI (SVG/PNG/PDF/JSON) via an action sheet + share sheet

- **`RoomPlanExampleApp/FloorPlanView.swift`**
  - **responsibility**: SwiftUI `Canvas` renderer for `FloorPlanData`.
  - **features**: pan/zoom, toggles for grid/dimensions/furniture/labels, area display.

#### Floor plan model generation + exporters

- **`RoomPlanExampleApp/FloorPlanGenerator.swift`**
  - **responsibility**: transforms RoomPlan’s 3D model (`CapturedRoom`) into 2D drawable data (`FloorPlanData`).
  - **notes**:
    - uses `simd_float4x4` math to compute endpoints and rotations
    - maps world coordinates into plan coordinates (top-down)

- **`RoomPlanExampleApp/SVGExporter.swift`**
  - **responsibility**: converts `FloorPlanData` to an SVG string and writes it to disk.
  - **goal**: match the “look” and coordinate conventions used by the Python conversion script.

### Export artifacts (sample output)

- **`Export/Room.json`**: example `CapturedRoom` JSON output.
- **`Export/Room.usdz`**: example `CapturedRoom.export(...)` output (USDZ).
- **`Export/*.svg`**: example SVG floor plans (some generated, some edited variants).

### Python tooling (optional utilities)

#### JSON → SVG conversion

- **`Export/conversionscript.py`**
  - **responsibility**: converts RoomPlan `Room.json` into a simple SVG floor plan.
  - **key details**:
    - RoomPlan transforms are **16 floats, column-major** (simd layout)
    - uses the same 3D → 2D mapping as the Swift generator: \(x = -worldX\), \(y = worldZ\)
    - can optionally apply `referenceOriginTransform`

#### Terminal viewer

- **`Export/terminal_viewer/floorplan_viewer.py`**
  - **responsibility**: renders a RoomPlan JSON floor plan directly in a terminal using Unicode box-drawing characters.
  - **extras**: can rotate/align output (dominant wall direction or minimal bounding box) for readability.

- **`Export/terminal_viewer/README.md`**
  - **responsibility**: usage docs + orientation notes.

