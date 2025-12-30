"""
RoomPlan JSON → simple 2D floor plan SVG

Designed to work with RoomPlan v2-style JSON exports (like `Export/Room.json` in this repo).

Key details (relevant to your note about floats/transforms):
- RoomPlan encodes `simd_float4x4` as a flat 16-float array in *column-major* order.
- The sample app in this repo maps the 3D world to a top-down 2D plan as:
    floorPlanX = -worldX
    floorPlanY =  worldZ
  (X is negated to match Apple's guide + the Swift `FloorPlanGenerator` here.)
"""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from typing import Iterable, List, Literal, Optional, Sequence, Tuple

# 16 floats, column-major (simd layout)
Mat4 = List[float]
Vec3 = Tuple[float, float, float]
Vec2 = Tuple[float, float]


# ----------------------------------------
# Linear algebra (no numpy dependency)
# ----------------------------------------


def mat4_mul(a: Mat4, b: Mat4) -> Mat4:
    """Multiply two 4x4 matrices stored in column-major order."""
    out = [0.0] * 16
    # out(col,row) = sum_k a(k,row) * b(col,k)
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


# ----------------------------------------
# RoomPlan → 2D mapping (matches sample app)
# ----------------------------------------


def world_to_floorplan_2d(world: Vec3) -> Vec2:
    # RoomPlan axes: X=right, Y=up, Z=forward.
    # Sample app top-down: x=-X, y=Z
    return (-world[0], world[2])


# ----------------------------------------
# SVG helpers
# ----------------------------------------


def svg_header(view_width: float, view_height: float) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{view_width:.0f}" height="{view_height:.0f}" '
        f'viewBox="0 0 {view_width:.0f} {view_height:.0f}">'
    )


def svg_footer() -> str:
    return "</svg>"


def svg_line(x1: float, y1: float, x2: float, y2: float, stroke: str, width: float, opacity: float = 1.0) -> str:
    return (
        f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
        f'stroke="{stroke}" stroke-width="{width:.2f}" stroke-linecap="square" opacity="{opacity:.3f}" />'
    )


def svg_polyline(points: Sequence[Vec2], stroke: str, width: float, fill: str = "none", close: bool = False) -> str:
    if close and points:
        points = list(points) + [points[0]]
    pts = " ".join([f"{x:.2f},{y:.2f}" for x, y in points])
    return f'<polyline points="{pts}" stroke="{stroke}" fill="{fill}" stroke-width="{width:.2f}" />'


def svg_text(x: float, y: float, text: str, size: float = 12, fill: str = "#666") -> str:
    safe = (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )
    return f'<text x="{x:.2f}" y="{y:.2f}" font-family="Menlo, monospace" font-size="{size:.0f}" fill="{fill}">{safe}</text>'


def svg_text_anchored(
    x: float,
    y: float,
    text: str,
    size: float = 12,
    fill: str = "#666",
    anchor: str = "middle",
    baseline: str = "middle",
) -> str:
    safe = (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )
    return (
        f'<text x="{x:.2f}" y="{y:.2f}" text-anchor="{anchor}" dominant-baseline="{baseline}" '
        f'font-family="Menlo, monospace" font-size="{size:.0f}" fill="{fill}">{safe}</text>'
    )


def svg_rect_rotated(
    cx: float,
    cy: float,
    w: float,
    h: float,
    angle_deg: float,
    fill: str,
    fill_opacity: float,
    stroke: str,
    stroke_width: float,
    rx: float = 3.0,
) -> str:
    # Rotate around center using a group transform.
    x = -w / 2.0
    y = -h / 2.0
    return (
        f'<g transform="translate({cx:.2f} {cy:.2f}) rotate({angle_deg:.2f})">'
        f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{rx:.2f}" '
        f'fill="{fill}" fill-opacity="{fill_opacity:.3f}" stroke="{stroke}" stroke-width="{stroke_width:.2f}" />'
        f"</g>"
    )


# ----------------------------------------
# Geometry extraction from Room.json
# ----------------------------------------


@dataclass(frozen=True)
class Segment2D:
    a: Vec2
    b: Vec2


@dataclass(frozen=True)
class FloorOutline2D:
    identifier: str
    story: Optional[int]
    outline: List[Vec2]


@dataclass(frozen=True)
class FloorObject2D:
    identifier: str
    category: str
    center: Vec2
    width_m: float
    depth_m: float
    angle_rad: float


@dataclass(frozen=True)
class SectionLabel2D:
    story: Optional[int]
    center: Vec2  # meters in floorplan space
    label: str


RoomLabelMode = Literal["index", "story", "id", "index-id", "story-id"]
RoomLabelSource = Literal["auto", "sections", "generated"]
SectionLabelStyle = Literal["small", "normal"]


def endpoints_from_transform_and_length(transform: Mat4, length_m: float) -> Tuple[Vec3, Vec3]:
    half = length_m / 2.0
    # Local segment runs along +X/-X in the element's local frame.
    p0_local: Vec3 = (-half, 0.0, 0.0)
    p1_local: Vec3 = (half, 0.0, 0.0)
    return (
        mat4_transform_point(transform, p0_local),
        mat4_transform_point(transform, p1_local),
    )


def mat4_floorplan_rotation_rad(m: Mat4) -> float:
    """
    Match the Swift sample's rotation extraction:
      euler.x = asin(-self[2][1])
      euler.y = atan2(self[2][0], self[2][2])
      euler.z = atan2(self[0][1], self[1][1])
      floorPlanRotation = -(euler.z - euler.y)

    Note: simd_float4x4 indexing is [column][row], and RoomPlan JSON uses column-major flattening.
    """

    def at(col: int, row: int) -> float:
        return float(m[col * 4 + row])

    # Clamp for asin stability
    v = max(-1.0, min(1.0, -at(2, 1)))
    pitch = math.asin(v)  # noqa: F841 (kept for readability / parity with Swift)
    yaw = math.atan2(at(2, 0), at(2, 2))
    roll = math.atan2(at(0, 1), at(1, 1))
    return -(roll - yaw)


def category_name(value: object) -> str:
    # RoomPlan v2 JSON uses single-key dict enums, e.g. {"table": {}}
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and value:
        return str(next(iter(value.keys())))
    return "unknown"

def format_section_label(label: str) -> str:
    """
    Convert RoomPlan section labels like `livingRoom` → `Living Room`.
    """
    spaced = re.sub(r"([a-z])([A-Z])", r"\1 \2", label or "")
    spaced = spaced.replace("_", " ").strip()
    return spaced.title() if spaced else "Room"


def polygon_area_and_centroid(poly: Sequence[Vec2]) -> Tuple[float, Vec2]:
    """
    Returns (area_m2, centroid) using the shoelace formula.
    If polygon is degenerate, centroid falls back to the average point.
    """
    if len(poly) < 3:
        if not poly:
            return (0.0, (0.0, 0.0))
        ax = sum(p[0] for p in poly) / len(poly)
        ay = sum(p[1] for p in poly) / len(poly)
        return (0.0, (ax, ay))

    a2 = 0.0
    cx6 = 0.0
    cy6 = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        cross = x0 * y1 - x1 * y0
        a2 += cross
        cx6 += (x0 + x1) * cross
        cy6 += (y0 + y1) * cross

    if abs(a2) < 1e-9:
        ax = sum(p[0] for p in poly) / len(poly)
        ay = sum(p[1] for p in poly) / len(poly)
        return (0.0, (ax, ay))

    area = abs(a2) / 2.0
    cx = cx6 / (3.0 * a2)
    cy = cy6 / (3.0 * a2)
    return (area, (cx, cy))

def format_room_label(
    *,
    mode: RoomLabelMode,
    index_1based: int,
    story: Optional[int],
    floor_identifier: str,
    prefix: str,
) -> str:
    if mode == "index":
        return f"{prefix}{index_1based}"
    if mode == "story":
        return f"{prefix}{story if story is not None else '?'}"
    if mode == "id":
        return f"{prefix}{floor_identifier[:8] if floor_identifier else '?'}"
    if mode == "index-id":
        return f"{prefix}{index_1based} ({floor_identifier[:8] if floor_identifier else '?'})"
    # story-id
    return f"{prefix}{story if story is not None else '?'} ({floor_identifier[:8] if floor_identifier else '?'})"


def point_in_polygon(point: Vec2, polygon: Sequence[Vec2]) -> bool:
    """
    Ray casting test. Works for simple polygons; good enough for RoomPlan floor outlines.
    Points on edges are treated as inside.
    """
    x, y = point
    inside = False
    n = len(polygon)
    if n < 3:
        return False

    for i in range(n):
        x0, y0 = polygon[i]
        x1, y1 = polygon[(i + 1) % n]

        # Check if point is on segment (within epsilon)
        dx = x1 - x0
        dy = y1 - y0
        if abs(dx) > 1e-12 or abs(dy) > 1e-12:
            t = ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)
            if 0.0 <= t <= 1.0:
                px = x0 + t * dx
                py = y0 + t * dy
                if (x - px) ** 2 + (y - py) ** 2 < 1e-10:
                    return True

        # Ray crossing (robust to horizontal edges; no epsilon division)
        #
        # Only consider edges that cross the horizontal ray at y.
        # If y0 == y1, the edge is horizontal and never "crosses" (it is handled by the on-segment test above).
        if (y0 > y) != (y1 > y):
            denom = (y1 - y0)
            if abs(denom) < 1e-12:
                continue
            x_intersect = x0 + (y - y0) * (x1 - x0) / denom
            if x < x_intersect:
                inside = not inside
    return inside


def dist2(a: Vec2, b: Vec2) -> float:
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    return dx * dx + dy * dy


def extract_floor_outlines_2d(data: dict, apply_reference_origin: bool) -> List[FloorOutline2D]:
    """
    Returns one outline per entry in `data["floors"]`.

    In multi-room captures, RoomPlan may export multiple floors (one per captured space).
    """
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
            # RoomPlan v2 JSON: polygonCorners are [x, y, z] (z is often 0 for floor-local polygon)
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
    """
    Returns list of (id, segment, width_m) for things like walls/doors/windows where dimensions[0] is length/width.
    """
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
    out: List[FloorObject2D] = []
    items = data.get("objects") or []
    if not items:
        return out

    ref_tx = data.get("referenceOriginTransform")
    for item in items:
        item_tx: Mat4 = item["transform"]
        if apply_reference_origin and ref_tx:
            item_tx = mat4_mul(ref_tx, item_tx)

        # center is just the transform applied to origin
        center_world = mat4_transform_point(item_tx, (0.0, 0.0, 0.0))
        center_2d = world_to_floorplan_2d(center_world)

        dims = item.get("dimensions") or [0.0, 0.0, 0.0]
        width_m = float(dims[0] or 0.0)   # x
        depth_m = float(dims[2] or 0.0)   # z
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


def extract_sections_2d(data: dict, apply_reference_origin: bool) -> List[SectionLabel2D]:
    sections = data.get("sections") or []
    if not sections:
        return []

    ref = data.get("referenceOriginTransform")
    out: List[SectionLabel2D] = []
    for sec in sections:
        center = sec.get("center") or [0.0, 0.0, 0.0]
        center3: Vec3 = (float(center[0]), float(center[1]), float(center[2]))
        if apply_reference_origin and ref:
            center3 = mat4_transform_point(ref, center3)

        label = format_section_label(str(sec.get("label") or "room"))
        out.append(
            SectionLabel2D(
                story=sec.get("story"),
                center=world_to_floorplan_2d(center3),
                label=label,
            )
        )
    return out


def pick_section_label_for_floor(outline: Sequence[Vec2], sections: Sequence[SectionLabel2D]) -> Optional[str]:
    """
    Choose one section label for a floor outline:
    - Prefer sections whose centers are inside the polygon.
    - If multiple, pick the closest to the polygon centroid.
    """
    if not outline or not sections:
        return None

    _area, centroid = polygon_area_and_centroid(outline)
    inside = [s for s in sections if point_in_polygon(s.center, outline)]
    candidates = inside if inside else list(sections)
    best = min(candidates, key=lambda s: dist2(s.center, centroid))
    return best.label


def compute_bounds(points: Iterable[Vec2]) -> Optional[Tuple[float, float, float, float]]:
    pts = list(points)
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def to_svg_space(p: Vec2, bounds: Tuple[float, float, float, float], ppm: float, margin_px: float) -> Vec2:
    """
    Map floorplan meters → SVG pixels.
    - Flips Y so "up" in floor plan becomes "up" visually (SVG y grows down).
    """
    min_x, min_y, max_x, max_y = bounds
    x_m, y_m = p
    x_px = (x_m - min_x) * ppm + margin_px
    y_px = (max_y - y_m) * ppm + margin_px
    return (x_px, y_px)


# ----------------------------------------
# Main conversion
# ----------------------------------------


def convert_roomplan_json_to_svg(
    json_path: str,
    svg_path: str,
    pixels_per_meter: float = 120.0,
    margin_px: float = 40.0,
    apply_reference_origin: bool = True,
    draw_room_labels: bool = True,
    draw_area_text: bool = True,
    room_label_mode: RoomLabelMode = "index",
    room_label_prefix: str = "Room ",
    room_label_source: RoomLabelSource = "auto",
    draw_section_labels: bool = True,
    section_label_style: SectionLabelStyle = "normal",
    draw_objects: bool = True,
    draw_object_labels: bool = True,
) -> None:
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Outlines are the most important "shape" signal.
    outlines = extract_floor_outlines_2d(data, apply_reference_origin=apply_reference_origin)

    # Walls/doors/windows (linear elements)
    walls = extract_linear_elements_2d(data, "walls", apply_reference_origin=apply_reference_origin)
    doors = extract_linear_elements_2d(data, "doors", apply_reference_origin=apply_reference_origin)
    windows = extract_linear_elements_2d(data, "windows", apply_reference_origin=apply_reference_origin)
    objects = extract_objects_2d(data, apply_reference_origin=apply_reference_origin) if draw_objects else []
    sections = extract_sections_2d(data, apply_reference_origin=apply_reference_origin)

    all_points: List[Vec2] = []
    for outline in outlines:
        all_points.extend(outline.outline)
    for _id, seg, _w in walls + doors + windows:
        all_points.append(seg.a)
        all_points.append(seg.b)
    for obj in objects:
        all_points.append(obj.center)
    if (draw_section_labels or (room_label_source != "generated" and draw_room_labels)) and sections:
        for s in sections:
            all_points.append(s.center)

    bounds = compute_bounds(all_points)
    if not bounds:
        raise SystemExit("No drawable geometry found (missing floors/polygonCorners?)")

    min_x, min_y, max_x, max_y = bounds
    view_w = (max_x - min_x) * pixels_per_meter + margin_px * 2
    view_h = (max_y - min_y) * pixels_per_meter + margin_px * 2

    svg: List[str] = []
    svg.append(svg_header(view_w, view_h))
    svg.append('<rect x="0" y="0" width="100%" height="100%" fill="white" />')

    # Draw outlines (thin) + optional room labels/area
    for idx, floor in enumerate(outlines):
        outline = floor.outline
        if not outline:
            continue
        outline_px = [to_svg_space(p, bounds, pixels_per_meter, margin_px) for p in outline]
        svg.append(svg_polyline(outline_px, stroke="#888", width=2.0, fill="none", close=True))

        if draw_room_labels or draw_area_text:
            area_m2, centroid_m = polygon_area_and_centroid(outline)
            cx, cy = to_svg_space(centroid_m, bounds, pixels_per_meter, margin_px)

            # Label source resolution
            use_sections = False
            if room_label_source == "sections":
                use_sections = True
            elif room_label_source == "auto":
                use_sections = len(sections) > 0

            resolved_label: Optional[str] = None
            if use_sections and sections:
                resolved_label = pick_section_label_for_floor(outline, sections)

            if not resolved_label:
                resolved_label = format_room_label(
                    mode=room_label_mode,
                    index_1based=idx + 1,
                    story=floor.story,
                    floor_identifier=floor.identifier,
                    prefix=room_label_prefix,
                )

            if draw_room_labels:
                svg.append(
                    svg_text_anchored(
                        cx,
                        cy - (10 if draw_area_text else 0),
                        resolved_label,
                        size=16,
                        fill="#333",
                        anchor="middle",
                        baseline="alphabetic" if draw_area_text else "middle",
                    )
                )
            if draw_area_text:
                svg.append(svg_text_anchored(cx, cy + 10, f"{area_m2:.1f} m²", size=14, fill="#2E8B57"))

    # Draw walls (thick)
    wall_px_width = max(2.0, pixels_per_meter * 0.06)  # ~6cm line
    for _id, seg, _w in walls:
        a = to_svg_space(seg.a, bounds, pixels_per_meter, margin_px)
        b = to_svg_space(seg.b, bounds, pixels_per_meter, margin_px)
        svg.append(svg_line(a[0], a[1], b[0], b[1], stroke="#111", width=wall_px_width))

    # Draw windows + doors (overlay)
    for _id, seg, _w in windows:
        a = to_svg_space(seg.a, bounds, pixels_per_meter, margin_px)
        b = to_svg_space(seg.b, bounds, pixels_per_meter, margin_px)
        svg.append(svg_line(a[0], a[1], b[0], b[1], stroke="#00AEEF", width=max(2.0, wall_px_width * 0.7)))

    for _id, seg, _w in doors:
        a = to_svg_space(seg.a, bounds, pixels_per_meter, margin_px)
        b = to_svg_space(seg.b, bounds, pixels_per_meter, margin_px)
        svg.append(svg_line(a[0], a[1], b[0], b[1], stroke="#2E8B57", width=max(2.0, wall_px_width * 0.6), opacity=0.9))

    # Draw furniture / objects
    if draw_objects:
        for obj in objects:
            cx, cy = to_svg_space(obj.center, bounds, pixels_per_meter, margin_px)
            w = max(4.0, obj.width_m * pixels_per_meter)
            h = max(4.0, obj.depth_m * pixels_per_meter)
            # We flip Y in to_svg_space, which flips rotation direction.
            angle_deg = -obj.angle_rad * 180.0 / math.pi

            svg.append(
                svg_rect_rotated(
                    cx=cx,
                    cy=cy,
                    w=w,
                    h=h,
                    angle_deg=angle_deg,
                    fill="#FF6B6B",
                    fill_opacity=0.25,
                    stroke="#FF6B6B",
                    stroke_width=1.0,
                    rx=4.0,
                )
            )
            if draw_object_labels:
                svg.append(svg_text_anchored(cx, cy, obj.category, size=10, fill="#AA2E2E"))

    # Draw all section labels (optional overlay)
    if draw_section_labels and sections:
        if section_label_style == "small":
            size = 11
            color = "#777"
        else:
            size = 13
            color = "#666"
        for s in sections:
            sx, sy = to_svg_space(s.center, bounds, pixels_per_meter, margin_px)
            svg.append(svg_text_anchored(sx, sy, s.label, size=size, fill=color))

    # Small label for sanity checks
    svg.append(
        svg_text(
            12,
            20,
            f"source: {json_path.split('/')[-1]}  ppm={pixels_per_meter:g}  refOrigin={'on' if apply_reference_origin else 'off'}",
        )
    )

    svg.append(svg_footer())

    with open(svg_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))

    print("SVG exported to:", svg_path)


def main() -> None:
    ap = argparse.ArgumentParser(description="Convert RoomPlan Room.json to a simple 2D floor plan SVG.")
    ap.add_argument(
        "-i",
        "--input",
        default="Export/Room.json",
        help="Path to RoomPlan Room.json",
    )
    ap.add_argument(
        "-o",
        "--output",
        default="Export/floorplan.svg",
        help="Output SVG path",
    )
    ap.add_argument("--ppm", type=float, default=120.0, help="Pixels per meter (scale).")
    ap.add_argument("--margin", type=float, default=40.0, help="Margin/padding in pixels.")
    ap.add_argument(
        "--no-reference-origin",
        action="store_true",
        help="Do NOT apply `referenceOriginTransform` (just use per-element transforms).",
    )
    ap.add_argument("--no-room-labels", action="store_true", help="Disable room labels.")
    ap.add_argument("--no-area-text", action="store_true", help="Disable room area text.")
    ap.add_argument(
        "--room-label-mode",
        choices=["index", "story", "id", "index-id", "story-id"],
        default="index",
        help="How to label rooms when using generated labels (default: index).",
    )
    ap.add_argument(
        "--room-label-prefix",
        default="Room ",
        help='Prefix for generated room labels (default: "Room ").',
    )
    ap.add_argument(
        "--room-label-source",
        choices=["auto", "sections", "generated"],
        default="auto",
        help='Room label source: "auto" uses sections if present, otherwise generated (default: auto).',
    )

    section_labels_group = ap.add_mutually_exclusive_group()
    section_labels_group.set_defaults(draw_section_labels=True)
    section_labels_group.add_argument(
        "--draw-section-labels",
        dest="draw_section_labels",
        action="store_true",
        help="Enable drawing all RoomPlan section labels at their centers (default).",
    )
    section_labels_group.add_argument(
        "--no-draw-section-labels",
        dest="draw_section_labels",
        action="store_false",
        help="Disable drawing all RoomPlan section labels.",
    )
    ap.add_argument(
        "--section-label-style",
        choices=["small", "normal"],
        default="normal",
        help="Style for section label overlay (default: normal).",
    )

    ap.add_argument("--no-objects", action="store_true", help="Disable drawing objects/furniture.")
    ap.add_argument("--no-object-labels", action="store_true", help="Disable text labels on objects/furniture.")
    args = ap.parse_args()

    convert_roomplan_json_to_svg(
        json_path=args.input,
        svg_path=args.output,
        pixels_per_meter=args.ppm,
        margin_px=args.margin,
        apply_reference_origin=not args.no_reference_origin,
        draw_room_labels=not args.no_room_labels,
        draw_area_text=not args.no_area_text,
        room_label_mode=args.room_label_mode,
        room_label_prefix=args.room_label_prefix,
        room_label_source=args.room_label_source,
        draw_section_labels=args.draw_section_labels,
        section_label_style=args.section_label_style,
        draw_objects=not args.no_objects,
        draw_object_labels=not args.no_object_labels,
    )


if __name__ == "__main__":
    main()


