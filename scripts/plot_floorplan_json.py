#!/usr/bin/env python3
"""
Render Roomy FloorPlanExportData JSON on macOS for deterministic orientation checks.

By default this renders two panels using app toggle logic:
- app_raw (desiredNorthUp = false)
- app_north_up (desiredNorthUp = true)

You can render more formulas with:
--modes raw,heading_only,yaw_only,heading_minus_yaw,heading_plus_yaw
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


Point = Tuple[float, float]


def parse_bool(value: str) -> bool:
    lowered = value.strip().lower()
    if lowered in {"1", "true", "yes", "y", "on"}:
        return True
    if lowered in {"0", "false", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError("Expected true|false")


def normalize_degrees(degrees: float) -> float:
    value = math.fmod(degrees, 360.0)
    return value + 360.0 if value < 0 else value


def normalize_signed_degrees(degrees: float) -> float:
    # Keep range [-180, 180) for easier debugging.
    return (degrees + 180.0) % 360.0 - 180.0


def rotate_point(point: Point, radians: float) -> Point:
    x, y = point
    cos_a = math.cos(radians)
    sin_a = math.sin(radians)
    return (x * cos_a - y * sin_a, x * sin_a + y * cos_a)


@dataclass
class RenderLayer:
    outlines: List[List[Point]]
    walls: List[Tuple[Point, Point]]
    windows: List[Tuple[Point, Point]]
    doors: List[Tuple[Point, Point]]


@dataclass
class OrientationMeta:
    source_is_north_up: bool
    heading: Optional[float]
    camera_yaw: Optional[float]
    room_to_north_yaw: Optional[float]


@dataclass
class ModeResult:
    mode: str
    title: str
    math_rotation_degrees: Optional[float]
    detail: str


MODE_HELP: Dict[str, str] = {
    "app_raw": "Mimic app toggle to raw (desiredNorthUp=false).",
    "app_north_up": "Mimic app toggle to north-up (desiredNorthUp=true).",
    "app_north_up_plus_180": "App north-up formula with additional +180 delta.",
    "raw": "No rotation.",
    "room_to_north": "Apply roomToNorthYaw directly.",
    "room_to_north_plus_180": "Apply roomToNorthYaw + 180.",
    "neg_room_to_north": "Apply negative roomToNorthYaw.",
    "heading_only": "Apply headingDegrees only.",
    "yaw_only": "Apply calibrationCameraYawDegrees only.",
    "heading_minus_yaw": "Apply headingDegrees - cameraYawDegrees.",
    "heading_minus_yaw_plus_180": "Apply (headingDegrees - cameraYawDegrees) + 180.",
    "heading_plus_yaw": "Apply headingDegrees + cameraYawDegrees.",
    "yaw_minus_heading": "Apply cameraYawDegrees - headingDegrees.",
    "neg_heading_minus_yaw": "Apply negative(headingDegrees - cameraYawDegrees).",
}


def extract_layer(payload: dict) -> RenderLayer:
    outlines = []
    for floor in payload.get("floorOutlines", []):
        raw_outline = floor.get("outline", [])
        points = []
        for item in raw_outline:
            if isinstance(item, Sequence) and len(item) >= 2:
                points.append((float(item[0]), float(item[1])))
        if points:
            outlines.append(points)

    def extract_segments(items: Sequence[dict]) -> List[Tuple[Point, Point]]:
        segments: List[Tuple[Point, Point]] = []
        for item in items:
            start = (float(item["startX"]), float(item["startY"]))
            end = (float(item["endX"]), float(item["endY"]))
            segments.append((start, end))
        return segments

    return RenderLayer(
        outlines=outlines,
        walls=extract_segments(payload.get("walls", [])),
        windows=extract_segments(payload.get("windows", [])),
        doors=extract_segments(payload.get("doors", [])),
    )


def rotate_layer(layer: RenderLayer, math_rotation_degrees: float) -> RenderLayer:
    radians = math.radians(math_rotation_degrees)

    def rotate_segment(segment: Tuple[Point, Point]) -> Tuple[Point, Point]:
        start, end = segment
        return (rotate_point(start, radians), rotate_point(end, radians))

    return RenderLayer(
        outlines=[[rotate_point(point, radians) for point in outline] for outline in layer.outlines],
        walls=[rotate_segment(segment) for segment in layer.walls],
        windows=[rotate_segment(segment) for segment in layer.windows],
        doors=[rotate_segment(segment) for segment in layer.doors],
    )


def axis_bounds(layer: RenderLayer) -> Tuple[float, float, float, float]:
    points: List[Point] = []
    for outline in layer.outlines:
        points.extend(outline)
    for start, end in layer.walls + layer.windows + layer.doors:
        points.append(start)
        points.append(end)

    if not points:
        return (-1.0, 1.0, -1.0, 1.0)

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    pad = 0.6
    return (min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad)


def plot_layer(ax, layer: RenderLayer, title: str) -> None:
    for outline in layer.outlines:
        if len(outline) < 2:
            continue
        xs = [p[0] for p in outline] + [outline[0][0]]
        ys = [p[1] for p in outline] + [outline[0][1]]
        ax.fill(xs, ys, alpha=0.18, color="#a0aec0")
        ax.plot(xs, ys, color="#4a5568", linewidth=1.0, alpha=0.7)

    for start, end in layer.walls:
        ax.plot([start[0], end[0]], [start[1], end[1]], color="black", linewidth=3)

    for start, end in layer.windows:
        ax.plot([start[0], end[0]], [start[1], end[1]], color="#38bdf8", linewidth=2)

    for start, end in layer.doors:
        ax.plot([start[0], end[0]], [start[1], end[1]], color="#16a34a", linewidth=2)

    min_x, max_x, min_y, max_y = axis_bounds(layer)
    ax.set_xlim(min_x, max_x)
    ax.set_ylim(min_y, max_y)
    ax.set_aspect("equal", adjustable="box")
    ax.grid(True, alpha=0.25, linewidth=0.5)
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    ax.set_title(title)


def extract_orientation_meta(payload: dict) -> OrientationMeta:
    scan_heading = payload.get("scanHeading") or {}
    north_alignment = payload.get("northAlignment") or {}

    heading = scan_heading.get("headingDegrees")
    if heading is not None:
        heading = normalize_degrees(float(heading))

    room_to_north_yaw = north_alignment.get("roomToNorthYawDegrees")
    if room_to_north_yaw is not None:
        room_to_north_yaw = normalize_degrees(float(room_to_north_yaw))

    camera_yaw = north_alignment.get("calibrationCameraYawDegrees")
    if camera_yaw is not None:
        camera_yaw = normalize_degrees(float(camera_yaw))
    elif heading is not None and room_to_north_yaw is not None:
        # Fallback when older exports don't include calibrationCameraYawDegrees.
        camera_yaw = normalize_degrees(heading - room_to_north_yaw)

    return OrientationMeta(
        source_is_north_up=bool(payload.get("isNorthUpNormalized") or False),
        heading=heading,
        camera_yaw=camera_yaw,
        room_to_north_yaw=room_to_north_yaw,
    )


def maybe_value(label: str, value: Optional[float]) -> str:
    if value is None:
        return f"{label}=missing"
    return f"{label}={value:.2f}deg"


def compass_delta_to_math_rotation(compass_delta_degrees: float) -> float:
    signed = normalize_signed_degrees(compass_delta_degrees)
    # Compass is clockwise-positive; 2D math rotation is counterclockwise-positive.
    return -signed


def mode_compass_delta(mode: str, meta: OrientationMeta) -> Tuple[Optional[float], str]:
    h = meta.heading
    y = meta.camera_yaw
    r = meta.room_to_north_yaw

    if mode == "raw":
        return 0.0, "delta=0"
    if mode == "app_north_up":
        if r is None:
            return None, "missing roomToNorthYaw"
        if meta.source_is_north_up:
            return 0.0, "source already north-up"
        return r, f"delta=roomToNorthYaw ({r:.2f})"
    if mode == "app_north_up_plus_180":
        if r is None:
            return None, "missing roomToNorthYaw"
        if meta.source_is_north_up:
            return 180.0, "source already north-up; delta=180"
        value = r + 180.0
        return value, f"delta=roomToNorthYaw+180 ({value:.2f})"
    if mode == "app_raw":
        if r is None:
            return None, "missing roomToNorthYaw"
        if not meta.source_is_north_up:
            return 0.0, "source already raw"
        return -r, f"delta=-roomToNorthYaw ({-r:.2f})"
    if mode == "room_to_north":
        if r is None:
            return None, "missing roomToNorthYaw"
        return r, f"delta=roomToNorthYaw ({r:.2f})"
    if mode == "room_to_north_plus_180":
        if r is None:
            return None, "missing roomToNorthYaw"
        value = r + 180.0
        return value, f"delta=roomToNorthYaw+180 ({value:.2f})"
    if mode == "neg_room_to_north":
        if r is None:
            return None, "missing roomToNorthYaw"
        return -r, f"delta=-roomToNorthYaw ({-r:.2f})"
    if mode == "heading_only":
        if h is None:
            return None, "missing headingDegrees"
        return h, f"delta=heading ({h:.2f})"
    if mode == "yaw_only":
        if y is None:
            return None, "missing cameraYaw"
        return y, f"delta=yaw ({y:.2f})"
    if mode == "heading_minus_yaw":
        if h is None or y is None:
            return None, "missing heading or yaw"
        value = h - y
        return value, f"delta=heading-yaw ({value:.2f})"
    if mode == "heading_minus_yaw_plus_180":
        if h is None or y is None:
            return None, "missing heading or yaw"
        value = (h - y) + 180.0
        return value, f"delta=(heading-yaw)+180 ({value:.2f})"
    if mode == "heading_plus_yaw":
        if h is None or y is None:
            return None, "missing heading or yaw"
        value = h + y
        return value, f"delta=heading+yaw ({value:.2f})"
    if mode == "yaw_minus_heading":
        if h is None or y is None:
            return None, "missing heading or yaw"
        value = y - h
        return value, f"delta=yaw-heading ({value:.2f})"
    if mode == "neg_heading_minus_yaw":
        if h is None or y is None:
            return None, "missing heading or yaw"
        value = -(h - y)
        return value, f"delta=-(heading-yaw) ({value:.2f})"

    return None, f"unknown mode {mode}"


def build_mode_result(mode: str, meta: OrientationMeta) -> ModeResult:
    compass_delta, detail = mode_compass_delta(mode, meta)
    if compass_delta is None:
        return ModeResult(
            mode=mode,
            title=mode,
            math_rotation_degrees=None,
            detail=detail,
        )

    math_rotation = compass_delta_to_math_rotation(compass_delta)
    title = f"{mode}\nmathRot={math_rotation:.2f}deg"
    return ModeResult(mode=mode, title=title, math_rotation_degrees=math_rotation, detail=detail)


def parse_modes(value: str) -> List[str]:
    modes = [item.strip() for item in value.split(",") if item.strip()]
    if not modes:
        raise argparse.ArgumentTypeError("Expected comma-separated mode names")
    return modes


def main() -> int:
    parser = argparse.ArgumentParser(description="Plot Roomy FloorPlanExportData JSON.")
    parser.add_argument("json_path", type=pathlib.Path, nargs="?", help="Path to floorplan JSON export")
    parser.add_argument(
        "--force-north-up",
        type=parse_bool,
        default=None,
        help="Render a single mode. true => north_up, false => raw",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("floorplan_plot.png"),
        help="Output PNG path",
    )
    parser.add_argument(
        "--modes",
        type=parse_modes,
        default=None,
        help="Comma-separated modes. Run --list-modes to see available values.",
    )
    parser.add_argument("--list-modes", action="store_true", help="Print all mode names and exit.")
    parser.add_argument("--show", action="store_true", help="Show the plot window")
    args = parser.parse_args()

    if args.list_modes:
        print("Available modes:")
        for key, description in MODE_HELP.items():
            print(f"- {key}: {description}")
        return 0

    if args.json_path is None:
        parser.error("json_path is required unless --list-modes is used")

    try:
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover - environment dependent
        print("matplotlib is required. Install with: python3 -m pip install matplotlib", file=sys.stderr)
        print(f"Import error: {exc}", file=sys.stderr)
        return 2

    payload = json.loads(args.json_path.read_text(encoding="utf-8"))
    base_layer = extract_layer(payload)
    meta = extract_orientation_meta(payload)

    if args.modes is not None:
        selected_modes = args.modes
    else:
        if args.force_north_up is None:
            selected_modes = ["app_raw", "app_north_up"]
        else:
            selected_modes = ["app_north_up" if args.force_north_up else "app_raw"]

    unknown = [mode for mode in selected_modes if mode not in MODE_HELP]
    if unknown:
        print(f"Unknown mode(s): {', '.join(unknown)}", file=sys.stderr)
        print("Run with --list-modes to see supported modes.", file=sys.stderr)
        return 2

    mode_results = [build_mode_result(mode, meta) for mode in selected_modes]

    fig, axes = plt.subplots(1, len(mode_results), figsize=(6 * len(mode_results), 7))
    if len(mode_results) == 1:
        axes = [axes]

    for axis, mode_result in zip(axes, mode_results):
        if mode_result.math_rotation_degrees is None:
            axis.set_title(mode_result.title)
            axis.text(
                0.5,
                0.5,
                f"Unavailable\n{mode_result.detail}",
                ha="center",
                va="center",
                transform=axis.transAxes,
            )
            axis.set_axis_off()
            continue

        layer = rotate_layer(base_layer, mode_result.math_rotation_degrees)
        plot_layer(axis, layer, mode_result.title)
        axis.text(
            0.5,
            -0.1,
            mode_result.detail,
            transform=axis.transAxes,
            ha="center",
            va="top",
            fontsize=9,
        )

    heading_value = meta.heading
    yaw_value = meta.camera_yaw
    room_to_north = meta.room_to_north_yaw
    fig.suptitle(
        (
            f"FloorPlan: {args.json_path.name} | "
            f"{maybe_value('heading', heading_value)} | "
            f"{maybe_value('cameraYaw', yaw_value)} | "
            f"{maybe_value('roomToNorthYaw', room_to_north)} | "
            f"sourceIsNorthUp={meta.source_is_north_up}"
        ),
        fontsize=10,
    )
    fig.tight_layout()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=170)
    print(f"Wrote {args.output}")

    if args.show:
        plt.show()
    else:
        plt.close(fig)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
