# Photo suggestion validation

Roomy's saved-scan library offers **Photo Suggestions** in a scan's leading swipe actions and context menu. Choose a room image, explicitly select **Generate Suggestions**, review and edit the result, then choose **Accept and Save**. Only accepted title/description metadata is written to the library index. The selected image is held in memory for the sheet and is not saved by Roomy.

## Local checks

Run the production metadata persistence checks:

```sh
swiftc -module-cache-path /tmp/roomy-photo-module-cache -parse-as-library RoomPlanExampleApp/RoomPhotoMetadata.swift tests/PhotoMetadataTests.swift -o /tmp/roomy-photo-metadata-tests
/tmp/roomy-photo-metadata-tests
```

These checks load a legacy saved-scan index without descriptions, accept and reopen edited metadata, preserve scan identity/date/area, preserve descriptions through rename, and reject empty names or missing scans. They use an isolated temporary directory and synthetic metadata, not physical room captures.

The UI and model integration use `SystemLanguageModel.default` exclusively. There is no cloud fallback, API key, or model tool. Image attachment APIs are availability-gated to iOS 27; older systems show an explanatory sheet. Device eligibility, Apple Intelligence settings, and model download status are checked before generation.

## Physical-device evaluation — pending

Use an Apple Intelligence-capable iPhone/iPad on iOS/iPadOS 27 or newer with Apple Intelligence enabled and its on-device model ready. Build the RoomPlanExampleApp scheme. Do not interpret a successful build as a model-quality evaluation.

For each of these ten user-selected photos, record the suggested title and description, generation latency shown in the sheet, whether the title is useful, every invented or omitted detail, and whether any edits were needed:

| Photo | Suggested title/description | Latency | Useful? | Incorrect details / edits |
|---|---|---|---|---|
| Clearly lit kitchen | Pending | Pending | Pending | Pending |
| Living room with mixed furniture | Pending | Pending | Pending | Pending |
| Small bedroom | Pending | Pending | Pending | Pending |
| Bathroom | Pending | Pending | Pending | Pending |
| Empty room | Pending | Pending | Pending | Pending |
| Combined kitchen/living area | Pending | Pending | Pending | Pending |
| Dim room | Pending | Pending | Pending | Pending |
| Cluttered room | Pending | Pending | Pending | Pending |
| Portrait photo with EXIF rotation | Pending | Pending | Pending | Pending |
| Blurred photo or image that is not a room | Pending | Pending | Pending | Pending |

For each result, inspect the description for invented measurements, area, safety or condition assessments, and claims about features outside the image. Suggestions must remain editable; accepting them must not alter the scan's measured area, geometry, orientation, or existing export data.

Also verify:

1. Generate, edit both fields, accept, close the library, reopen it, and confirm title and description survive. Rename the scan and save its floor plan; confirm the description survives both operations.
2. Generate and dismiss without accepting; confirm the saved title/description remain unchanged.
3. Cancel while generating, choose a different image, and generate again. The cancelled response must not replace the new result.
4. Dismiss the sheet during photo loading or generation; confirm no later metadata change or alert appears.
5. Turn off Apple Intelligence, test an ineligible device, and test while its model is not ready. Confirm the explanation is useful and existing scanning/library features work.
6. Test an unreadable image/loading error and a generation failure or refusal. Confirm a visible error and a retry path.
7. Test the unsupported-OS sheet on iOS 18.6/26, including closing it.

The metadata tests do not exercise the model. A separate native model check was
run on October 30, 2026 on this Mac (macOS 27.2), using the same production
`RoomPhotoSuggestionService` as the app. The on-device model reported available.
Image-buffer access required running outside the shell sandbox.

Only the two existing licensed exterior photos below were evaluated; these are
negative/non-room cases, not a substitute for the ten-room-photo checklist.

| Existing project image | Actual suggestion | Measured time | Visual assessment |
| --- | --- | --- | --- |
| george-barros-t4FMbSdmeR0-unsplash.jpg | “Exterior of a House”; multi-storey white building, windows, balcony, flat roof, plants and path | 2.85 s | Recognized exterior; visible features broadly consistent |
| john-joumaa-yoihgoqV41w-unsplash.jpg | “House in Field”; small light house, gabled roof, **two doors**, grass and trees | 1.67 s | Recognized exterior, but invented a second door; photo visibly has one front door |

No dimensions, areas, safety assessments or hidden-room claims appeared in
these two outputs. The incorrect door count is a real quality limitation:
human review remains necessary. No iPhone latency, cancellation UX, positive
interior-photo quality, or full ten-photo evaluation is claimed.

Reproduce using explicitly chosen local images:

```sh
xcrun swiftc -parse-as-library -module-cache-path /tmp/roomy-photo-eval-cache RoomPlanExampleApp/RoomPhotoMetadata.swift RoomPlanExampleApp/RoomPhotoSuggestionService.swift scripts/evaluate-photo-suggestions.swift -o /tmp/roomy-photo-evaluation
/tmp/roomy-photo-evaluation /absolute/path/to/room-photo.jpg
```

Use `scripts/probe-model.swift` with `swiftc -parse-as-library` to inspect the
Mac's model availability without generating a response. The evaluator never
writes suggestions into the library.

## API references

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Generating structured content and checking availability](https://developer.apple.com/tutorials/develop-in-swift/generate-structured-content)
- Installed iOS 27.2 FoundationModels Swift interface: image attachments accept `CGImage` plus an orientation; a typed response is requested with `respond(generating:...)`.
