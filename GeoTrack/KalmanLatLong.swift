import Foundation
import CoreLocation

/// 2D/3D Kalman Filter for smooth GPS latitude and longitude tracking.
public class KalmanLatLong {
    private let qMetresPerSecond: Double
    private var timestamp: Date?
    private var lat: Double = 0.0
    private var lng: Double = 0.0
    private var alt: Double = 0.0
    private var variance: Double = -1.0

    public init(qMetresPerSecond: Double = 2.5) {
        self.qMetresPerSecond = qMetresPerSecond
    }

    public func reset() {
        variance = -1.0
        timestamp = nil
    }

    public func process(latMeasurement: Double, lngMeasurement: Double, altMeasurement: Double, accuracy: Double, timestamp: Date) -> (lat: Double, lng: Double, alt: Double) {
        let acc = max(1.0, accuracy)

        if variance < 0 {
            self.timestamp = timestamp
            self.lat = latMeasurement
            self.lng = lngMeasurement
            self.alt = altMeasurement
            self.variance = acc * acc
            return (lat, lng, alt)
        }

        if let lastTime = self.timestamp {
            let duration = timestamp.timeIntervalSince(lastTime)
            if duration > 0 {
                variance += duration * qMetresPerSecond * qMetresPerSecond
                self.timestamp = timestamp
            }
        }

        let k = variance / (variance + acc * acc)
        lat += k * (latMeasurement - lat)
        lng += k * (lngMeasurement - lng)
        alt += k * (altMeasurement - alt)
        variance = (1.0 - k) * variance

        return (lat, lng, alt)
    }

    public static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
}
