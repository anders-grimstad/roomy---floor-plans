/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Shared scan-level heading metadata for exports and UI.
*/

import Foundation

private func normalizeDegrees(_ degrees: Double) -> Double {
    let value = degrees.truncatingRemainder(dividingBy: 360)
    return value < 0 ? value + 360 : value
}

enum HeadingConfidenceState: String, Codable {
    case high
    case medium
    case low
    case uncalibrated

    var label: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Low confidence"
        case .uncalibrated:
            return "Uncalibrated"
        }
    }
}

struct ScanHeading: Codable, Equatable {
    enum Reference: String, Codable {
        case trueNorth
        case magneticNorth
    }

    let headingDegrees: Double
    let accuracyDegrees: Double?
    let reference: Reference
    let capturedAt: Date
    let captureMethod: String

    static let balancedReliableAccuracyThreshold: Double = 18
    static let highConfidenceAccuracyThreshold: Double = 10
    static let lowConfidenceAccuracyThreshold: Double = 30

    var normalizedDegrees: Double {
        normalizeDegrees(headingDegrees)
    }

    var cardinalDirection: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalizedDegrees + 22.5) / 45.0) % directions.count
        return directions[index]
    }

    var isReliable: Bool {
        switch confidenceState {
        case .high, .medium:
            return true
        case .low, .uncalibrated:
            return false
        }
    }

    var confidenceState: HeadingConfidenceState {
        guard let accuracyDegrees else { return .uncalibrated }
        if accuracyDegrees <= Self.highConfidenceAccuracyThreshold {
            return .high
        }
        if accuracyDegrees <= Self.balancedReliableAccuracyThreshold {
            return .medium
        }
        if accuracyDegrees <= Self.lowConfidenceAccuracyThreshold {
            return .low
        }
        return .uncalibrated
    }

    var referenceLabel: String {
        switch reference {
        case .trueNorth:
            return "True North"
        case .magneticNorth:
            return "Magnetic North"
        }
    }

    var summaryLabel: String {
        let degrees = Int(normalizedDegrees.rounded())
        return "Heading \(degrees)° \(cardinalDirection)"
    }

    var detailLabel: String {
        let accuracyText: String
        if let accuracyDegrees {
            accuracyText = "±\(Int(accuracyDegrees.rounded()))°"
        } else {
            accuracyText = "Uncalibrated"
        }
        return "\(referenceLabel) • \(accuracyText) • \(confidenceState.label)"
    }

    var exportLabel: String {
        "\(summaryLabel) • \(detailLabel)"
    }
}

struct ScanNorthAlignment: Codable, Equatable {
    let roomToNorthYawDegrees: Double
    let reference: ScanHeading.Reference
    let accuracyDegrees: Double?
    let calibratedAt: Date
    let calibrationMethod: String
    let calibrationHeadingDegrees: Double?
    let calibrationCameraYawDegrees: Double?
    let sampleCount: Int?
    let spreadDegrees: Double?
    let confidence: HeadingConfidenceState?

    init(
        roomToNorthYawDegrees: Double,
        reference: ScanHeading.Reference,
        accuracyDegrees: Double?,
        calibratedAt: Date,
        calibrationMethod: String,
        calibrationHeadingDegrees: Double? = nil,
        calibrationCameraYawDegrees: Double? = nil,
        sampleCount: Int? = nil,
        spreadDegrees: Double? = nil,
        confidence: HeadingConfidenceState? = nil
    ) {
        self.roomToNorthYawDegrees = roomToNorthYawDegrees
        self.reference = reference
        self.accuracyDegrees = accuracyDegrees
        self.calibratedAt = calibratedAt
        self.calibrationMethod = calibrationMethod
        self.calibrationHeadingDegrees = calibrationHeadingDegrees
        self.calibrationCameraYawDegrees = calibrationCameraYawDegrees
        self.sampleCount = sampleCount
        self.spreadDegrees = spreadDegrees
        self.confidence = confidence
    }

    var normalizedRoomToNorthYawDegrees: Double {
        normalizeDegrees(roomToNorthYawDegrees)
    }

    var isReliable: Bool {
        switch confidenceState {
        case .high, .medium:
            return true
        case .low, .uncalibrated:
            return false
        }
    }

    var confidenceState: HeadingConfidenceState {
        if let confidence {
            return confidence
        }

        guard let accuracyDegrees else { return .uncalibrated }
        let spread = spreadDegrees ?? 0
        let samples = sampleCount ?? 1

        if samples >= 6 && spread <= 4 && accuracyDegrees <= 8 {
            return .high
        }
        if samples >= 4 && spread <= 10 && accuracyDegrees <= ScanHeading.balancedReliableAccuracyThreshold {
            return .medium
        }
        if accuracyDegrees <= ScanHeading.lowConfidenceAccuracyThreshold {
            return .low
        }
        return .uncalibrated
    }

    var statusLabel: String {
        "North lock • \(confidenceState.label)"
    }

    var unavailableReason: String {
        if let spreadDegrees, spreadDegrees > 10 {
            return "North-up unavailable: heading was unstable during calibration."
        }
        if let sampleCount, sampleCount < 4 {
            return "North-up unavailable: not enough stable calibration samples."
        }
        if let accuracyDegrees {
            return "North-up unavailable: heading accuracy is low (±\(Int(accuracyDegrees.rounded()))°)."
        }
        return "North-up unavailable: compass calibration is incomplete."
    }
}

struct RoomExportMetadata: Codable {
    let generatedAt: Date
    let scanHeading: ScanHeading?
    let northAlignment: ScanNorthAlignment?
}
