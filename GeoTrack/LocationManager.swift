import Foundation
import CoreLocation
import Combine

public struct TrackPointItem: Identifiable {
    public let id = UUID()
    public let coordinate: CLLocationCoordinate2D
    public let altitude: Double
    public let speedKmh: Double
    public let timestamp: Date
}

public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var isTracking: Bool = false
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentAltitude: Double = 0.0
    @Published public var totalDistanceMeters: Double = 0.0
    @Published public var elapsedTimeSeconds: TimeInterval = 0
    @Published public var recordedPoints: [TrackPointItem] = []

    private let clManager = CLLocationManager()
    private let altFilter = AltitudeFilter(maxVerticalVelocityMps: 8.0)
    private let kalmanFilter = KalmanLatLong(qMetresPerSecond = 2.5)

    private var timer: Timer?
    private var startTime: Date?
    private var lastCoordinate: CLLocationCoordinate2D?

    override public init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = 2.0
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
    }

    public func startTracking() {
        clManager.requestAlwaysAuthorization()
        altFilter.reset()
        kalmanFilter.reset()
        recordedPoints.removeAll()
        totalDistanceMeters = 0.0
        currentSpeedKmh = 0.0
        currentAltitude = 0.0
        elapsedTimeSeconds = 0
        lastCoordinate = nil
        startTime = Date()

        isTracking = true
        clManager.startUpdatingLocation()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.elapsedTimeSeconds = Date().timeIntervalSince(start)
        }
    }

    public func stopTracking() {
        isTracking = false
        clManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let loc = locations.last else { return }

        let now = Date()
        let rawAlt = loc.altitude
        let vertAcc = loc.verticalAccuracy > 0 ? loc.verticalAccuracy : 15.0

        // 1. Filter altitude spikes
        let filteredAlt = altFilter.filter(rawAltitude: rawAlt, verticalAccuracy: vertAcc, timestamp: now)

        // 2. Smooth coordinate with Kalman
        let smoothed = kalmanFilter.process(
            latMeasurement: loc.coordinate.latitude,
            lngMeasurement: loc.coordinate.longitude,
            altMeasurement: filteredAlt,
            accuracy: loc.horizontalAccuracy,
            timestamp: now
        )

        let smoothedCoord = CLLocationCoordinate2D(latitude: smoothed.lat, longitude: smoothed.lng)
        let speed = max(0.0, loc.speed) * 3.6 // Convert m/s to km/h

        if let prev = lastCoordinate {
            let stepDist = KalmanLatLong.distance(from: prev, to: smoothedCoord)
            if stepDist > 1.5 {
                totalDistanceMeters += stepDist
                lastCoordinate = smoothedCoord
            }
        } else {
            lastCoordinate = smoothedCoord
        }

        currentSpeedKmh = speed
        currentAltitude = filteredAlt

        let point = TrackPointItem(
            coordinate: smoothedCoord,
            altitude: filteredAlt,
            speedKmh: speed,
            timestamp: now
        )
        recordedPoints.append(point)
    }
}
