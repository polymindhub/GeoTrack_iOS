import Foundation

/// Robust Altitude Filter for iOS to eliminate GPS vertical spikes, jumps, and jitter.
public class AltitudeFilter {
    private let maxVerticalVelocityMps: Double
    private var smoothedAltitude: Double?
    private var lastTimestamp: Date?
    private var consecutiveSpikeCount: Int = 0

    public init(maxVerticalVelocityMps: Double = 8.0) {
        self.maxVerticalVelocityMps = maxVerticalVelocityMps
    }

    public func reset() {
        smoothedAltitude = nil
        lastTimestamp = nil
        consecutiveSpikeCount = 0
    }

    public func filter(rawAltitude: Double, verticalAccuracy: Double, timestamp: Date) -> Double {
        guard let currentSmoothed = smoothedAltitude, let lastTime = lastTimestamp else {
            smoothedAltitude = rawAltitude
            lastTimestamp = timestamp
            consecutiveSpikeCount = 0
            return rawAltitude
        }

        let dtSec = max(0.1, min(30.0, timestamp.timeIntervalSince(lastTime)))
        lastTimestamp = timestamp

        let maxAllowedDelta = max(3.0, maxVerticalVelocityMps * dtSec)
        let rawDelta = rawAltitude - currentSmoothed
        var targetAltitude = rawAltitude

        if abs(rawDelta) > maxAllowedDelta {
            consecutiveSpikeCount += 1
            if consecutiveSpikeCount < 4 {
                let clampedDelta = rawDelta > 0 ? maxAllowedDelta : -maxAllowedDelta
                targetAltitude = currentSmoothed + clampedDelta
            } else {
                targetAltitude = currentSmoothed + (rawDelta * 0.3)
            }
        } else {
            consecutiveSpikeCount = 0
        }

        let accuracyWeight: Double
        if verticalAccuracy <= 5.0 {
            accuracyWeight = 0.40
        } else if verticalAccuracy <= 12.0 {
            accuracyWeight = 0.25
        } else if verticalAccuracy <= 25.0 {
            accuracyWeight = 0.15
        } else {
            accuracyWeight = 0.08
        }

        let timeFactor = max(0.5, min(2.0, dtSec / 2.0))
        let alpha = max(0.05, min(0.50, accuracyWeight * timeFactor))

        let updatedAltitude = currentSmoothed + alpha * (targetAltitude - currentSmoothed)
        smoothedAltitude = updatedAltitude
        return updatedAltitude
    }
}
