#!/bin/bash
# Optional real PaperKit/GPU checks on a supported Mac, separate from iOS device validation.
set -euo pipefail
cd "$(dirname "$0")/.."
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/roomy-native.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

xcrun swiftc -parse-as-library -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift RoomPlanExampleApp/FloorPlanAnnotationRendering.swift \
  tests/AnnotationRendering.swift -o "$verification_dir/annotations"
"$verification_dir/annotations"

xcrun swiftc -parse-as-library -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/FloorPlanAnnotationGeometry.swift RoomPlanExampleApp/FloorPlanAnnotationRendering.swift \
  tests/AnnotationBoundarySave.swift -o "$verification_dir/annotation-boundary"
"$verification_dir/annotation-boundary"

python3 scripts/render-export-qa.py
python3 scripts/render-export-qa.py --edge-test

xcrun swiftc -parse-as-library -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/GaussianSplatFile.swift RoomPlanExampleApp/GaussianSplatRendering.swift \
  tests/SplatGPURegression.swift -o "$verification_dir/splat-upload"
"$verification_dir/splat-upload" RoomPlanExampleApp/SplatAssets/plant.ply

xcrun swiftc -parse-as-library -module-cache-path "$verification_dir/modules" \
  RoomPlanExampleApp/GaussianSplatFile.swift RoomPlanExampleApp/GaussianSplatRendering.swift \
  tests/SplatRendering.swift -o "$verification_dir/splats"
"$verification_dir/splats"
