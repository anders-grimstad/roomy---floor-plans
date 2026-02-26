#!/usr/bin/env python3
"""
Terminal-based 2D floor plan visualizer for RoomPlan JSON exports.

Renders the floor plan using Unicode box-drawing characters directly in the terminal.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import os
from typing import List, Tuple, Optional, Sequence

# Type aliases
Mat4 = List[float]
Vec3 = Tuple[float, float, float]
Vec2 = Tuple[float, float, float]


# ----------------------------------------
# Linear algebra helpers (from conversionscript.py)
# ----------------------------------------

def mat4_mul(a: Mat4, b: Mat4) -> Mat4:
    """Multiply two 4x4 matrices stored in column-major order."""
    out = [0.0] * 16
    for col in range(4):
        for row in range(4):
            out[col * 4 + row] = (
                a[0 * 4 + row] * b[col * 4 + 0]
                + a[1 * 4 + row] * b[col * 4 + 1]
                + a[2 * 4 + row] * b[col * 4 + 2]
                + a[3 * 4 + row] * b[col * 4 + 3]
            )
    return out


def mat4_transform_point(m: Mat4, p: Vec3) -> Vec3:
    """Transform a point (x,y,z,1) by a column-major 4x4 matrix."""
    x, y, z = p
    out_x = m[0] * x + m[4] * y + m[8] * z + m[12]
    out_y = m[1] * x + m[5] * y + m[9] * z + m[13]
    out_z = m[2] * x + m[6] * y + m[10] * z + m[14]
    out_w = m[3] * x + m[7] * y + m[11] * z + m[15]
    if out_w and abs(out_w - 1.0) > 1e-6:
        return (out_x / out_w, out_y / out_w, out_z / out_w)
    return (out_x, out_y, out_z)


def world_to_floorplan_2d(world: Vec3) -> Vec2:
    """Convert 3D world coordinates to 2D floor plan coordinates."""
    return (-world[0], world[2])


def mat4_floorplan_rotation_rad(m: Mat4) -> float:
    """Extract floor plan rotation from transform matrix."""
    def at(col: int, row: int) -> float:
        return float(m[col * 4 + row])

    v = max(-1.0, min(1.0, -at(2, 1)))
    pitch = math.asin(v)
    yaw = math.atan2(at(2, 0), at(2, 2))
    roll = math.atan2(at(0, 1), at(1, 1))
    return -(roll - yaw)


def category_name(value: object) -> str:
    """Extract category name from RoomPlan enum-style dict."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and value:
        return str(next(iter(value.keys())))
    return "unknown"


# ----------------------------------------
# Rotation and alignment helpers
# ----------------------------------------

def rotate_point_2d(p: Vec2, angle_rad: float, center: Vec2 = (0.0, 0.0)) -> Vec2:
    """Rotate a 2D point around a center point."""
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)

    # Translate to origin
    x = p[0] - center[0]
    y = p[1] - center[1]

    # Rotate
    x_rot = x * cos_a - y * sin_a
    y_rot = x * sin_a + y * cos_a

    # Translate back
    return (x_rot + center[0], y_rot + center[1])


def segment_angle(seg: Segment2D) -> float:
    """Calculate the angle of a line segment in radians."""
    dx = seg.b[0] - seg.a[0]
    dy = seg.b[1] - seg.a[1]
    return math.atan2(dy, dx)


def segment_length(seg: Segment2D) -> float:
    """Calculate the length of a line segment."""
    dx = seg.b[0] - seg.a[0]
    dy = seg.b[1] - seg.a[1]
    return math.sqrt(dx * dx + dy * dy)


def snap_to_cardinal(angle_rad: float) -> float:
    """Snap angle to nearest cardinal direction (0, 90, 180, 270 degrees)."""
    # Normalize to [0, 2*pi)
    angle = angle_rad % (2 * math.pi)

    # Find nearest multiple of pi/2
    quadrant = round(angle / (math.pi / 2))
    return quadrant * (math.pi / 2)


def calculate_dominant_wall_angle(walls: List[Tuple[str, Segment2D, float]]) -> float:
    """
    Calculate the dominant wall direction using weighted histogram.
    Longer walls have more influence on the result.
    Returns the angle to rotate by to align walls to nearest cardinal direction.
    """
    if not walls:
        return 0.0

    # Calculate angles and weights (by length)
    angles_and_weights = []
    for _id, seg, _w in walls:
        angle = segment_angle(seg)
        length = segment_length(seg)
        # Normalize angle to [0, pi) since walls have no inherent direction
        angle_normalized = angle % math.pi
        angles_and_weights.append((angle_normalized, length))

    # Find the weighted average angle
    # Use circular mean for angles
    sum_sin = sum(math.sin(2 * a) * w for a, w in angles_and_weights)
    sum_cos = sum(math.cos(2 * a) * w for a, w in angles_and_weights)

    dominant_angle = math.atan2(sum_sin, sum_cos) / 2

    # Determine which cardinal direction (0 or pi/2) is nearest
    # and return the rotation needed to align to it
    if abs(dominant_angle) < math.pi / 4:
        # Closer to horizontal (0) - return the angle as-is
        return dominant_angle
    else:
        # Closer to vertical (pi/2) - return angle relative to pi/2
        return dominant_angle - math.pi / 2


def calculate_bounding_box_area(points: List[Vec2], rotation: float) -> float:
    """Calculate the bounding box area for a given rotation."""
    if not points:
        return float('inf')

    # Rotate all points
    center = (0.0, 0.0)
    rotated = [rotate_point_2d(p, rotation, center) for p in points]

    # Calculate bounding box
    xs = [p[0] for p in rotated]
    ys = [p[1] for p in rotated]

    width = max(xs) - min(xs)
    height = max(ys) - min(ys)

    return width * height


def find_minimal_bounding_box_rotation(points: List[Vec2]) -> float:
    """
    Find rotation angle that minimizes bounding box area.
    Tests rotations in 1-degree increments from 0 to 90 degrees.
    """
    if not points:
        return 0.0

    best_angle = 0.0
    best_area = float('inf')

    # Test angles from 0 to 90 degrees (pi/2 radians)
    # We only need to test this range due to rectangular symmetry
    for angle_deg in range(91):
        angle_rad = math.radians(angle_deg)
        area = calculate_bounding_box_area(points, angle_rad)

        if area < best_area:
            best_area = area
            best_angle = angle_rad

    return best_angle


def apply_rotation_to_geometry(
    outlines: List[FloorOutline2D],
    walls: List[Tuple[str, Segment2D, float]],
    doors: List[Tuple[str, Segment2D, float]],
    windows: List[Tuple[str, Segment2D, float]],
    objects: List[FloorObject2D],
    angle_rad: float,
    center: Vec2
) -> None:
    """Apply rotation to all geometry in-place."""
    # Rotate floor outlines
    for floor in outlines:
        floor.outline = [rotate_point_2d(p, angle_rad, center) for p in floor.outline]

    # Rotate linear elements
    for elements in [walls, doors, windows]:
        for i, (_id, seg, w) in enumerate(elements):
            seg.a = rotate_point_2d(seg.a, angle_rad, center)
            seg.b = rotate_point_2d(seg.b, angle_rad, center)

    # Rotate objects (both position and orientation)
    for obj in objects:
        obj.center = rotate_point_2d(obj.center, angle_rad, center)
        obj.angle_rad += angle_rad  # Update object's rotation angle


# ----------------------------------------
# Data structures
# ----------------------------------------

class Segment2D:
    def __init__(self, a: Vec2, b: Vec2):
        self.a = a
        self.b = b


class FloorOutline2D:
    def __init__(self, identifier: str, story: Optional[int], outline: List[Vec2]):
        self.identifier = identifier
        self.story = story
        self.outline = outline


class FloorObject2D:
    def __init__(self, identifier: str, category: str, center: Vec2, width_m: float, depth_m: float, angle_rad: float):
        self.identifier = identifier
        self.category = category
        self.center = center
        self.width_m = width_m
        self.depth_m = depth_m
        self.angle_rad = angle_rad


# ----------------------------------------
# Geometry extraction
# ----------------------------------------

def endpoints_from_transform_and_length(transform: Mat4, length_m: float) -> Tuple[Vec3, Vec3]:
    """Get endpoints of a linear element from its transform and length."""
    half = length_m / 2.0
    p0_local: Vec3 = (-half, 0.0, 0.0)
    p1_local: Vec3 = (half, 0.0, 0.0)
    return (
        mat4_transform_point(transform, p0_local),
        mat4_transform_point(transform, p1_local),
    )


def extract_floor_outlines_2d(data: dict, apply_reference_origin: bool) -> List[FloorOutline2D]:
    """Extract floor outlines from RoomPlan JSON."""
    floors = data.get("floors") or []
    if not floors:
        return []

    outlines: List[FloorOutline2D] = []
    ref = data.get("referenceOriginTransform")

    for floor in floors:
        corners = floor.get("polygonCorners") or []
        if not corners:
            continue

        floor_tx: Mat4 = floor["transform"]
        if apply_reference_origin and ref:
            floor_tx = mat4_mul(ref, floor_tx)

        outline: List[Vec2] = []
        for corner in corners:
            local: Vec3 = (float(corner[0]), float(corner[1]), float(corner[2]))
            world = mat4_transform_point(floor_tx, local)
            outline.append(world_to_floorplan_2d(world))

        outlines.append(
            FloorOutline2D(
                identifier=str(floor.get("identifier", "")),
                story=floor.get("story"),
                outline=outline,
            )
        )

    return outlines


def extract_linear_elements_2d(
    data: dict,
    key: str,
    apply_reference_origin: bool,
) -> List[Tuple[str, Segment2D, float]]:
    """Extract linear elements (walls, doors, windows) from RoomPlan JSON."""
    out: List[Tuple[str, Segment2D, float]] = []
    items = data.get(key) or []
    if not items:
        return out

    ref_tx = data.get("referenceOriginTransform")
    for item in items:
        item_tx: Mat4 = item["transform"]
        if apply_reference_origin and ref_tx:
            item_tx = mat4_mul(ref_tx, item_tx)

        width_m = float((item.get("dimensions") or [0.0])[0] or 0.0)
        a3, b3 = endpoints_from_transform_and_length(item_tx, width_m)
        out.append(
            (
                str(item.get("identifier", "")),
                Segment2D(world_to_floorplan_2d(a3), world_to_floorplan_2d(b3)),
                width_m,
            )
        )
    return out


def extract_objects_2d(data: dict, apply_reference_origin: bool) -> List[FloorObject2D]:
    """Extract objects (furniture) from RoomPlan JSON."""
    out: List[FloorObject2D] = []
    items = data.get("objects") or []
    if not items:
        return out

    ref_tx = data.get("referenceOriginTransform")
    for item in items:
        item_tx: Mat4 = item["transform"]
        if apply_reference_origin and ref_tx:
            item_tx = mat4_mul(ref_tx, item_tx)

        center_world = mat4_transform_point(item_tx, (0.0, 0.0, 0.0))
        center_2d = world_to_floorplan_2d(center_world)

        dims = item.get("dimensions") or [0.0, 0.0, 0.0]
        width_m = float(dims[0] or 0.0)
        depth_m = float(dims[2] or 0.0)
        angle_rad = mat4_floorplan_rotation_rad(item_tx)

        out.append(
            FloorObject2D(
                identifier=str(item.get("identifier", "")),
                category=category_name(item.get("category")),
                center=center_2d,
                width_m=width_m,
                depth_m=depth_m,
                angle_rad=angle_rad,
            )
        )
    return out


def compute_bounds(points: Sequence[Vec2]) -> Optional[Tuple[float, float, float, float]]:
    """Compute bounding box of a set of points."""
    pts = list(points)
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


# ----------------------------------------
# Terminal rendering
# ----------------------------------------

class DrawChars:
    """Unicode characters for drawing the floor plan."""
    # Walls - bold lines
    WALL_H = '━'
    WALL_V = '┃'
    WALL_CORNER = '╋'

    # Objects - lighter blocks
    OBJECT_FILL = '▒'
    OBJECT_LIGHT = '░'

    # Doors and windows
    DOOR = '▓'
    WINDOW = '█'

    # Floor outline
    OUTLINE_H = '─'
    OUTLINE_V = '│'
    OUTLINE_CORNER = '┼'

    # Empty space
    EMPTY = ' '
    FLOOR = '·'


class TerminalCanvas:
    """A 2D canvas for drawing in the terminal."""

    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        # Initialize with empty spaces
        self.grid = [[DrawChars.EMPTY for _ in range(width)] for _ in range(height)]

    def set_pixel(self, x: int, y: int, char: str):
        """Set a character at the given position."""
        if 0 <= x < self.width and 0 <= y < self.height:
            self.grid[y][x] = char

    def draw_line(self, x0: int, y0: int, x1: int, y1: int, char: str):
        """Draw a line using Bresenham's algorithm."""
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy

        while True:
            self.set_pixel(x0, y0, char)

            if x0 == x1 and y0 == y1:
                break

            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    def draw_thick_line(self, x0: int, y0: int, x1: int, y1: int, char: str, thickness: int = 1):
        """Draw a thick line."""
        if thickness == 1:
            self.draw_line(x0, y0, x1, y1, char)
            return

        # Draw multiple parallel lines for thickness
        for offset in range(-thickness // 2, thickness // 2 + 1):
            if abs(x1 - x0) > abs(y1 - y0):
                # More horizontal, offset in y direction
                self.draw_line(x0, y0 + offset, x1, y1 + offset, char)
            else:
                # More vertical, offset in x direction
                self.draw_line(x0 + offset, y0, x1 + offset, y1, char)

    def draw_rect(self, cx: int, cy: int, w: int, h: int, fill_char: str):
        """Draw a filled rectangle centered at (cx, cy)."""
        x0 = cx - w // 2
        y0 = cy - h // 2

        for dy in range(h):
            for dx in range(w):
                self.set_pixel(x0 + dx, y0 + dy, fill_char)

    def draw_polyline(self, points: List[Tuple[int, int]], char: str, closed: bool = False):
        """Draw a polyline connecting the given points."""
        if len(points) < 2:
            return

        for i in range(len(points) - 1):
            x0, y0 = points[i]
            x1, y1 = points[i + 1]
            self.draw_line(x0, y0, x1, y1, char)

        if closed and len(points) > 2:
            x0, y0 = points[-1]
            x1, y1 = points[0]
            self.draw_line(x0, y0, x1, y1, char)

    def add_text(self, x: int, y: int, text: str):
        """Add text at the given position."""
        for i, char in enumerate(text):
            self.set_pixel(x + i, y, char)

    def render(self) -> str:
        """Render the canvas to a string."""
        lines = []
        for row in self.grid:
            lines.append(''.join(row))
        return '\n'.join(lines)


def meters_to_terminal_coords(
    p: Vec2,
    bounds: Tuple[float, float, float, float],
    chars_per_meter: float,
    canvas_width: int,
    canvas_height: int
) -> Tuple[int, int]:
    """Convert meter coordinates to terminal character coordinates."""
    min_x, min_y, max_x, max_y = bounds

    # Calculate the center offset to center the floor plan
    plan_width = (max_x - min_x) * chars_per_meter
    plan_height = (max_y - min_y) * chars_per_meter

    offset_x = (canvas_width - plan_width) / 2
    offset_y = (canvas_height - plan_height) / 2

    # Convert to terminal coords (flip Y since terminal Y grows downward)
    x = int((p[0] - min_x) * chars_per_meter + offset_x)
    y = int((max_y - p[1]) * chars_per_meter + offset_y)

    return (x, y)


def visualize_floorplan_terminal(
    json_path: str,
    chars_per_meter: float = 4.0,
    canvas_width: int = 120,
    canvas_height: int = 40,
    apply_reference_origin: bool = True,
    show_objects: bool = True,
    show_labels: bool = True,
    align_mode: str = "none",
):
    """
    Visualize the floor plan in the terminal.

    Args:
        align_mode: Alignment strategy - "none", "walls", or "bbox"
    """

    # Load and extract data
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"Loading floor plan from: {json_path}")

    # Extract geometry
    outlines = extract_floor_outlines_2d(data, apply_reference_origin=apply_reference_origin)
    walls = extract_linear_elements_2d(data, "walls", apply_reference_origin=apply_reference_origin)
    doors = extract_linear_elements_2d(data, "doors", apply_reference_origin=apply_reference_origin)
    windows = extract_linear_elements_2d(data, "windows", apply_reference_origin=apply_reference_origin)
    objects = extract_objects_2d(data, apply_reference_origin=apply_reference_origin) if show_objects else []

    # Compute bounds before rotation
    all_points: List[Vec2] = []
    for outline in outlines:
        all_points.extend(outline.outline)
    for _id, seg, _w in walls + doors + windows:
        all_points.append(seg.a)
        all_points.append(seg.b)
    for obj in objects:
        all_points.append(obj.center)

    bounds = compute_bounds(all_points)
    if not bounds:
        print("Error: No drawable geometry found in the JSON file.")
        sys.exit(1)

    # Calculate center point for rotation
    min_x, min_y, max_x, max_y = bounds
    center = ((min_x + max_x) / 2, (min_y + max_y) / 2)

    # Apply alignment rotation if requested
    rotation_angle = 0.0
    if align_mode == "walls":
        # Align based on dominant wall direction
        rotation_angle = -calculate_dominant_wall_angle(walls)
        print(f"Alignment: Rotating by {math.degrees(rotation_angle):.1f}° to align dominant walls")
        apply_rotation_to_geometry(outlines, walls, doors, windows, objects, rotation_angle, center)

    elif align_mode == "bbox":
        # Align to minimize bounding box
        rotation_angle = -find_minimal_bounding_box_rotation(all_points)
        print(f"Alignment: Rotating by {math.degrees(rotation_angle):.1f}° to minimize bounding box")
        apply_rotation_to_geometry(outlines, walls, doors, windows, objects, rotation_angle, center)

    # Recompute bounds after rotation
    all_points = []
    for outline in outlines:
        all_points.extend(outline.outline)
    for _id, seg, _w in walls + doors + windows:
        all_points.append(seg.a)
        all_points.append(seg.b)
    for obj in objects:
        all_points.append(obj.center)

    bounds = compute_bounds(all_points)
    min_x, min_y, max_x, max_y = bounds
    print(f"Bounds: X=[{min_x:.2f}, {max_x:.2f}]m, Y=[{min_y:.2f}, {max_y:.2f}]m")
    print(f"Size: {max_x - min_x:.2f}m × {max_y - min_y:.2f}m")
    print(f"Found: {len(outlines)} floor(s), {len(walls)} wall(s), {len(doors)} door(s), {len(windows)} window(s), {len(objects)} object(s)")
    print()

    # Create canvas
    canvas = TerminalCanvas(canvas_width, canvas_height)

    # Helper to convert coordinates
    def to_canvas(p: Vec2) -> Tuple[int, int]:
        return meters_to_terminal_coords(p, bounds, chars_per_meter, canvas_width, canvas_height)

    # Draw floor outlines first (light)
    for floor in outlines:
        if not floor.outline:
            continue
        points = [to_canvas(p) for p in floor.outline]
        canvas.draw_polyline(points, DrawChars.FLOOR, closed=True)

        # Fill interior with floor character
        if len(points) >= 3:
            min_x_px = min(p[0] for p in points)
            max_x_px = max(p[0] for p in points)
            min_y_px = min(p[1] for p in points)
            max_y_px = max(p[1] for p in points)

            for y in range(min_y_px, max_y_px + 1):
                for x in range(min_x_px, max_x_px + 1):
                    # Simple fill - just fill the bounding box
                    if 0 <= y < canvas.height and 0 <= x < canvas.width:
                        if canvas.grid[y][x] == DrawChars.EMPTY:
                            canvas.set_pixel(x, y, DrawChars.FLOOR)

    # Draw walls (thick and bold)
    wall_thickness = max(1, int(chars_per_meter * 0.1))
    for _id, seg, _w in walls:
        a = to_canvas(seg.a)
        b = to_canvas(seg.b)
        canvas.draw_thick_line(a[0], a[1], b[0], b[1], DrawChars.WALL_H, thickness=wall_thickness)

    # Draw windows
    for _id, seg, _w in windows:
        a = to_canvas(seg.a)
        b = to_canvas(seg.b)
        canvas.draw_line(a[0], a[1], b[0], b[1], DrawChars.WINDOW)

    # Draw doors
    for _id, seg, _w in doors:
        a = to_canvas(seg.a)
        b = to_canvas(seg.b)
        canvas.draw_line(a[0], a[1], b[0], b[1], DrawChars.DOOR)

    # Draw objects
    if show_objects:
        for obj in objects:
            cx, cy = to_canvas(obj.center)

            # Determine dimensions based on rotation angle
            # Normalize angle to [0, 2π)
            angle_normalized = obj.angle_rad % (2 * math.pi)

            # Check if object should be rotated 90° (swap width/depth)
            # Consider angles near 90° (π/2) or 270° (3π/2) as "vertical"
            is_vertical = (math.pi/4 < angle_normalized < 3*math.pi/4) or \
                         (5*math.pi/4 < angle_normalized < 7*math.pi/4)

            if is_vertical:
                # Swap dimensions for 90° rotation
                w_px = max(1, int(obj.depth_m * chars_per_meter))
                h_px = max(1, int(obj.width_m * chars_per_meter))
            else:
                # Normal orientation
                w_px = max(1, int(obj.width_m * chars_per_meter))
                h_px = max(1, int(obj.depth_m * chars_per_meter))

            canvas.draw_rect(cx, cy, w_px, h_px, DrawChars.OBJECT_FILL)

            # Add label if it fits
            if show_labels and len(obj.category) <= w_px:
                label_x = cx - len(obj.category) // 2
                canvas.add_text(label_x, cy, obj.category[:w_px])

    # Add legend at the bottom
    legend_y = canvas_height - 2
    if legend_y > 0:
        legend = f"{DrawChars.WALL_H}=wall  {DrawChars.DOOR}=door  {DrawChars.WINDOW}=window  {DrawChars.OBJECT_FILL}=object  {DrawChars.FLOOR}=floor"
        canvas.add_text(2, legend_y, legend[:canvas_width - 4])

    # Render and display
    print(canvas.render())
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Visualize RoomPlan floor plans in the terminal using Unicode characters."
    )
    parser.add_argument(
        "-i", "--input",
        default="../room.json",
        help="Path to RoomPlan Room.json file (default: ../room.json)"
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=4.0,
        help="Characters per meter (default: 4.0, higher = larger output)"
    )
    parser.add_argument(
        "--width",
        type=int,
        default=120,
        help="Canvas width in characters (default: 120)"
    )
    parser.add_argument(
        "--height",
        type=int,
        default=40,
        help="Canvas height in characters (default: 40)"
    )
    parser.add_argument(
        "--no-reference-origin",
        action="store_true",
        help="Don't apply referenceOriginTransform"
    )
    parser.add_argument(
        "--no-objects",
        action="store_true",
        help="Don't draw furniture/objects"
    )
    parser.add_argument(
        "--no-labels",
        action="store_true",
        help="Don't show object labels"
    )
    parser.add_argument(
        "--align",
        choices=["none", "walls", "bbox"],
        default="none",
        help="Alignment strategy: 'none' (default), 'walls' (align dominant wall direction), 'bbox' (minimize bounding box)"
    )

    args = parser.parse_args()

    try:
        visualize_floorplan_terminal(
            json_path=args.input,
            chars_per_meter=args.scale,
            canvas_width=args.width,
            canvas_height=args.height,
            apply_reference_origin=not args.no_reference_origin,
            show_objects=not args.no_objects,
            show_labels=not args.no_labels,
            align_mode=args.align,
        )
    except FileNotFoundError:
        print(f"Error: Could not find file '{args.input}'", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{args.input}': {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
