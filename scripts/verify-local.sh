#!/bin/bash
# Native macOS checks of shared production data/geometry code; no iOS simulator required.
set -euo pipefail
cd "$(dirname "$0")/.."
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/roomy-verification.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

xcrun swiftc -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/FloorPlanGeometry.swift RoomPlanExampleApp/ScanHeading.swift \
  RoomPlanExampleApp/FloorPlanExportData.swift RoomPlanExampleApp/SVGExporter.swift \
  tests/ScanBaseline.swift -o "$verification_dir/scan-baseline"
"$verification_dir/scan-baseline"

xcrun swiftc -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift tests/AnnotationTests.swift \
  -o "$verification_dir/annotations"
"$verification_dir/annotations"

xcrun swiftc -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/RoomPhotoMetadata.swift tests/PhotoMetadataTests.swift \
  -o "$verification_dir/photo-metadata"
"$verification_dir/photo-metadata"

# Keep the store body unchanged; adapt only UIKit's image type/PNG encoder for macOS.
python3 - "$verification_dir/NativeSavedScansStore.swift" <<'PY'
import sys
from pathlib import Path
source = Path("RoomPlanExampleApp/SavedScansStore.swift").read_text()
adapter = """import AppKit
typealias UIImage = NSImage
extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
"""
Path(sys.argv[1]).write_text(source.replace("import UIKit", adapter))
PY
xcrun swiftc -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/FloorPlanGeometry.swift RoomPlanExampleApp/ScanHeading.swift \
  RoomPlanExampleApp/FloorPlanExportData.swift RoomPlanExampleApp/RoomPhotoMetadata.swift \
  "$verification_dir/NativeSavedScansStore.swift" tests/SavedScanStoreTests.swift \
  -o "$verification_dir/saved-scan-store"
"$verification_dir/saved-scan-store"

xcrun swiftc -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/GaussianSplatFile.swift tests/SplatRegression.swift \
  -o "$verification_dir/splats"
"$verification_dir/splats" RoomPlanExampleApp/SplatAssets/plant.ply

git diff --check HEAD
echo "PASS: all local data and geometry checks. Device/model/rendering checks are separate."
