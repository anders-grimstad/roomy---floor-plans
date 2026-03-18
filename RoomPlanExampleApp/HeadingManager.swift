/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
CoreLocation-backed heading updates for scan metadata.
*/

import CoreLocation
import CoreMotion
import Foundation

enum HeadingStatus: Equatable {
    case idle
    case unavailable
    case waitingForAuthorization
    case denied
    case active
}

final class HeadingManager: NSObject, ObservableObject {
    @Published private(set) var latestHeading: ScanHeading?
    @Published private(set) var latestCameraHeading: ScanHeading?
    @Published private(set) var status: HeadingStatus = .idle

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let motionUpdateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "HeadingManager.motionQueue"
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private let headingFilterDegrees: CLLocationDegrees = 1.0
    private let maxHeadingHistoryAge: TimeInterval = 20
    private let maxHeadingHistoryCount = 120
    private var headingHistory: [ScanHeading] = []
    private var cameraHeadingHistory: [ScanHeading] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = headingFilterDegrees
        locationManager.headingOrientation = .portrait
    }

    func start() {
        guard CLLocationManager.headingAvailable() else {
            status = .unavailable
            return
        }

        let authorization = locationManager.authorizationStatus
        switch authorization {
        case .notDetermined:
            status = .waitingForAuthorization
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            status = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingHeading()
            startCameraHeadingUpdates()
            status = .active
        @unknown default:
            status = .denied
        }
    }

    func stop() {
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        status = .idle
    }

    func resetHistory() {
        headingHistory.removeAll()
        cameraHeadingHistory.removeAll()
        latestHeading = nil
        latestCameraHeading = nil
    }

    func snapshotHeading() -> ScanHeading? {
        latestHeading
    }

    func snapshotHeading(near targetDate: Date, maxAge: TimeInterval = 3.0) -> ScanHeading? {
        guard let latestHeading else { return nil }
        let age = abs(latestHeading.capturedAt.timeIntervalSince(targetDate))
        return age <= maxAge ? latestHeading : nil
    }

    func snapshotHeadings(near targetDate: Date, maxAge: TimeInterval = 0.8, limit: Int = 8) -> [ScanHeading] {
        let candidates = headingHistory.filter {
            abs($0.capturedAt.timeIntervalSince(targetDate)) <= maxAge
        }
        return candidates
            .sorted {
                abs($0.capturedAt.timeIntervalSince(targetDate)) < abs($1.capturedAt.timeIntervalSince(targetDate))
            }
            .prefix(limit)
            .map { $0 }
    }

    func snapshotCameraHeadings(near targetDate: Date, maxAge: TimeInterval = 0.8, limit: Int = 8) -> [ScanHeading] {
        let candidates = cameraHeadingHistory.filter {
            abs($0.capturedAt.timeIntervalSince(targetDate)) <= maxAge
        }
        return candidates
            .sorted {
                abs($0.capturedAt.timeIntervalSince(targetDate)) < abs($1.capturedAt.timeIntervalSince(targetDate))
            }
            .prefix(limit)
            .map { $0 }
    }

    func bestHeadingSample(
        near targetDate: Date,
        maxAge: TimeInterval,
        maxAccuracy: Double
    ) -> ScanHeading? {
        snapshotHeadings(near: targetDate, maxAge: maxAge, limit: 12)
            .filter { heading in
                guard let accuracy = heading.accuracyDegrees else { return false }
                return accuracy <= maxAccuracy
            }
            .sorted { lhs, rhs in
                if lhs.reference != rhs.reference {
                    return lhs.reference == .trueNorth
                }
                let lhsAccuracy = lhs.accuracyDegrees ?? .greatestFiniteMagnitude
                let rhsAccuracy = rhs.accuracyDegrees ?? .greatestFiniteMagnitude
                if lhsAccuracy != rhsAccuracy {
                    return lhsAccuracy < rhsAccuracy
                }
                return abs(lhs.capturedAt.timeIntervalSince(targetDate)) < abs(rhs.capturedAt.timeIntervalSince(targetDate))
            }
            .first
    }

    func bestCameraHeadingSample(
        near targetDate: Date,
        maxAge: TimeInterval,
        maxAccuracy: Double
    ) -> ScanHeading? {
        snapshotCameraHeadings(near: targetDate, maxAge: maxAge, limit: 12)
            .filter { heading in
                guard let accuracy = heading.accuracyDegrees else { return false }
                return accuracy <= maxAccuracy
            }
            .sorted { lhs, rhs in
                if lhs.reference != rhs.reference {
                    return lhs.reference == .trueNorth
                }
                let lhsAccuracy = lhs.accuracyDegrees ?? .greatestFiniteMagnitude
                let rhsAccuracy = rhs.accuracyDegrees ?? .greatestFiniteMagnitude
                if lhsAccuracy != rhsAccuracy {
                    return lhsAccuracy < rhsAccuracy
                }
                return abs(lhs.capturedAt.timeIntervalSince(targetDate)) < abs(rhs.capturedAt.timeIntervalSince(targetDate))
            }
            .first
    }

    private func appendHeading(_ heading: ScanHeading) {
        headingHistory.append(heading)

        if headingHistory.count > maxHeadingHistoryCount {
            headingHistory.removeFirst(headingHistory.count - maxHeadingHistoryCount)
        }

        let cutoffDate = heading.capturedAt.addingTimeInterval(-maxHeadingHistoryAge)
        headingHistory.removeAll { $0.capturedAt < cutoffDate }
    }

    private func appendCameraHeading(_ heading: ScanHeading) {
        cameraHeadingHistory.append(heading)

        if cameraHeadingHistory.count > maxHeadingHistoryCount {
            cameraHeadingHistory.removeFirst(cameraHeadingHistory.count - maxHeadingHistoryCount)
        }

        let cutoffDate = heading.capturedAt.addingTimeInterval(-maxHeadingHistoryAge)
        cameraHeadingHistory.removeAll { $0.capturedAt < cutoffDate }
    }

    private func startCameraHeadingUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        let referenceFrame = preferredAttitudeReferenceFrame()
        guard referenceFrame != .xArbitraryZVertical else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: motionUpdateQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            guard let cameraHeadingDegrees = Self.cameraForwardHeadingDegrees(from: motion) else { return }
            let reference: ScanHeading.Reference = (referenceFrame == .xTrueNorthZVertical) ? .trueNorth : .magneticNorth
            let cameraHeading = ScanHeading(
                headingDegrees: cameraHeadingDegrees,
                accuracyDegrees: self.latestHeading?.accuracyDegrees,
                reference: reference,
                capturedAt: Self.motionDate(from: motion.timestamp),
                captureMethod: "coreMotionCameraForwardHeading"
            )
            DispatchQueue.main.async {
                self.latestCameraHeading = cameraHeading
                self.appendCameraHeading(cameraHeading)
            }
        }
    }

    private func preferredAttitudeReferenceFrame() -> CMAttitudeReferenceFrame {
        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()
        if availableFrames.contains(.xTrueNorthZVertical) {
            return .xTrueNorthZVertical
        }
        if availableFrames.contains(.xMagneticNorthZVertical) {
            return .xMagneticNorthZVertical
        }
        return .xArbitraryZVertical
    }

    private static func cameraForwardHeadingDegrees(from motion: CMDeviceMotion) -> Double? {
        let rotation = motion.attitude.rotationMatrix

        // Rotation matrix is reference -> device. Transpose maps device -> reference.
        // Device forward for the rear camera is -Z in device coordinates.
        // Keep this aligned with ARKit cameraYaw extraction that also uses camera forward.
        let northComponent = -rotation.m31
        let westComponent = -rotation.m32
        let horizontalMagnitude = sqrt(northComponent * northComponent + westComponent * westComponent)
        guard horizontalMagnitude >= 0.15 else { return nil }

        let eastComponent = -westComponent
        return normalizedDegrees(atan2(eastComponent, northComponent) * 180 / .pi)
    }

    private static func motionDate(from timestamp: TimeInterval) -> Date {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let age = uptime - timestamp
        guard age.isFinite, age >= 0, age <= 5 else { return now }
        return now.addingTimeInterval(-age)
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

extension HeadingManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            if status != .active {
                manager.startUpdatingHeading()
                startCameraHeadingUpdates()
                status = .active
            }
        case .restricted, .denied:
            status = .denied
        case .notDetermined:
            status = .waitingForAuthorization
        @unknown default:
            status = .denied
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let accuracy = newHeading.headingAccuracy >= 0 ? newHeading.headingAccuracy : nil
        let usesTrueHeading = newHeading.trueHeading >= 0
        let headingValue = usesTrueHeading ? newHeading.trueHeading : newHeading.magneticHeading
        let reference: ScanHeading.Reference = usesTrueHeading ? .trueNorth : .magneticNorth

        latestHeading = ScanHeading(
            headingDegrees: headingValue,
            accuracyDegrees: accuracy,
            reference: reference,
            capturedAt: Date(),
            captureMethod: "coreLocationHeading"
        )
        if let latestHeading {
            appendHeading(latestHeading)
        }
    }
}
