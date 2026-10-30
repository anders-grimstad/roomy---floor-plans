---
date: 2026-06-12
topic: roomy-app-review
focus: Full review of the Roomy app — features, design, UX; execute top three
mode: repo-grounded
---

# Ideation: Roomy Full App Review

## Grounding Context

**Codebase Context:** SwiftUI iOS app on Apple RoomPlan (LiDAR), recently migrated from UIKit (`.memory/` docs are stale — they describe the old storyboard architecture). iOS 26 Liquid Glass adoption with pre-26 fallbacks. Flow: glass home screen (rotating Unsplash backgrounds, Silkscreen pixel font, playful Krusedull Studios copy) → scan with background compass/north calibration → 3D results (Export USDZ+JSON+metadata) → 2D floor plan (furniture/labels/dimensions/north-up toggles; export SVG/PNG/PDF/JSON; manual Save). `SavedScansStore` persists floorplan.json + thumbnail.png + room.usdz per scan.

Key defects found: saved-scans list has no delete/rename/3D viewing (room.usdz written but never read back); PNG/PDF exports render the *interactive UI* at hardcoded 390×844 with button chrome baked in (`FloorPlanScreen.swift:243-257`); scans are silently lost unless the user navigates Done → 2D View → Save (no save path on the 3D result screen); raw CapturedRoom JSON is discarded after capture (only derived data persists).

**External Context:** Post-scan editing is the competitive battleground (Polycam, magicplan); QuickLook gives free in-app USDZ/AR viewing; StructureBuilder (WWDC23) merges rooms into whole-home plans; tap-to-measure is category standard; title block/scale bar is what makes exports usable by contractors. Liquid Glass compatibility mode removed in iOS 27.

**Past Learnings:** none (no docs/solutions/).

## Topic Axes

- capture-experience
- floorplan-interaction
- saved-library
- export-interop
- design-polish

## Ranked Ideas

### 1. Saved-scans library overhaul: delete, rename, 3D viewing, brand styling
**Description:** Add swipe-to-delete (with folder cleanup), rename, and QuickLook 3D/AR preview of the already-persisted `room.usdz` to SavedScansView. Restyle to match the app's personality (Silkscreen accents, better thumbnails, playful empty state) instead of the current bare system List.
**Axis:** saved-library
**Basis:** direct: `SavedScansView.swift` is a 73-line plain List with only a NavigationLink to the 2D plan; `SavedScansStore.roomUSDZURL(for:)` has zero callers in any review path — the 3D model is written to disk for every scan and never viewable again.
**Rationale:** The library is the screen users return to; today it's a roach motel that silently hides the app's most impressive artifact. Restoring access to data already on disk is near-free value.
**Downsides:** QuickLook gives less control than a custom SceneKit viewer; rename UI adds a small amount of state handling.
**Confidence:** 90%
**Complexity:** Medium
**Status:** Explored (implemented 2026-06-12)

### 2. Document-grade exports: render the plan, not a screenshot of the UI
**Description:** Replace the export path (ImageRenderer over the interactive FloorPlanView with stubbed callbacks at fixed 390×844, control chrome included) with a dedicated chrome-free render sized to the plan's real bounds, with a title block (name, date, total area, scale bar). Shared by PNG/PDF export and the saved thumbnail.
**Axis:** export-interop
**Basis:** direct: `FloorPlanScreen.swift:243-257` — `renderFloorPlanImage()` renders the interactive view including back/save/toggle buttons into every export and thumbnail.
**Rationale:** The export is the artifact users actually hand to landlords/contractors; a phone-shaped screenshot with buttons printed on it is the gap between toy and tool.
**Downsides:** Needs careful extraction of the drawing layer from the 31KB FloorPlanView.
**Confidence:** 92%
**Complexity:** Medium
**Status:** Explored (implemented 2026-06-12)

### 3. Never lose a scan: autosave on capture completion
**Description:** Persist every completed scan automatically the moment RoomPlan post-processing finishes (floor plan JSON, thumbnail, USDZ, and the raw CapturedRoom JSON for future re-processing). The 2D screen's Save becomes an update of the existing record; blocking success alert replaced with transient feedback.
**Axis:** saved-library
**Basis:** direct: zero save paths exist in `RoomCaptureSwiftUIView.swift`; `saveScan()` lives only in `FloorPlanScreen.swift:121` — a scan is silently destroyed if the user exports the 3D model and leaves, or taps Cancel.
**Rationale:** A LiDAR scan costs minutes of physical effort; losing it via the most common navigation gestures is the most expensive failure available in this app. Cameras don't have save buttons.
**Downsides:** Library accumulates scans faster — mitigated by survivor #1's delete.
**Confidence:** 88%
**Complexity:** Low-Medium
**Status:** Explored (implemented 2026-06-12)

### 4. Tap-to-measure on the 2D floor plan
**Description:** Tap two points for a live distance readout (pixel tape-measure with Silkscreen badge, snapping to walls/corners); tap a wall for its length. The typed geometry in FloorPlanExportData already supports it.
**Axis:** floorplan-interaction
**Basis:** external: Polycam and magicplan ship tap-to-measure as core; direct: the home-screen copy mocks the tommestokk, yet the app cannot answer "how far is the door from the window".
**Rationale:** The most common question about a floor plan is an arbitrary distance the auto-dimensions don't show — this is the feature that literally fulfils the stated mission.
**Downsides:** Gesture/hit-testing work inside a large Canvas view; snapping needs tuning.
**Confidence:** 80%
**Complexity:** Medium
**Status:** Unexplored

### 5. Persist raw CapturedRoom → multi-room "Home" merging
**Description:** Save the encoded CapturedRoom JSON in each scan folder (prerequisite, ~20 lines — partially landed with #3), then build "Home" containers that merge room scans into a whole-house floor plan via RoomPlan's StructureBuilder.
**Axis:** capture-experience
**Basis:** direct: `SavedScansStore.saveScan` previously wrote only derived data; external: StructureBuilder (WWDC23) merges CapturedRooms into a CapturedStructure — magicplan/Polycam organize around multi-room projects.
**Rationale:** People want a floor plan of their *home*, not one room; this is the identity-expanding move the mission statement already promises. Raw persistence also makes old scans improve retroactively whenever the generator improves.
**Downsides:** Merging UX (which rooms, adjacency, error states) is a real design project.
**Confidence:** 75%
**Complexity:** High (persistence part: Low — landed with #3)
**Status:** Unexplored

### 6. Surface scan confidence: report card + cone-of-uncertainty walls
**Description:** Use RoomPlan's per-surface confidence (currently discarded): post-scan playful report card ("B+. That corner is suspicious.") and fuzzy/sketchy stroke rendering for low-confidence walls in the plan and exports.
**Axis:** capture-experience
**Basis:** external: CapturedRoom.Surface carries `confidence`; NOAA's cone of uncertainty proves laypeople read certainty from stroke treatment.
**Rationale:** Accuracy is the app's identity; making uncertainty visible is how a side project earns "accurate" credibility.
**Downsides:** Risks visual noise; grading thresholds need tuning.
**Confidence:** 70%
**Complexity:** Medium
**Status:** Unexplored

### 7. Ghost furniture: "will it fit?"
**Description:** Drag true-scale labeled rectangles (couch 220×95, custom sizes) onto the plan, rotate, see clearance against walls and openings.
**Axis:** floorplan-interaction
**Basis:** external: IKEA Kreativ and magicplan show furnishing decisions are the durable post-scan use case.
**Rationale:** Nobody wants a floor plan — they want answers, usually "will it fit". Strongest retention reframe within the app's identity.
**Downsides:** Largest new-feature scope of the survivors; needs persistence of placed ghosts to pay off.
**Confidence:** 65%
**Complexity:** Medium-High
**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Deferred/skippable north calibration (3 frames converged on it) | Basis doesn't hold — scanning already starts instantly and calibration already runs silently in the background (ARSession delegate); there is no upfront gate to remove |
| 2 | Pixel-blueprint render theme / plan as brand artifact | Charming but speculative value vs cost; better as a brainstorm variant after exports are fixed |
| 3 | Non-destructive edits.json delta layer | Premature — no editing features exist yet to ride on it |
| 4 | RoomyTheme design-kit extraction | Engineering hygiene, not user-facing; partially falls out of implementing survivors 1–3 |
| 5 | Re-scan takes + ghost diff | Niche, speculative usage pattern |
| 6 | .roomy zip bundle / Roomy Card | Real but minor; noted as follow-up inside export work rather than standalone survivor |
| 7 | Eyes-up voice/haptic scanning coach | High effort, unvalidated demand |
| 8 | Library-as-home-screen flip | Too disruptive to the brand-defining home screen for current value |
| 9 | Pre-flight checklist / Room-Dex ticker / envelope protection | Folded into survivor #6 (scan confidence) as the strongest single representative of the quality-feedback cluster |
| - | axis: design-polish | No dedicated survivor — polish is folded into survivors 1–3 (deliberate) |
