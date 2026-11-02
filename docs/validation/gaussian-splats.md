# Gaussian splat experiment

## Implemented

Open **Gaussian Splats · Experimental** from Roomy's home screen. The viewer
loads Apple's real potted-plant scan, or a user-selected compatible Gaussian
PLY file. Drag to orbit, pinch or move the camera-distance slider to zoom,
and choose Reset to restore framing. Imports remain local and are viewed for
the session; this experiment does not copy them into the saved-scan library.

The feature uses RealityKit's `GaussianSplatComponent`, `GaussianSplatResource`,
and `LowLevelBuffer`. The installed iOS 27.2 SDK marks these APIs available from
iOS 27.0. Earlier systems get an explanatory screen. Rendering additionally
requires Apple7 GPU family support and physical hardware; Simulator displays
an explanation. A supported non-LiDAR device can view an imported splat.

The parser accepts the common **binary little-endian PLY 1.0** Gaussian schema:
float position (`x/y/z`), log scale (`scale_0…2`), wxyz quaternion (`rot_0…3`),
opacity logit (`opacity`), and diffuse spherical harmonics (`f_dc_0…2`). Optional
`f_rest_0…N` coefficients support SH degrees 0–3 and are transposed from
channel-major file storage to RealityKit's RGB-interleaved buffer layout.
Other scalar fields and scalar metadata elements preceding the vertices are
skipped using their declared byte sizes. ASCII, big-endian, compressed PLY,
list properties, ordinary point clouds, and mesh-only PLY are rejected with a
visible error. PLY conventions are not universal; export conventional 3DGS
PLY when converting an incompatible asset.

Apple's plant file includes negative-infinity opacity logits for invisible
splats. These become finite -80 logits for the GPU, preserving effective
transparency. Non-finite geometry and missing/truncated properties fail
before GPU upload. File reading/parsing and buffer allocation/copy run off the
main actor with cancellation checks, including checks between 1 MiB copy
chunks. Only RealityKit resource/entity construction remains on the main
actor. Failed imports retain the previously loaded scene.

Walkthrough was not added: orbit/zoom/reset provide the required first
experiment, while an indoor walkthrough requires scene-specific navigation
and a room asset to validate it. Capture, reconstruction/training, and
RoomPlan alignment remain outside this viewer's scope.

## Assets and sources

- `RoomPlanExampleApp/SplatAssets/plant.ply`: Apple's 51,352-splat real object
  capture. It is not a Roomy room capture or a synthetic test fixture.
- The adjacent `LICENSE-Apple.txt` preserves Apple's MIT permission notice.
- [Apple sample and download](https://developer.apple.com/documentation/visionos/rendering-gaussian-splats-with-realitykit).
- [Component documentation and GPU requirement](https://developer.apple.com/documentation/realitykit/gaussiansplatcomponent).
- [WWDC26 RealityKit session, 17:09](https://developer.apple.com/videos/play/wwdc2026/279/?time=1029).

## Automated verification

The parser regression executable exercises production code with small
synthetic PLY inputs. It checks positions, log scales, quaternion order,
metadata offsets, SH transposition, truncation, missing fields, non-finite
geometry, unsupported encoding, malformed headers, and the complete bundled
Apple capture. A valid file initially failed against the unimplemented parser.
A subsequent opacity test failed on Apple's valid negative-infinity logits,
then passed after preserving their effective transparency.

Run from the repository root:

```sh
swiftc -parse-as-library -module-cache-path /tmp/roomy-splat-module-cache RoomPlanExampleApp/GaussianSplatFile.swift tests/SplatRegression.swift -o /tmp/roomy-splat-regression
/tmp/roomy-splat-regression RoomPlanExampleApp/SplatAssets/plant.ply
```

For a separate native macOS 27 GPU resource/upload check:

```sh
swiftc -parse-as-library -module-cache-path /tmp/roomy-splat-module-cache RoomPlanExampleApp/GaussianSplatFile.swift RoomPlanExampleApp/GaussianSplatRendering.swift tests/SplatGPURegression.swift -o /tmp/roomy-splat-gpu-regression
/tmp/roomy-splat-gpu-regression RoomPlanExampleApp/SplatAssets/plant.ply
```

The GPU executable also checks that cancelled background buffer preparation
throws rather than publishing an asset. It prints SKIP if the required OS/GPU is unavailable.
Resource creation does not prove visual fidelity, frame rate, or thermal
behavior. Record those separately below.

`tests/SplatRendering.swift` additionally runs the production factory through a
native offscreen RealityRenderer and saves `/tmp/roomy-splat-render.png`. Run
`bash scripts/verify-native.sh` on a supported Mac for this and the native
annotation/export checks. This is a Mac rendering check, not an iPhone UI,
navigation, frame-rate or thermal test.

Observed on October 30, 2026: parser regression checks passed against the
synthetic inputs and bundled real capture. The iOS 18.6 deployment-target
typecheck passed with Xcode 27.2. The native GPU check on macOS 27.2 created
all 51,352 splats on an Apple M3 Pro. Metal was unavailable inside the shell
sandbox; the same check with authorized native Metal access passed.

On October 31, an offscreen RealityRenderer image appeared unusually dark.
To isolate the loader, the same camera, render target, and PNG-export harness
was run with Apple's **unmodified** PLYParser and SplatEntityBuilder. It produced
the same dark plant: mean absolute RGB differences were only approximately
0.127, 0.122, and 0.111 on the 0–255 scale. Roomy's SH ordering, normalization,
and descriptor stride therefore match the reference in this rendering path.
No light, brightness multiplier, or extra diffuse bias was added to compensate.
The harness's linear `.rgba8Unorm` texture and PNG color-space handling need
separate validation; the dark exported image alone does not establish a
production loader defect or establish correct on-screen visual fidelity.

## Physical-device checks — pending

Record device, OS/build, app commit, asset source/license, file size, splat
count, and SH degree for every run. Do not mark a row passed from a build or
parser result.

| Check | Procedure | Evidence to record |
| --- | --- | --- |
| Bundled sample | Open the experiment, inspect plant and soil from several angles | Screenshot; missing/incorrect colors or geometry |
| Room import | Import a licensed real room PLY; orbit at several heights | Screenshot; scale/framing and orientation notes |
| Reset | Orbit and zoom, tap Reset | Framing returns to initial position |
| Close/pull-back | Zoom close until splats leave the frustum; pull back and hold still; repeat ten times | Any missing splats, persistence, recording |
| Responsiveness | Orbit continuously for three minutes, then load a larger room asset | Instruments frame timings and stalls |
| Memory | Profile sample and room loads, repeated imports, and dismissal | Peak/resident memory and whether allocations release |
| Heat | View/orbit for five minutes on battery | Thermal state before/after, throttling, subjective warmth |
| Invalid import | Try a mesh PLY, truncated PLY, and unsupported encoding | Error appears; previous valid scene remains usable |
| Cancellation | Cancel a large load; dismiss while loading; reopen | No stale scene replacement or crash |
| Compatibility | Open on pre-iOS 27, unsupported GPU, and Simulator | Explanatory screen; existing Roomy flows remain usable |

Rendering and performance measurements have not been claimed as passed by
the parser or SDK typecheck results.
