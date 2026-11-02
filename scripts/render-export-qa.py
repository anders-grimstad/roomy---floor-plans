#!/usr/bin/env python3
"""Render the actual export view on macOS with UIKit color/image adapters.

This exercises the production drawing/export bodies, not the iPhone UI or a scan.
The temporary adapters map UIKit semantic colors/images to AppKit equivalents.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parent.parent
drawing = (root / "RoomPlanExampleApp/FloorPlanView.swift").read_text().split("// MARK: - Floor Plan View")[0]
drawing = drawing.replace("import RoomPlan\n", "").replace("import UIKit", "import AppKit")
for ui, mac in {
    "systemBackground": "windowBackgroundColor", "secondarySystemBackground": "controlBackgroundColor",
    "label": "labelColor", "separator": "separatorColor", "quaternarySystemFill": "quaternaryLabelColor",
    "tertiaryLabel": "tertiaryLabelColor", "secondaryLabel": "secondaryLabelColor",
}.items():
    drawing = drawing.replace(f"Color(uiColor: .{ui})", f"Color(nsColor: .{mac})")
preview = (root / "RoomPlanExampleApp/FloorPlanAnnotations.swift").read_text().split("\n@available(iOS 27.0", 1)[0]
preview = preview.replace("import UIKit", "import AppKit").replace("UIImage", "NSImage").replace("Image(uiImage:", "Image(nsImage:")
export = (root / "RoomPlanExampleApp/FloorPlanScreen.swift").read_text().split("struct FloorPlanExportView: View", 1)[1]
source = drawing + "\n" + preview + "\nstruct FloorPlanExportView: View" + export

with tempfile.TemporaryDirectory(prefix="roomy-export-qa-") as work:
    work = Path(work)
    (work / "ExportViews.swift").write_text(source)
    binary = work / "render"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(work / "modules"),
        str(root / "RoomPlanExampleApp/FloorPlanGeometry.swift"),
        str(root / "RoomPlanExampleApp/ScanHeading.swift"),
        str(root / "RoomPlanExampleApp/FloorPlanExportData.swift"),
        str(root / "RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift"),
        str(root / "RoomPlanExampleApp/FloorPlanAnnotationRendering.swift"),
        str(work / "ExportViews.swift"), str(root / ("tests/AnnotationEdgeRendering.swift" if "--edge-test" in sys.argv else "tests/ExportRendering.swift")), "-o", str(binary),
    ], check=True, cwd=root)
    subprocess.run([str(binary)], check=True, cwd=root)
