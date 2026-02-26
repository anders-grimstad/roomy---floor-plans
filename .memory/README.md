## `.memory/` index

This folder contains **project-specific, repo-local documentation** intended for quick orientation and future AI/human reference.

### Contents

- **`ARCHITECTURE_OVERVIEW.md`**: high-level architecture and data flow (capture → post-process → exports; floor plan pipeline).
- **`COMPONENTS.md`**: inventory of major components (Swift app + Python tooling), with file links and responsibilities.
- **`SDKS_AND_APIS.md`**: Apple SDKs/APIs used (RoomPlan, UIKit, SwiftUI, CoreGraphics, simd) and key constraints.
- **`DATA_AND_EXPORT_FORMATS.md`**: exported file formats and the important data-model details (transforms, coordinate mapping, JSON schemas).
- **`USER_FLOWS.md`**: mermaid diagrams of the main end-user flows.

### Scope / non-goals

- This documentation mirrors **the current repository state** (not “ideal” architecture).
- No behavior changes are implied—these docs describe what the code does today.

