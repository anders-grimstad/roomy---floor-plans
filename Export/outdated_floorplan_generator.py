#!/usr/bin/env python3
"""
RoomPlan JSON to SVG Floor Plan Converter

Converts Apple RoomPlan SDK JSON output to a 2D SVG floor plan.
Supports: floors, walls, doors, windows, sections (room labels), and objects.

Usage:
    python floorplan_generator.py Room.json output.svg
    python floorplan_generator.py Room.json output.svg --scale 100 --show-objects
"""

import json
import argparse
import numpy as np
from dataclasses import dataclass
from typing import List, Tuple, Dict, Optional, Any

# ============================================================
# Data Classes
# ============================================================

@dataclass
class Point2D:
    x: float
    y: float
    
    def __iter__(self):
        return iter((self.x, self.y))
    
    def __hash__(self):
        return hash((round(self.x, 6), round(self.y, 6)))

@dataclass
class BoundingBox:
    min_x: float
    min_y: float
    max_x: float
    max_y: float
    
    @property
    def width(self) -> float:
        return self.max_x - self.min_x
    
    @property
    def height(self) -> float:
        return self.max_y - self.min_y
    
    @property
    def center(self) -> Point2D:
        return Point2D(
            (self.min_x + self.max_x) / 2,
            (self.min_y + self.max_y) / 2
        )

# ============================================================
# Configuration
# ============================================================

class FloorPlanStyle:
    """Styling configuration for the floor plan SVG"""
    
    # Canvas
    padding: float = 60
    background_color: str = "#ffffff"
    
    # Floor
    floor_stroke: str = "#e0e0e0"
    floor_fill: str = "#fafafa"
    floor_stroke_width: float = 2
    
    # Walls
    wall_stroke: str = "#2c3e50"
    wall_stroke_width: float = 6
    wall_cap: str = "round"
    
    # Doors
    door_stroke: str = "#e74c3c"
    door_stroke_width: float = 2
    door_arc_stroke: str = "#e74c3c"
    door_swing_opacity: float = 0.4
    
    # Windows
    window_stroke: str = "#3498db"
    window_stroke_width: float = 4
    window_gap_color: str = "#ffffff"
    
    # Room labels
    label_font: str = "Arial, sans-serif"
    label_font_size: float = 14
    label_color: str = "#7f8c8d"
    
    # Objects/Furniture
    object_stroke: str = "#95a5a6"
    object_fill: str = "#ecf0f1"
    object_stroke_width: float = 1
    object_opacity: float = 0.7
    
    # Dimensions
    show_dimensions: bool = True
    dimension_color: str = "#bdc3c7"
    dimension_font_size: float = 10


# ============================================================
# SVG Builder
# ============================================================

class SVGBuilder:
    """Builds SVG elements for the floor plan"""
    
    def __init__(self, width: float, height: float, style: FloorPlanStyle):
        self.width = width
        self.height = height
        self.style = style
        self.elements: List[str] = []
        self.defs: List[str] = []
        
    def add_defs(self):
        """Add SVG definitions (markers, patterns, etc.)"""
        self.defs.append('''
        <defs>
            <marker id="arrowhead" markerWidth="10" markerHeight="7" 
                    refX="9" refY="3.5" orient="auto">
                <polygon points="0 0, 10 3.5, 0 7" fill="#bdc3c7"/>
            </marker>
        </defs>
        ''')
    
    def header(self) -> str:
        return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     width="{self.width:.2f}" height="{self.height:.2f}"
     viewBox="0 0 {self.width:.2f} {self.height:.2f}">
<rect width="100%" height="100%" fill="{self.style.background_color}"/>
{''.join(self.defs)}
'''
    
    def footer(self) -> str:
        return "</svg>"
    
    def polygon(self, points: List[Point2D], stroke: str, fill: str, 
                stroke_width: float, closed: bool = True) -> str:
        pts = " ".join([f"{p.x:.2f},{p.y:.2f}" for p in points])
        tag = "polygon" if closed else "polyline"
        return f'<{tag} points="{pts}" stroke="{stroke}" fill="{fill}" stroke-width="{stroke_width}"/>'
    
    def line(self, p1: Point2D, p2: Point2D, stroke: str, 
             stroke_width: float, stroke_linecap: str = "round",
             stroke_dasharray: str = None) -> str:
        dash = f' stroke-dasharray="{stroke_dasharray}"' if stroke_dasharray else ''
        return f'<line x1="{p1.x:.2f}" y1="{p1.y:.2f}" x2="{p2.x:.2f}" y2="{p2.y:.2f}" ' \
               f'stroke="{stroke}" stroke-width="{stroke_width}" stroke-linecap="{stroke_linecap}"{dash}/>'
    
    def rect(self, x: float, y: float, width: float, height: float, 
             angle: float = 0, stroke: str = "black", fill: str = "none",
             stroke_width: float = 1, opacity: float = 1.0) -> str:
        cx, cy = x + width/2, y + height/2
        transform = f' transform="rotate({angle:.2f} {cx:.2f} {cy:.2f})"' if angle != 0 else ''
        return f'<rect x="{x:.2f}" y="{y:.2f}" width="{width:.2f}" height="{height:.2f}" ' \
               f'stroke="{stroke}" fill="{fill}" stroke-width="{stroke_width}" ' \
               f'opacity="{opacity}"{transform}/>'
    
    def arc(self, cx: float, cy: float, r: float, start_angle: float, 
            end_angle: float, stroke: str, stroke_width: float, fill: str = "none") -> str:
        """Draw an arc (for door swings)"""
        import math
        start_rad = math.radians(start_angle)
        end_rad = math.radians(end_angle)
        
        x1 = cx + r * math.cos(start_rad)
        y1 = cy + r * math.sin(start_rad)
        x2 = cx + r * math.cos(end_rad)
        y2 = cy + r * math.sin(end_rad)
        
        large_arc = 1 if abs(end_angle - start_angle) > 180 else 0
        sweep = 1 if end_angle > start_angle else 0
        
        return f'<path d="M {x1:.2f} {y1:.2f} A {r:.2f} {r:.2f} 0 {large_arc} {sweep} {x2:.2f} {y2:.2f}" ' \
               f'stroke="{stroke}" stroke-width="{stroke_width}" fill="{fill}"/>'
    
    def text(self, x: float, y: float, content: str, font_size: float,
             color: str, font_family: str, anchor: str = "middle") -> str:
        return f'<text x="{x:.2f}" y="{y:.2f}" font-family="{font_family}" ' \
               f'font-size="{font_size}" fill="{color}" text-anchor="{anchor}" ' \
               f'dominant-baseline="middle">{content}</text>'
    
    def group(self, elements: List[str], id: str = None, 
              opacity: float = None) -> str:
        attrs = []
        if id:
            attrs.append(f'id="{id}"')
        if opacity is not None:
            attrs.append(f'opacity="{opacity}"')
        attr_str = " ".join(attrs)
        if attr_str:
            attr_str = " " + attr_str
        return f'<g{attr_str}>\n' + '\n'.join(elements) + '\n</g>'
    
    def comment(self, text: str) -> str:
        return f'<!-- {text} -->'
    
    def build(self) -> str:
        return self.header() + '\n'.join(self.elements) + '\n' + self.footer()


# ============================================================
# Geometry Utilities  
# ============================================================

def parse_transform(transform_array: List[float]) -> np.ndarray:
    """Parse a flat 16-element array into a 4x4 transformation matrix"""
    return np.array(transform_array).reshape((4, 4))

def apply_transform(point: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    """
    Apply a 4x4 transformation matrix to a 3D point.
    Apple's RoomPlan uses row-major matrices with row vector convention: v' = v @ M
    """
    p = np.array([*point[:3], 1.0])
    # Row vector multiplication for Apple's convention
    result = p @ matrix
    return result[:3]

def project_to_2d(point_3d: np.ndarray) -> Point2D:
    """
    Project a 3D point to 2D floor plan coordinates.
    Uses X for horizontal and Z for vertical (top-down view).
    Z is inverted to get proper orientation.
    """
    return Point2D(point_3d[0], -point_3d[2])

def get_rotation_angle(transform: np.ndarray) -> float:
    """Extract the Y-axis rotation angle from a transform matrix (in degrees)"""
    import math
    # For a Y-axis rotation, the rotation angle can be extracted from the matrix
    # rotation around Y: [[cos, 0, sin], [0, 1, 0], [-sin, 0, cos]]
    angle = math.atan2(transform[0, 2], transform[0, 0])
    return math.degrees(angle)

def compute_bounding_box(points: List[Point2D]) -> BoundingBox:
    """Compute the bounding box of a list of 2D points"""
    xs = [p.x for p in points]
    ys = [p.y for p in points]
    return BoundingBox(min(xs), min(ys), max(xs), max(ys))

def compute_element_endpoints(element: Dict, length_axis: int = 0) -> Tuple[np.ndarray, np.ndarray]:
    """
    Compute the local-to-element-space endpoints of a wall/door/window element.
    Elements are centered at origin with length along the specified axis.
    Returns endpoints transformed by the element's own transform only.
    """
    length = element['dimensions'][length_axis]
    half_len = length / 2.0
    
    # Local endpoints (along X axis by default)
    if length_axis == 0:
        p0_local = np.array([-half_len, 0, 0])
        p1_local = np.array([half_len, 0, 0])
    else:
        p0_local = np.array([0, 0, -half_len])
        p1_local = np.array([0, 0, half_len])
    
    transform = parse_transform(element['transform'])
    
    # Apply element transform (row vector convention)
    p0_world = apply_transform(p0_local, transform)
    p1_world = apply_transform(p1_local, transform)
    
    return p0_world, p1_world

def compute_element_rect_corners(element: Dict) -> List[np.ndarray]:
    """
    Compute the 4 corners of a rectangular element in world space.
    Used for objects/furniture.
    """
    dims = element['dimensions']
    w, h, d = dims[0] / 2, dims[1] / 2, dims[2] / 2
    
    # 4 corners at floor level (y=0 in local space)
    corners_local = [
        np.array([-w, 0, -d]),
        np.array([w, 0, -d]),
        np.array([w, 0, d]),
        np.array([-w, 0, d]),
    ]
    
    transform = parse_transform(element['transform'])
    return [apply_transform(c, transform) for c in corners_local]


# ============================================================
# Floor Plan Generator
# ============================================================

class FloorPlanGenerator:
    """Main class for generating SVG floor plans from RoomPlan JSON"""
    
    def __init__(self, data: Dict[str, Any], style: FloorPlanStyle = None,
                 scale: float = 50, show_objects: bool = False,
                 show_labels: bool = True, show_dimensions: bool = False):
        self.data = data
        self.style = style or FloorPlanStyle()
        self.scale = scale  # pixels per meter
        self.show_objects = show_objects
        self.show_labels = show_labels
        self.show_dimensions = show_dimensions
        
        # Parse global transforms
        self.ref_transform = parse_transform(data.get('referenceOriginTransform', 
                                                       np.eye(4).flatten().tolist()))
        
        # Collect all 2D points for bounding box calculation
        self.all_points: List[Point2D] = []
        
        # Processed geometry
        self.floor_polygons: List[List[Point2D]] = []
        self.wall_lines: List[Tuple[Point2D, Point2D, Dict]] = []
        self.door_lines: List[Tuple[Point2D, Point2D, Dict]] = []
        self.window_lines: List[Tuple[Point2D, Point2D, Dict]] = []
        self.room_labels: List[Tuple[Point2D, str]] = []
        self.object_rects: List[Tuple[List[Point2D], Dict]] = []
        
    def process_floors(self):
        """Process floor polygon corners"""
        for floor in self.data.get('floors', []):
            floor_transform = parse_transform(floor['transform'])
            
            polygon = []
            for corner in floor.get('polygonCorners', []):
                # Floor polygon corners are [x, y, z] in floor-local space
                # where x,y form the 2D polygon and z=0 (floor level)
                local = np.array([corner[0], corner[1], corner[2]])
                # Apply floor transform to get world coordinates
                world = apply_transform(local, floor_transform)
                # Project to 2D: (X, -Z) for top-down view
                pt2d = project_to_2d(world)
                polygon.append(pt2d)
                self.all_points.append(pt2d)
            
            if polygon:
                self.floor_polygons.append(polygon)
    
    def process_walls(self):
        """Process wall geometry"""
        for wall in self.data.get('walls', []):
            p0, p1 = compute_element_endpoints(wall)
            
            # Wall endpoints are already in world space after element transform
            pt0 = project_to_2d(p0)
            pt1 = project_to_2d(p1)
            
            self.wall_lines.append((pt0, pt1, wall))
            self.all_points.extend([pt0, pt1])
    
    def process_doors(self):
        """Process door geometry"""
        for door in self.data.get('doors', []):
            p0, p1 = compute_element_endpoints(door)
            
            pt0 = project_to_2d(p0)
            pt1 = project_to_2d(p1)
            
            self.door_lines.append((pt0, pt1, door))
            self.all_points.extend([pt0, pt1])
    
    def process_windows(self):
        """Process window geometry"""
        for window in self.data.get('windows', []):
            p0, p1 = compute_element_endpoints(window)
            
            pt0 = project_to_2d(p0)
            pt1 = project_to_2d(p1)
            
            self.window_lines.append((pt0, pt1, window))
            self.all_points.extend([pt0, pt1])
    
    def process_sections(self):
        """Process room labels from sections"""
        for section in self.data.get('sections', []):
            center = section.get('center', [0, 0, 0])
            # Section centers are already in world space [x, y, z]
            center_3d = np.array(center)
            
            # Project to 2D: (X, -Z) for top-down view
            pt = project_to_2d(center_3d)
            
            label = section.get('label', 'room')
            # Convert camelCase to Title Case
            formatted_label = self._format_label(label)
            
            self.room_labels.append((pt, formatted_label))
            self.all_points.append(pt)  # Include in bounding box calculation
    
    def process_objects(self):
        """Process furniture/objects"""
        if not self.show_objects:
            return
            
        for obj in self.data.get('objects', []):
            corners = compute_element_rect_corners(obj)
            
            # Corners are already in world space, just project to 2D
            projected = []
            for corner in corners:
                pt = project_to_2d(corner)
                projected.append(pt)
                self.all_points.append(pt)
            
            self.object_rects.append((projected, obj))
    
    def _format_label(self, label: str) -> str:
        """Format camelCase label to Title Case"""
        import re
        # Insert space before capitals
        spaced = re.sub(r'([a-z])([A-Z])', r'\1 \2', label)
        return spaced.title()
    
    def normalize_coordinates(self):
        """Normalize all coordinates to fit in the SVG canvas"""
        if not self.all_points:
            return 100, 100  # Default size
        
        bbox = compute_bounding_box(self.all_points)
        padding = self.style.padding
        
        # Calculate canvas size
        width = bbox.width * self.scale + padding * 2
        height = bbox.height * self.scale + padding * 2
        
        def transform_point(p: Point2D) -> Point2D:
            return Point2D(
                (p.x - bbox.min_x) * self.scale + padding,
                (p.y - bbox.min_y) * self.scale + padding
            )
        
        # Transform all geometry
        self.floor_polygons = [
            [transform_point(p) for p in poly] 
            for poly in self.floor_polygons
        ]
        
        self.wall_lines = [
            (transform_point(p0), transform_point(p1), data)
            for p0, p1, data in self.wall_lines
        ]
        
        self.door_lines = [
            (transform_point(p0), transform_point(p1), data)
            for p0, p1, data in self.door_lines
        ]
        
        self.window_lines = [
            (transform_point(p0), transform_point(p1), data)
            for p0, p1, data in self.window_lines
        ]
        
        self.room_labels = [
            (transform_point(p), label)
            for p, label in self.room_labels
        ]
        
        self.object_rects = [
            ([transform_point(p) for p in corners], data)
            for corners, data in self.object_rects
        ]
        
        return width, height
    
    def generate(self) -> str:
        """Generate the complete SVG floor plan"""
        
        # Process all geometry
        self.process_floors()
        self.process_walls()
        self.process_doors()
        self.process_windows()
        self.process_sections()
        self.process_objects()
        
        # Normalize to canvas coordinates
        width, height = self.normalize_coordinates()
        
        # Build SVG
        svg = SVGBuilder(width, height, self.style)
        svg.add_defs()
        
        # Layer 1: Floor fill
        svg.elements.append(svg.comment("Floor"))
        for poly in self.floor_polygons:
            svg.elements.append(svg.polygon(
                poly, 
                self.style.floor_stroke,
                self.style.floor_fill,
                self.style.floor_stroke_width,
                closed=True
            ))
        
        # Layer 2: Objects/Furniture (below walls)
        if self.object_rects:
            svg.elements.append(svg.comment("Objects/Furniture"))
            obj_elements = []
            for corners, obj_data in self.object_rects:
                cat = list(obj_data.get('category', {}).keys())[0] if obj_data.get('category') else 'object'
                obj_elements.append(svg.polygon(
                    corners,
                    self.style.object_stroke,
                    self.style.object_fill,
                    self.style.object_stroke_width,
                    closed=True
                ))
            svg.elements.append(svg.group(obj_elements, id="objects", 
                                          opacity=self.style.object_opacity))
        
        # Layer 3: Walls
        svg.elements.append(svg.comment("Walls"))
        for p0, p1, wall_data in self.wall_lines:
            svg.elements.append(svg.line(
                p0, p1,
                self.style.wall_stroke,
                self.style.wall_stroke_width,
                self.style.wall_cap
            ))
        
        # Layer 4: Doors (draw gap + swing arc)
        svg.elements.append(svg.comment("Doors"))
        for p0, p1, door_data in self.door_lines:
            # Draw door gap (white line to "erase" wall)
            svg.elements.append(svg.line(
                p0, p1,
                self.style.background_color,
                self.style.wall_stroke_width + 2
            ))
            
            # Draw door line
            svg.elements.append(svg.line(
                p0, p1,
                self.style.door_stroke,
                self.style.door_stroke_width
            ))
            
            # Draw door swing arc
            import math
            dx = p1.x - p0.x
            dy = p1.y - p0.y
            door_length = math.sqrt(dx*dx + dy*dy)
            door_angle = math.degrees(math.atan2(dy, dx))
            
            # Arc from door position
            svg.elements.append(svg.arc(
                p0.x, p0.y, door_length,
                door_angle, door_angle + 90,
                self.style.door_arc_stroke,
                self.style.door_stroke_width,
                fill="none"
            ))
        
        # Layer 5: Windows
        svg.elements.append(svg.comment("Windows"))
        for p0, p1, window_data in self.window_lines:
            # Draw window gap (white line)
            svg.elements.append(svg.line(
                p0, p1,
                self.style.background_color,
                self.style.wall_stroke_width + 2
            ))
            
            # Draw window (double line effect)
            svg.elements.append(svg.line(
                p0, p1,
                self.style.window_stroke,
                self.style.window_stroke_width
            ))
            
            # Inner white line for window pane effect
            svg.elements.append(svg.line(
                p0, p1,
                self.style.background_color,
                self.style.window_stroke_width - 2
            ))
        
        # Layer 6: Room labels
        if self.show_labels and self.room_labels:
            svg.elements.append(svg.comment("Room Labels"))
            for pt, label in self.room_labels:
                svg.elements.append(svg.text(
                    pt.x, pt.y, label,
                    self.style.label_font_size,
                    self.style.label_color,
                    self.style.label_font
                ))
        
        return svg.build()


# ============================================================
# Main
# ============================================================

def convert_roomplan_to_svg(json_path: str, svg_path: str, 
                            scale: float = 50,
                            show_objects: bool = False,
                            show_labels: bool = True,
                            show_dimensions: bool = False):
    """
    Convert a RoomPlan JSON file to an SVG floor plan.
    
    Args:
        json_path: Path to the RoomPlan JSON file
        svg_path: Output path for the SVG file
        scale: Pixels per meter (default: 50)
        show_objects: Whether to show furniture/objects
        show_labels: Whether to show room labels
        show_dimensions: Whether to show dimension annotations
    """
    with open(json_path, 'r') as f:
        data = json.load(f)
    
    generator = FloorPlanGenerator(
        data,
        scale=scale,
        show_objects=show_objects,
        show_labels=show_labels,
        show_dimensions=show_dimensions
    )
    
    svg_content = generator.generate()
    
    with open(svg_path, 'w') as f:
        f.write(svg_content)
    
    print(f"✓ Floor plan exported to: {svg_path}")
    print(f"  Scale: {scale} pixels/meter")
    print(f"  Objects: {'shown' if show_objects else 'hidden'}")
    print(f"  Labels: {'shown' if show_labels else 'hidden'}")


def main():
    parser = argparse.ArgumentParser(
        description='Convert RoomPlan JSON to SVG floor plan'
    )
    parser.add_argument('input', help='Input RoomPlan JSON file')
    parser.add_argument('output', help='Output SVG file path')
    parser.add_argument('--scale', type=float, default=50,
                        help='Scale in pixels per meter (default: 50)')
    parser.add_argument('--show-objects', action='store_true',
                        help='Show furniture and objects')
    parser.add_argument('--no-labels', action='store_true',
                        help='Hide room labels')
    parser.add_argument('--show-dimensions', action='store_true',
                        help='Show dimension annotations')
    
    args = parser.parse_args()
    
    convert_roomplan_to_svg(
        args.input,
        args.output,
        scale=args.scale,
        show_objects=args.show_objects,
        show_labels=not args.no_labels,
        show_dimensions=args.show_dimensions
    )


if __name__ == '__main__':
    main()

