## Main user flows (mermaid)

These diagrams describe **what the user experiences** and which controller/actions implement each step.

### Screen map (only visible UI + user options)

```mermaid
flowchart TD
  Launch[LaunchApp] --> SupportCheck{DeviceSupportsRoomPlan?}

  SupportCheck -->|No| Unsupported[UnsupportedDeviceScreen]

  SupportCheck -->|Yes| Onboarding[OnboardingScreen]
  Onboarding -->|Tap_StartScanning| Capture[CaptureScreen]

  Capture -->|Tap_Done| CaptureComplete[CaptureCompleteState]
  Capture -->|Tap_Cancel| Onboarding

  CaptureComplete -->|Tap_Export| ShareSheetCapture[ShareSheet]
  CaptureComplete -->|Tap_FloorPlan| FloorPlan[FloorPlanScreen]
  CaptureComplete -->|Tap_Cancel| Onboarding

  FloorPlan -->|Tap_Close| CaptureComplete
  FloorPlan -->|Tap_Export| ExportOptions[ExportOptionsSheet]

  ExportOptions -->|Choose_SVG| ShareSheetFloorPlan[ShareSheet]
  ExportOptions -->|Choose_PNG| ShareSheetFloorPlan
  ExportOptions -->|Choose_PDF| ShareSheetFloorPlan
  ExportOptions -->|Choose_JSON| ShareSheetFloorPlan
  ExportOptions -->|Cancel| FloorPlan
```

Notes:
- `CaptureCompleteState` is the **same capture screen** after scanning stops and export buttons are shown/enabled.
- `ShareSheet` is `UIActivityViewController` (system UI).

### Unsupported device flow (no LiDAR / RoomPlan unsupported)

```mermaid
flowchart TD
  AppLaunch[AppLaunch] --> SupportCheck{RoomCaptureSession_isSupported?}
  SupportCheck -->|No| UnsupportedScene[UnsupportedDevice_storyboard]
  UnsupportedScene --> UnsupportedUI[UnsupportedDeviceScreen]
  SupportCheck -->|Yes| MainScene[Main_storyboard]
```

Implementation references:
- `RoomPlanExampleApp/AppDelegate.swift`
- `RoomPlanExampleApp/Base.lproj/UnsupportedDevice.storyboard`

### Happy path: onboarding → capture → results ready

```mermaid
flowchart TD
  AppLaunch[AppLaunch] --> SupportCheck{RoomCaptureSession_isSupported?}
  SupportCheck -->|Yes| Onboarding[OnboardingViewController]
  Onboarding -->|StartScanning_button| CaptureNav[RoomCaptureViewNavigationController]
  CaptureNav --> CaptureVC[RoomCaptureViewController]
  CaptureVC -->|viewDidAppear| RunSession[captureSession_run]
  RunSession --> Scanning[UserScansRoom]
  Scanning -->|Done_button| StopSession[captureSession_stop]
  StopSession --> PostProcess[RoomPlan_PostProcess]
  PostProcess -->|didPresent_processedResult| ResultsReady[finalResults_set]
  ResultsReady --> ButtonsEnabled[Export_and_FloorPlan_enabled]
```

Implementation references:
- `RoomPlanExampleApp/OnboardingViewController.swift`
- `RoomPlanExampleApp/Base.lproj/Main.storyboard`
- `RoomPlanExampleApp/RoomCaptureViewController.swift`

### Capture results export (USDZ + Room.json)

```mermaid
flowchart TD
  ResultsReady[finalResults_set] -->|Tap_Export| ExportAction[exportResults_action]
  ExportAction --> TempFolder[Create_temp_Export_folder]
  TempFolder --> JSONWrite[Write_Room_json]
  TempFolder --> USDZWrite[Write_Room_usdz_mesh]
  JSONWrite --> ShareSheet[UIActivityViewController]
  USDZWrite --> ShareSheet
  ShareSheet --> Share[UserShares]
```

Implementation references:
- `RoomPlanExampleApp/RoomCaptureViewController.swift`

### Floor plan flow (view + export formats)

```mermaid
flowchart TD
  ResultsReady[finalResults_set] -->|Tap_FloorPlan| PresentFloorPlan[Present_FloorPlanViewController]
  PresentFloorPlan --> Generate2D[FloorPlanGenerator_generate]
  Generate2D --> FloorPlanData[FloorPlanData]
  FloorPlanData --> HostSwiftUI[UIHostingController_FloorPlanView]
  HostSwiftUI --> View2D[UserViews2DPlan]

  View2D -->|Tap_Export| ExportMenu[Export_actionSheet]
  ExportMenu -->|SVG| ExportSVG[SVGExporter_export]
  ExportMenu -->|PNG| ExportPNG[UIGraphicsImageRenderer_snapshot]
  ExportMenu -->|PDF| ExportPDF[UIGraphics_PDF_context]
  ExportMenu -->|JSON| ExportJSON[FloorPlanExportData_encode]

  ExportSVG --> ShareSheet[UIActivityViewController]
  ExportPNG --> ShareSheet
  ExportPDF --> ShareSheet
  ExportJSON --> ShareSheet
  ShareSheet --> Share[UserShares]

  View2D -->|Tap_Close| Dismiss[Dismiss_FloorPlanViewController]
  Dismiss --> ResultsReady
```

Implementation references:
- `RoomPlanExampleApp/RoomCaptureViewController.swift`
- `RoomPlanExampleApp/FloorPlanViewController.swift`
- `RoomPlanExampleApp/FloorPlanGenerator.swift`
- `RoomPlanExampleApp/FloorPlanView.swift`
- `RoomPlanExampleApp/SVGExporter.swift`

