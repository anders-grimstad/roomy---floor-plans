# Create a 3D model of an interior room by guiding the user through an AR experience

Highlight physical structures and display text that guides a user to scan the shape of their physical environment using a framework-provided view.

For more information about the app and how it works, see
[Create a 3D model of an interior room by guiding the user through an AR experience]
(https://developer.apple.com/documentation/roomplan/create_a_3d_model_of_an_interior_room_by_guiding_the_user_through_an_ar_experience) in the
developer documentation.

## WWDC experiments

On iOS 27, open a saved scan's 2D plan and choose **Annotate** to add native
PaperKit markup. Annotations are stored separately from measured geometry and
included in PNG/PDF exports. Existing scans and earlier OS versions retain
their normal viewing and export paths.

In Saved Scans, swipe from the leading edge or use the context menu to open
**Photo Suggestions**. Choose a room photo, generate a suggested name and
description with Apple's on-device model, review/edit it, and explicitly
accept it. Apple Intelligence must be available; photos are not stored by Roomy.

The **Gaussian Splats · Experimental** home-screen entry opens a licensed Apple
plant scan or a compatible imported Gaussian PLY. It provides orbit, zoom and
reset on supported iOS 27 hardware. It also appears on the unsupported-LiDAR
screen, since viewing splats does not require RoomPlan capture support.

Run `bash scripts/verify-local.sh` on macOS for geometry, persistence, legacy
compatibility and parser checks.

On macOS 27 with supported Apple GPU hardware, `bash scripts/verify-native.sh`
also renders native markup, PNG/PDF export bodies, and the real plant splat.
The export harness uses AppKit adapters for UIKit colors and images; iPhone
interaction and physical scan checks remain separate.

Device procedures and verification limits:

- [Scan baseline](docs/validation/scan-baseline.md)
- [Annotations](docs/validation/annotations.md)
- [Photo suggestions](docs/validation/photo-suggestions.md)
- [Gaussian splats](docs/validation/gaussian-splats.md)

## Local JSON floor plan renderer (macOS)

Use `scripts/plot_floorplan_json.py` to render floor plans directly from exported JSON for deterministic orientation testing.

### Install dependency

```bash
python3 -m pip install matplotlib
```

### Compare raw vs north-up

```bash
python3 scripts/plot_floorplan_json.py "/Users/anders.grimstad@m10s.io/Downloads/FloorPlan 7.json" --output "/tmp/floorplan7_compare.png"
```

This generates a 2-panel PNG:
- Left: raw room orientation (`desiredNorthUp=false`)
- Right: north-up orientation (`desiredNorthUp=true`)

### Render one mode only

```bash
python3 scripts/plot_floorplan_json.py "/Users/anders.grimstad@m10s.io/Downloads/FloorPlan 7.json" --force-north-up true --output "/tmp/floorplan7_north_up.png"
python3 scripts/plot_floorplan_json.py "/Users/anders.grimstad@m10s.io/Downloads/FloorPlan 7.json" --force-north-up false --output "/tmp/floorplan7_raw.png"
```

### Optional interactive display

```bash
python3 scripts/plot_floorplan_json.py "/Users/anders.grimstad@m10s.io/Downloads/FloorPlan 7.json" --show
```

### Formula playground (compare more calculations)

List supported formulas:

```bash
python3 scripts/plot_floorplan_json.py --list-modes
```

Render multiple hypotheses side-by-side:

```bash
python3 scripts/plot_floorplan_json.py "/Users/anders.grimstad@m10s.io/Downloads/FloorPlan 7.json" \
  --modes raw,heading_only,yaw_only,heading_minus_yaw,heading_minus_yaw_plus_180,room_to_north,room_to_north_plus_180,app_north_up \
  --output "/tmp/floorplan7_formulas.png"
```
