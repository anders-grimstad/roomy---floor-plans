# RoomPlan Example App - Project Explainer

This is an **official Apple sample app** demonstrating the **RoomPlan framework** - Apple's AR-powered room scanning technology introduced in iOS 16. It creates 3D models of interior spaces using the device's LiDAR sensor.

## What It Does

The app guides users through an **augmented reality experience** to scan a physical room. As you move your iPhone/iPad around, RoomPlan:

- Detects walls, floors, doors, windows, and furniture
- Builds a real-time 3D model of the space
- Exports the result as both **USDZ** (3D model) and **JSON** (structured data)

---

## Architecture

| File | Purpose |
|------|---------|
| `AppDelegate.swift` | Entry point; checks if device supports RoomPlan (requires LiDAR) |
| `SceneDelegate.swift` | Minimal scene lifecycle management |
| `OnboardingViewController.swift` | Initial screen with "Start Scan" button |
| `RoomCaptureViewController.swift` | **Core scanning logic** - manages the AR capture session |

---

## Key Code Highlights

### Device Compatibility Check

In `AppDelegate.swift`, the app checks for LiDAR support and shows an "Unsupported Device" screen if not available:

```swift
func application(_ application: UIApplication,
                 configurationForConnecting connectingSceneSession: UISceneSession,
                 options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    var configurationName = "Default Configuration"
    if !RoomCaptureSession.isSupported {
        configurationName = "Unsupported Device"
    }
    return UISceneConfiguration(name: configurationName, sessionRole: connectingSceneSession.role)
}
```

### Room Capture Session

In `RoomCaptureViewController.swift`, the AR scanning view is created using Apple's built-in `RoomCaptureView`:

```swift
private func setupRoomCaptureView() {
    roomCaptureView = RoomCaptureView(frame: view.bounds)
    roomCaptureView.captureSession.delegate = self
    roomCaptureView.delegate = self
    
    view.insertSubview(roomCaptureView, at: 0)
}
```

### Export Functionality

The app exports both a 3D model and structured JSON data:

```swift
@IBAction func exportResults(_ sender: UIButton) {
    let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
    let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
    let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")
    do {
        try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(finalResults)
        try jsonData.write(to: capturedRoomURL)
        try finalResults?.export(to: destinationURL, exportOptions: .mesh)

        let activityVC = UIActivityViewController(activityItems: [destinationFolderURL], applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover
        
        present(activityVC, animated: true, completion: nil)
        // ...
    } catch {
        print("Error = \(error)")
    }
}
```

---

## Exported Data Structure

The JSON export contains detailed geometric data including:

- **floors** - with polygon corners and 3D transforms
- **walls** - dimensions, orientation, confidence levels
- **openings** - doors, windows
- **objects** - furniture and fixtures

Each element includes:

| Property | Description |
|----------|-------------|
| `identifier` | Unique UUID for the element |
| `dimensions` | Width, height, depth in meters |
| `transform` | 4x4 matrix for position/rotation in 3D space |
| `confidence` | Detection confidence (high/medium/low) |
| `category` | Element type (wall, floor, door, etc.) |

---

## Requirements

- **iOS 16+**
- **iPhone/iPad with LiDAR** (iPhone 12 Pro and later, iPad Pro 2020 and later)
- Camera permission

---

## Use Cases

This example serves as a starting point for apps that need indoor spatial mapping:

- Interior design and decoration tools
- Real estate virtual tours
- Accessibility planning
- AR furniture placement
- Home renovation planning
- Floor plan generation

---

## Resources

- [Apple Developer Documentation: Create a 3D model of an interior room](https://developer.apple.com/documentation/roomplan/create_a_3d_model_of_an_interior_room_by_guiding_the_user_through_an_ar_experience)
- [RoomPlan Framework Reference](https://developer.apple.com/documentation/roomplan)

