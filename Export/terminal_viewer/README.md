# Terminal Floor Plan Viewer

A terminal-based visualizer for RoomPlan JSON exports. Renders 2D floor plans directly in your terminal using Unicode box-drawing characters.

## Features

- 📐 Visualizes floor plans from RoomPlan LiDAR scans
- 🏠 Shows walls, doors, windows, and furniture
- 🎨 Uses Unicode characters for clean terminal rendering
- ⚙️ Configurable scale and canvas size
- 🚀 No external dependencies (pure Python)

## Usage

### Basic usage
```bash
python3 floorplan_viewer.py -i ../room.json
```

### Custom size and scale
```bash
python3 floorplan_viewer.py -i ../room.json --width 150 --height 50 --scale 5.0
```

### Without objects/furniture
```bash
python3 floorplan_viewer.py -i ../room.json --no-objects
```

### Auto-align to dominant wall direction
```bash
python3 floorplan_viewer.py --align walls
```

### Auto-align to minimize bounding box (most compact)
```bash
python3 floorplan_viewer.py --align bbox
```

## Options

- `-i, --input PATH` - Path to RoomPlan Room.json file (default: ../room.json)
- `--scale FLOAT` - Characters per meter, higher = larger output (default: 4.0)
- `--width INT` - Canvas width in characters (default: 120)
- `--height INT` - Canvas height in characters (default: 40)
- `--align {none,walls,bbox}` - Alignment strategy:
  - `none` - No rotation (default, as scanned)
  - `walls` - Rotate to align dominant wall direction horizontally/vertically
  - `bbox` - Rotate to minimize bounding box area (most compact representation)
- `--no-reference-origin` - Don't apply referenceOriginTransform
- `--no-objects` - Don't draw furniture/objects
- `--no-labels` - Don't show object labels

## Legend

- `━` = Walls
- `▓` = Doors
- `█` = Windows
- `▒` = Furniture/objects
- `·` = Floor area

## Requirements

- Python 3.6+
- No external dependencies

## Example Output

The viewer will display information about your floor plan and render it using Unicode characters:

```
Loading floor plan from: ../room.json
Bounds: X=[-7.23, 7.45]m, Y=[-4.12, 4.28]m
Size: 14.68m × 8.40m
Found: 1 floor(s), 12 wall(s), 3 door(s), 2 window(s), 15 object(s)

[ASCII art floor plan will be displayed here]
```

## Notes

- The viewer is self-contained and includes all necessary coordinate transformation logic
- For higher resolution output, increase both `--scale` and `--width/--height` proportionally
- The terminal must support Unicode characters for proper rendering

### About Orientation

RoomPlan scans are **not** oriented to compass north. The orientation is based on where you started scanning and which direction the device was facing. Each scan will have a different orientation unless you always start from the exact same spot.

**Alignment Options:**
- **`--align walls`**: Analyzes all walls and rotates the plan so the dominant wall direction is horizontal or vertical. Useful for making floor plans look more "architectural"
- **`--align bbox`**: Rotates to find the angle that creates the most compact bounding box. Good for fitting large floor plans in limited space
- **`--align none`**: Shows the plan exactly as scanned (default)
