/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The sample app's main view controller that manages the scanning process.
*/

import UIKit
import RoomPlan
import ARKit
import simd

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ARSessionDelegate {
    
    @IBOutlet var exportButton: UIButton?
    
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?
    @IBOutlet var activityIndicator: UIActivityIndicatorView?
    
    private var isScanning: Bool = false
    
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    private var finalResults: CapturedRoom?
    
    // MARK: - Minimap
    
    private lazy var minimapView: MinimapView = {
        let v = MinimapView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private var arSession: ARSession?
    private var lastCurrentRoomUpdate: CFTimeInterval = 0
    
    // Floor Plan button (created programmatically)
    private lazy var floorPlanButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Floor Plan"
        config.image = UIImage(systemName: "square.split.bottomrightquarter")
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor(red: 0.31, green: 0.80, blue: 0.64, alpha: 1.0)
        config.baseForegroundColor = .black
        
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(showFloorPlan), for: .touchUpInside)
        button.alpha = 0
        button.isHidden = true
        button.isEnabled = false
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up after loading the view.
        setupRoomCaptureView()
        setupFloorPlanButton()
        setupMinimapView()
        activityIndicator?.stopAnimating()
    }
    
    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        
        view.insertSubview(roomCaptureView, at: 0)
    }
    
    private func setupFloorPlanButton() {
        view.addSubview(floorPlanButton)
        
        // Position the floor plan button next to the export button
        NSLayoutConstraint.activate([
            floorPlanButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            floorPlanButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func setupMinimapView() {
        view.addSubview(minimapView)
        view.bringSubviewToFront(minimapView)
        
        NSLayoutConstraint.activate([
            minimapView.widthAnchor.constraint(equalToConstant: 180),
            minimapView.heightAnchor.constraint(equalToConstant: 180),
            minimapView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            minimapView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -120)
        ])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
        hookPoseUpdatesIfPossible()
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
        unhookPoseUpdates()
    }
    
    private func startSession() {
        isScanning = true
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        
        setActiveNavBar()
    }
    
    private func stopSession() {
        isScanning = false
        roomCaptureView?.captureSession.stop()
        
        setCompleteNavBar()
    }
    
    // Decide to post-process and show the final results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    // Access the final post-processed results.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        self.exportButton?.isEnabled = true
        self.floorPlanButton.isEnabled = true
        self.activityIndicator?.stopAnimating()
        
        // Accumulate completed rooms on the minimap.
        let generator = FloorPlanGenerator(capturedRoom: processedResult)
        let data = generator.generate()
        minimapView.appendCompletedRoom(data)
    }

    // MARK: - ARSessionDelegate (Pose updates)
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Convert ARKit world pose → floorplan 2D (meters): x = -worldX, y = worldZ.
        let t = frame.camera.transform
        let posWorld = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let pos2D = CGPoint(x: -CGFloat(posWorld.x), y: CGFloat(posWorld.z))
        
        // Heading from camera forward vector, projected to XZ, then mapped to floorplan 2D.
        let forwardWorld = -simd_float3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let f2 = simd_float2(-forwardWorld.x, forwardWorld.z)
        let len = simd_length(f2)
        let headingRad: CGFloat
        if len > 1e-6 {
            let n = f2 / len
            headingRad = CGFloat(atan2(n.y, n.x))
        } else {
            headingRad = 0
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.minimapView.updatePose(position2D: pos2D, headingRad: headingRad)
        }
    }
    
    private func hookPoseUpdatesIfPossible() {
        guard arSession == nil else { return }
        
        // Prefer grabbing the ARSession used by RoomPlan if it’s exposed.
        // We avoid hard dependencies on specific SDK symbols by using Objective‑C runtime selectors.
        if let session = extractARSessionFromRoomPlan() {
            arSession = session
            session.delegate = self
        }
    }
    
    private func unhookPoseUpdates() {
        arSession?.delegate = nil
        arSession = nil
    }
    
    private func extractARSessionFromRoomPlan() -> ARSession? {
        // 1) Try captureSession.arSession
        if let s = performSelector("arSession", on: roomCaptureView.captureSession as AnyObject) as? ARSession {
            return s
        }
        // 2) Try RoomCaptureView.arSession
        if let s = performSelector("arSession", on: roomCaptureView as AnyObject) as? ARSession {
            return s
        }
        // 3) Try RoomCaptureView.arView?.session (RealityKit)
        if let arView = performSelector("arView", on: roomCaptureView as AnyObject) {
            // Avoid importing RealityKit explicitly; read `session` via selector.
            if let s = performSelector("session", on: arView as AnyObject) as? ARSession {
                return s
            }
        }
        return nil
    }
    
    private func performSelector(_ name: String, on object: AnyObject) -> Any? {
        let sel = NSSelectorFromString(name)
        guard let nsObject = object as? NSObject, nsObject.responds(to: sel) else { return nil }
        return nsObject.perform(sel)?.takeUnretainedValue()
    }

    // MARK: - Optional live geometry updates (current room)
    //
    // If your RoomPlan SDK version provides a live update callback, you can route it here.
    // This method signature may vary across SDK versions; if it matches, it will be called.
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // Throttle to avoid heavy regeneration at frame rate.
        let now = CACurrentMediaTime()
        if now - lastCurrentRoomUpdate < 0.15 { return } // ~6–7 Hz
        lastCurrentRoomUpdate = now
        
        let generator = FloorPlanGenerator(capturedRoom: room)
        let data = generator.generate()
        DispatchQueue.main.async { [weak self] in
            self?.minimapView.setCurrentRoom(data)
        }
    }
    
    @IBAction func doneScanning(_ sender: UIBarButtonItem) {
        if isScanning { stopSession() } else { cancelScanning(sender) }
        self.exportButton?.isEnabled = false
        self.floorPlanButton.isEnabled = false
        self.activityIndicator?.startAnimating()
    }

    @IBAction func cancelScanning(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }
    
    @objc private func showFloorPlan() {
        guard let capturedRoom = finalResults else {
            print("No captured room data available")
            return
        }
        
        let floorPlanVC = FloorPlanViewController(capturedRoom: capturedRoom)
        floorPlanVC.modalPresentationStyle = .fullScreen
        present(floorPlanVC, animated: true)
    }
    
    // Export the USDZ output by specifying the `.mesh` export option.
    // Alternatively, `.parametric` exports the model as unit-sized cubes and `.all`
    // exports both in a single USDZ.
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
            if let popOver = activityVC.popoverPresentationController {
                popOver.sourceView = self.exportButton
            }
        } catch {
            print("Error = \(error)")
        }
    }
    
    private func setActiveNavBar() {
        UIView.animate(withDuration: 1.0, animations: {
            self.cancelButton?.tintColor = .white
            self.doneButton?.tintColor = .white
            self.exportButton?.alpha = 0.0
            self.floorPlanButton.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
            self.floorPlanButton.isHidden = true
        })
    }
    
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        self.floorPlanButton.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
            self.floorPlanButton.alpha = 1.0
        }
    }
}

