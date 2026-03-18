# Create a 3D model of an interior room by guiding the user through an AR experience

Highlight physical structures and display text that guides a user to scan the shape of their physical environment using a framework-provided view.

For more information about the app and how it works, see
[Create a 3D model of an interior room by guiding the user through an AR experience]
(https://developer.apple.com/documentation/roomplan/create_a_3d_model_of_an_interior_room_by_guiding_the_user_through_an_ar_experience) in the
developer documentation.

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
