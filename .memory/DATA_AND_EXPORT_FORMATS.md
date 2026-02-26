## Data and export formats

This repo has two “layers” of data:

- **RoomPlan capture output**: `CapturedRoom` (3D scene semantics + geometry).
- **Derived 2D floor plan**: `FloorPlanData` and its export wrappers (SVG/PNG/PDF/custom JSON).

### Capture results (RoomPlan)

#### In-memory

- The post-processed capture result is held as:
  - `finalResults: CapturedRoom?` in `RoomCaptureViewController`.

#### Exported files (from the app)

When the user taps **Export** in the capture screen, the app writes to a temp folder:

- **Folder**: `FileManager.default.temporaryDirectory/Export/`
- **Files**:
  - `Room.json` (JSON-encoded `CapturedRoom`)
  - `Room.usdz` (USDZ export from `CapturedRoom.export(...)`)
- **Sharing**:
  - Shares the **folder URL** via `UIActivityViewController` so both files go together.

File: `RoomPlanExampleApp/RoomCaptureViewController.swift`

#### USDZ export options

The capture controller documents these export options:

- `.mesh` (used here)
- `.parametric` (exports unit cubes)
- `.all` (both in one USDZ)

File: `RoomPlanExampleApp/RoomCaptureViewController.swift`

### RoomPlan JSON details (important for tooling)

The Python utilities under `Export/` assume the JSON follows the “v2-style” output and highlight these details:

- **4x4 transforms are stored as 16 floats** in **column-major** order (simd layout).
- The 2D floor plan mapping used by both Swift and Python is:
  - RoomPlan axes: X=right, Y=up, Z=forward
  - Floor plan axes: \(x = -worldX\), \(y = worldZ\)
- Python tooling can optionally apply `referenceOriginTransform` for consistent world alignment across elements.

Files:
- `Export/conversionscript.py`
- `Export/terminal_viewer/floorplan_viewer.py`

### Derived 2D floor plan (Swift)

#### In-memory model

- `FloorPlanGenerator` converts `CapturedRoom` → `FloorPlanData`.
- `FloorPlanData` contains:
  - floor outlines
  - walls
  - doors
  - windows
  - objects (furniture)
  - sections (room labels)
  - dimensions (measurement annotations)
  - bounds + totalArea

File: `RoomPlanExampleApp/FloorPlanGenerator.swift`

#### Coordinate conventions

- **3D → 2D**: `FloorPlanPoint.fromWorld(...)` maps `(-world.x, world.z)`.
- **Rotation**: `simd_float4x4.floorPlanRotation` is computed as `-(roll - yaw)` based on extracted euler-like angles.

File: `RoomPlanExampleApp/FloorPlanGenerator.swift`

### Floor plan exports (from `FloorPlanViewController`)

When the user taps **Export** on the floor plan screen, the app presents an action sheet and supports:

- **SVG**: generated from `FloorPlanData` via `SVGExporter`
  - File: `RoomPlanExampleApp/SVGExporter.swift`
  - Output: `FloorPlan.svg` (temp directory)

- **PNG**: rendered snapshot of the hosted SwiftUI view via `UIGraphicsImageRenderer`
  - Output: shared as a `UIImage` item (`FloorPlan.png` is used as a display name)

- **PDF**: rendered from the hosted view layer into a PDF context
  - Output: `FloorPlan.pdf` (temp directory)

- **Custom JSON**: `FloorPlanExportData` (Codable) derived from `FloorPlanData`
  - Output: `FloorPlan.json` (temp directory)

File: `RoomPlanExampleApp/FloorPlanViewController.swift`

### Floor plan JSON schema (`FloorPlanExportData`)

This is a stable, simplified schema that’s easier to consume than the raw RoomPlan `CapturedRoom` JSON.

#### Top-level fields

- `version` (string, currently `"2.0"`)
- `generatedAt` (date)
- `totalArea` (number, m²)
- `bounds`:
  - `x`, `y`, `width`, `height`
- `floorOutlines[]`:
  - `id`, `story`, `area`, `outline` (array of `[x, y]` points)
- `walls[]`: `startX`, `startY`, `endX`, `endY`, `length`
- `doors[]`: `startX`, `startY`, `endX`, `endY`, `width`, `angle`, `isOpen`
- `windows[]`: `startX`, `startY`, `endX`, `endY`, `width`, `angle`
- `objects[]`: `category`, `label`, `x`, `y`, `width`, `depth`, `angle`
- `sections[]`: `label`, `x`, `y`, `story`

File: `RoomPlanExampleApp/FloorPlanViewController.swift` (see `FloorPlanExportData`)

