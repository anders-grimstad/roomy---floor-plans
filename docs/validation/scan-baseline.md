# Roomy scan validation baseline

## What the app implements

The app starts one `RoomCaptureView` with an owned `ARSession`. Done calls
`captureSession.stop()` and receives one processed `CapturedRoom`. It does not
collect a series of rooms, call `StructureBuilder`, retain an AR world map, or
keep tracking running between completed scans for a merge workflow.

`FloorPlanGenerator` extracts every floor polygon and room section returned in
that result. It retains their `story` values. The 2D renderer and SVG exporter
draw all outlines together; there is no storey selector or per-storey filtering.
Multiple floor *surfaces* therefore do not prove multiple storeys are supported.
Whether a continuous capture across adjacent rooms works well needs a physical
scan; source inspection cannot establish capture quality.

Apple's current [structure scanning documentation](https://developer.apple.com/documentation/roomplan/scanning-the-rooms-of-a-single-structure)
states that captured structures can contain rooms at different floor heights
and on different storeys. That framework capability is broader than Roomy's
current single-result capture flow. New scan merging and storey selection are
outside this update.

## Data flow to check

1. `RoomCaptureSwiftUIView`: scan completes → generate floor plan → render
   thumbnail → `SavedScansStore.saveScan` → write USDZ and raw room JSON.
2. `SavedScansStore`: Documents/SavedScans/index.json plus one directory per
   scan containing floorplan.json, thumbnail.png, room.usdz and room.json.
3. `SavedScansView`: reopen the saved floorplan.json in `FloorPlanScreen` or
   display room.usdz using Quick Look. Rename updates the index; delete removes
   the directory and index entry.
4. `FloorPlanScreen`: toggle raw/north-up coordinates, update the existing scan,
   and export SVG, JSON, PNG, or PDF. Existing PNG/PDF output uses a shared plan
   drawing with title, date, area, and scale bar, rather than a UI screenshot.

Baseline limitation: raw room JSON and USDZ creation on automatic save were
best-effort writes in the original code. A saved floor plan alone does not prove
both supplemental assets were successfully created. Check the files explicitly.

## Repeatable physical-device procedure

Status: **not run**. This repository contains no real LiDAR scan fixtures.
The automated fixture is explicitly synthetic exported geometry.

Record device, OS/build, app commit, lighting, magnetic interference, and date.
Use an ordinary tape/laser to record independent reference distances; report
observed differences in centimetres and percent rather than assuming LiDAR
accuracy. Do not substitute simulator results for these checks.

For each route below, do two takes from different starting directions:

| Route | Independent references | Inspect |
| --- | --- | --- |
| One rectangular room | Four wall lengths, one door width, two diagonals | Closed outline, wall/door/window presence, scale, orientation, plausible floor area |
| Two connected rooms | Both rooms' lengths/widths and shared doorway | Both room regions present, doorway aligned, no duplicated boundary/overlap, combined area |
| Downstairs → stairs → upstairs | Each storey's reference dimensions and landing position | Capture/tracking behavior on stairs, story metadata, 3D elevations, overlapping 2D geometry; record unsupported behavior explicitly |

For every take:

- Finish the scan and leave directly from the 3D result. Reopen Saved Scans and
  confirm automatic persistence without visiting 2D first.
- Open the 2D plan and 3D preview. Inspect geometry against the reference notes.
- Toggle north-up on/off twice. Record unavailable calibration honestly; verify
  doorway/furniture positions and dimensions remain consistent after rotation.
- Save, terminate/relaunch, reopen, and repeat the orientation check. Confirm
  the same saved scan is updated, rather than duplicated.
- Export all four 2D formats and the 3D bundle. Open each in an independent
  viewer; inspect dimensions, room labels, clipping, title/date/area and scale.
  The JSON and SVG must remain usable geometry exports.
- Retrieve the app's Documents container in Xcode Devices and Simulators.
  Confirm the scan's raw room JSON, USDZ, floor plan and thumbnail exist.
- Rename the scan; reopen it. Delete a disposable take; check its directory is
  removed while other scans remain readable.

Record each observation as PASS, FAIL, or NOT RUN with filenames/screenshots.
Keep original real captures locally; don't commit photos or home scans by default.

## Automated characterization

`tests/fixtures/synthetic-connected-rooms.json` describes two adjacent rectangles
with hand-checked areas 12 + 6 = 18 m² and a 4 m reference wall. It is not an
Apple capture or a measurement-accuracy test. `tests/ScanBaseline.swift` exercises
the app's actual geometry, JSON conversion, north-up save/reopen round trip,
legacy optional metadata, room identity, furniture label, and SVG exporter.
The stored bounds include the existing half-metre display margin on each side.

The same runner also characterizes the actual library store using a temporary
library and an AppKit image adapter. It checks save/reopen, thumbnail decoding,
update without duplication, description preservation through plan updates and
renaming, raw-file preservation, and deletion without affecting another scan.
Dates are compared to their initially persisted ISO-8601 values, which use
second precision, rather than to the constructor's fractional-second `Date`.

Run the local checks using `scripts/verify-local.sh` from the repository root.
