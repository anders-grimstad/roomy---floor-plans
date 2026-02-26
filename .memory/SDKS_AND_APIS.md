## SDKs / APIs in use

This app is primarily a **RoomPlan capture pipeline** wrapped in UIKit, with a SwiftUI-based 2D floor-plan renderer hosted inside UIKit.

### RoomPlan (Apple)

- **Primary types used**
  - `RoomCaptureSession`
  - `RoomCaptureView`
  - `CapturedRoomData` (raw capture output for post-processing)
  - `CapturedRoom` (post-processed result)

- **Key constraint: UIKit-first capture surface**
  - The capture UI in this repo is a `RoomCaptureView` inserted into a `UIViewController` (`RoomCaptureViewController`).
  - Practically: the canonical, sample-supported integration pattern is **UIKit**. If you want to use capture in SwiftUI, you typically wrap the UIKit controller/view (e.g. `UIViewControllerRepresentable`), rather than using a native SwiftUI RoomPlan view.

- **Support gating (LiDAR / device capability)**
  - `RoomCaptureSession.isSupported` is checked during app launch to route either to the main UI or an “Unsupported Device” storyboard.
  - File: `RoomPlanExampleApp/AppDelegate.swift`

- **Delegate-driven lifecycle**
  - The capture flow is driven by delegate callbacks (in this repo the controller conforms to both protocols):
    - `RoomCaptureSessionDelegate`
    - `RoomCaptureViewDelegate`
  - The app returns `true` from `captureView(shouldPresent:...)` to allow RoomPlan to post-process.
  - The final `CapturedRoom` arrives in `captureView(didPresent:processedResult:...)`.
  - File: `RoomPlanExampleApp/RoomCaptureViewController.swift`

- **USDZ export**
  - The result is exported via `CapturedRoom.export(to:exportOptions:)`.
  - This repo uses `exportOptions: .mesh` and notes `.parametric` and `.all` as alternatives.

### UIKit (Apple)

- **Navigation / presentation**
  - Storyboard-based entry (`Main.storyboard`) and a modal full-screen presentation of a navigation controller for capture.
  - UIKit modals for:
    - capture nav controller
    - floor plan screen
    - action sheets / share sheets

- **Sharing**
  - Exports are shared via `UIActivityViewController`.
  - Files: `RoomPlanExampleApp/RoomCaptureViewController.swift`, `RoomPlanExampleApp/FloorPlanViewController.swift`

- **Permissions**
  - Camera usage string is provided via build settings:
    - `INFOPLIST_KEY_NSCameraUsageDescription = "RoomCaptureView Requires Camera Access"`
  - File: `RoomPlanExampleApp.xcodeproj/project.pbxproj`

### SwiftUI (Apple)

- **Usage here**
  - SwiftUI is used for **rendering** the 2D floor plan, not for capture.
  - `FloorPlanViewController` embeds `FloorPlanView` using `UIHostingController`.
  - File: `RoomPlanExampleApp/FloorPlanViewController.swift`

- **Rendering**
  - `FloorPlanView` uses `Canvas` and gesture state for pan/zoom and view toggles (grid/dimensions/furniture/labels).
  - File: `RoomPlanExampleApp/FloorPlanView.swift`

### CoreGraphics / Quartz (Apple)

- **Why**
  - Used for 2D export outputs from the rendered floor plan:
    - PNG via `UIGraphicsImageRenderer`
    - PDF via `UIGraphicsBeginPDFContextToData` + `CALayer.render(in:)`
  - File: `RoomPlanExampleApp/FloorPlanViewController.swift`

### simd (Apple)

- **Why**
  - RoomPlan transforms are `simd_float4x4`; this repo:
    - extracts euler-ish angles
    - converts transforms + element dimensions into endpoints
    - maps 3D world points into the 2D floor plan coordinate system
  - File: `RoomPlanExampleApp/FloorPlanGenerator.swift`

### Foundation (Apple)

- **Why**
  - File I/O, temporary directories, JSON encoding (`JSONEncoder`), basic data models.
  - Files: `RoomPlanExampleApp/RoomCaptureViewController.swift`, `RoomPlanExampleApp/FloorPlanViewController.swift`, `RoomPlanExampleApp/FloorPlanGenerator.swift`, `RoomPlanExampleApp/SVGExporter.swift`

### Notable configuration in this repo

- **Deployment target**
  - The Xcode project currently sets `IPHONEOS_DEPLOYMENT_TARGET = 18.6` (Debug/Release).
  - File: `RoomPlanExampleApp.xcodeproj/project.pbxproj`
  - Note: Apple’s original RoomPlan sample documentation historically referenced iOS 16+; this repo’s Xcode project settings override that.

