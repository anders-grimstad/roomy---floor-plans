---
name: Live minimap overlay
overview: Add a UniFi-style minimap overlay during RoomPlan scanning using a UIKit UIView backed by CAShapeLayer. It stays centered on the device, rotates heading-up, and accumulates completed rooms in different colors while optionally rendering the current in-progress room if RoomPlan provides live geometry updates.
todos:
  - id: add-minimap-view
    content: Implement MinimapView (UIView + CAShapeLayer) with mapContainerLayer transform for heading-up + scanner-centered rendering.
    status: completed
  - id: wire-pose-updates
    content: Read camera pose from the ARSession used by RoomPlan and call minimapView.updatePose(position2D, headingRad) at frame rate (or throttled).
    status: completed
    dependencies:
      - add-minimap-view
  - id: render-completed-rooms
    content: On captureView(didPresent processedResult:), generate FloorPlanData via FloorPlanGenerator and append a completed-room layer with palette color.
    status: completed
    dependencies:
      - add-minimap-view
  - id: render-current-room
    content: If available, use RoomPlan live updates during scanning to update the current-room minimap layer (throttle to ~5–10 Hz); otherwise keep current layer empty.
    status: completed
    dependencies:
      - add-minimap-view
  - id: ui-placement
    content: Add minimap overlay to RoomCaptureViewController (bottom center), set background/rounded corners, and ensure it stays visible while scanning.
    status: completed
    dependencies:
      - add-minimap-view
---

# Live minimap overlay (CAShapeLayer)

## Target behavior

- **Always visible while scanning** (including the first room).
- **Anchored to the scanner**: the device marker stays centered; the map translates under it.
- **Heading-up**: the map rotates so forward is “up”; the device arrow can stay fixed pointing up.
- **Accumulate rooms**: each completed room persists on the minimap in a distinct color; current room uses a “current scan” color.

## Data sources

- **Pose (position + heading)**: pull from ARKit camera each frame.
- Use the `ARSession` backing RoomPlan (preferred) or the most direct pose access RoomPlan exposes.
- Convert to floorplan 2D using your convention: `x = -worldX`, `y = worldZ`.
- **Geometry**:
- **Completed rooms**: in `captureView(didPresent processedResult:)`, build `FloorPlanData` via existing `FloorPlanGenerator`, then store as a minimap layer (assign next color).
- **In-progress room (optional but recommended)**: if RoomPlan provides a live update callback during capture (e.g., a `didUpdate`/`didChange` style callback with `CapturedRoomData`), convert that to a lightweight set of wall/window/door segments and render as “current” layer. Throttle to ~5–10 Hz.
- If live RoomPlan geometry updates aren’t available in your SDK version, the minimap still works (pose + accumulated completed rooms). You can add a “trail” later if desired.

## Rendering architecture (UIKit)

- Add a new `UIView` overlay (e.g., `MinimapView`) that owns layers:
- `mapContainerLayer`: a parent `CALayer` whose `affineTransform` applies **translate (center on scanner)**, **rotate (heading-up)**, and **scale (meters→pixels)**.
- One `CAShapeLayer` per completed room (stroke only) + one `CAShapeLayer` for current room.
- `deviceMarkerLayer`: drawn at view center (circle + triangle). This layer is NOT transformed by map rotation (or rotate it if you prefer).

### Coordinate transform (core idea)

Keep all room paths in **floorplan meters**.On each pose update:

- Compute `pos2D_m` and `headingRad`.
- Set `mapContainerLayer` transform to:
- translate to view center,
- rotate by `-headingRad` (heading-up),
- scale by `pixelsPerMeter`,
- translate by `(-pos2D_m.x, -pos2D_m.y)` (anchor on scanner).

This keeps the device centered and the map moving/rotating around it.

## Implementation steps

- Create `MinimapView` (new file) with:
- API:
    - `setCompletedRooms([MinimapRoom]) `(or incremental `appendCompletedRoom`)
    - `setCurrentRoomGeometry(_:)`
    - `updatePose(position2D: CGPoint, headingRad: CGFloat)`
- Internals:
    - room color palette (cycle)
    - building `CGPath`s from `FloorPlanData` wall/door/window segments
    - throttling helpers for geometry updates
- Update [`RoomPlanExampleApp/RoomCaptureViewController.swift`](/Users/anders.grimstad@m10s.io/Documents/GitHub/roomscannersample/RoomPlanExampleApp/RoomCaptureViewController.swift):
- Add minimap overlay view (bottom center, matching UniFi placement).
- Hook pose updates:
    - Prefer attaching as `ARSessionDelegate` on the AR session used by RoomPlan.
    - On each frame: compute `position2D` and `headingRad`, call `minimapView.updatePose(...)`.
- Hook geometry updates:
    - On `captureView(didPresent processedResult:)`: generate `FloorPlanData`, append as a completed room layer.
    - If live RoomPlan updates are available: update current room layer at a throttled rate.
- Color handling:
- Maintain an array of completed rooms with assigned colors.
- Current room can be a fixed accent color; completed rooms get palette colors (UniFi-like: newest room in bright green, older in gray/white).

## Files to add/change

- Add: `RoomPlanExampleApp/MinimapView.swift`
- Change: `RoomPlanExampleApp/RoomCaptureViewController.swift`
- (Optional) Add: `RoomPlanExampleApp/MinimapModels.swift` for small structs like `MinimapRoom`, `MinimapPose`.

## Verification

- Start scanning: minimap visible immediately; marker centered.
- Walk/turn: minimap rotates heading-up and moves under marker.
- Finish room: completed room outline persists in a distinct color.
- Scan another room: current room outline updates in its color; previous room remains.

## Todos

- add-minimap-view: Implement `MinimapView` with CAShapeLayers and pose-driven container transform.
- wire-pose-updates: Feed minimap pose from the RoomPlan/ARKit camera each frame (heading-up).