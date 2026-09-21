import Foundation
import CoreLocation
import Combine

public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var isTracking: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var isGpsActive: Bool = false
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentAltitude: Double = 0.0
    @Published public var accuracyMeters: Double = 0.0
    @Published public var currentCoordinate: CLLocationCoordinate2D?
    @Published public var totalDistanceMeters: Double = 0.0
    @Published public var elapsedTimeSeconds: TimeInterval = 0
    @Published public var maxSpeedKmh: Double = 0.0
    @Published public var avgSpeedKmh: Double = 0.0
    @Published public var maxAltitude: Double = 0.0
    @Published public var minAltitude: Double = 0.0
    @Published public var elevationGain: Double = 0.0
    @Published public var recordedPoints: [TrackPointItem] = []
    @Published public var activeTrackTitle: String = ""

    private let clManager = CLLocationManager()
    private let altFilter = AltitudeFilter(maxVerticalVelocityMps: 8.0)
    private let kalmanFilter = KalmanLatLong(qMetresPerSecond: 2.5)

    private var timer: Timer?
    private var activeTrackingDuration: TimeInterval = 0
    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastAltitude: Double?
    private var currentTrackId: UUID = UUID()
    private var startTime: Date = Date()

    override public init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = 2.0
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false

        // Request initial permission and start standby GPS
        clManager.requestAlwaysAuthorization()
        clManager.startUpdatingLocation()
    }

    public func startStandbyGps() {
        clManager.startUpdatingLocation()
    }

    public func startTracking(title: String) {
        clManager.requestAlwaysAuthorization()
        altFilter.reset()
        kalmanFilter.reset()
        recordedPoints.removeAll()
        totalDistanceMeters = 0.0
        currentSpeedKmh = 0.0
        currentAltitude = 0.0
        maxSpeedKmh = 0.0
        avgSpeedKmh = 0.0
        maxAltitude = 0.0
        minAltitude = 0.0
        elevationGain = 0.0
        elapsedTimeSeconds = 0
        activeTrackingDuration = 0
        lastCoordinate = nil
        lastAltitude = nil
        currentTrackId = UUID()
        activeTrackTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recorded Track" : title
        startTime = Date()

        isTracking = true
        isPaused = false
        clManager.startUpdatingLocation()

        startTimer()
    }

    public func pauseTracking() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    public func resumeTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isTracking, !self.isPaused else { return }
            self.activeTrackingDuration += 1.0
            self.elapsedTimeSeconds = self.activeTrackingDuration

            // Recalculate avg speed
            if self.activeTrackingDuration > 0 && self.totalDistanceMeters > 0 {
                let hours = self.activeTrackingDuration / 3600.0
                self.avgSpeedKmh = (self.totalDistanceMeters / 1000.0) / hours
            }
        }
    }

    public func stopAndSaveTracking() -> TrackItem? {
        guard isTracking else { return nil }

        isTracking = false
        isPaused = false
        timer?.invalidate()
        timer = nil

        let endTime = Date()

        let savedTrack = TrackItem(
            id: currentTrackId,
            title: activeTrackTitle,
            startTime: startTime,
            endTime: endTime,
            totalDistanceMeters: totalDistanceMeters,
            maxSpeedKmh: maxSpeedKmh,
            avgSpeedKmh: avgSpeedKmh,
            maxAltitude: maxAltitude,
            minAltitude: minAltitude,
            elevationGain: elevationGain,
            pointCount: recordedPoints.count,
            isCompleted: true
        )

        // Save into local TrackStore
        TrackStore.shared.saveTrack(track: savedTrack, points: recordedPoints)

        // Auto export KMZ
        _ = KmzExporter.export(track: savedTrack, points: recordedPoints)

        // Keep standby GPS running for map & dashboard
        clManager.startUpdatingLocation()

        return savedTrack
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        isGpsActive = true
        accuracyMeters = loc.horizontalAccuracy

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
        let speed = max(0.0, loc.speed) * 3.6 // m/s to km/h

        currentCoordinate = smoothedCoord
        currentSpeedKmh = speed
        currentAltitude = filteredAlt

        // If actively tracking and not paused, accumulate track points & stats
        guard isTracking && !isPaused else { return }

        // Distance accumulator
        if let prev = lastCoordinate {
            let stepDist = KalmanLatLong.distance(from: prev, to: smoothedCoord)
            if stepDist > 1.5 {
                totalDistanceMeters += stepDist
                lastCoordinate = smoothedCoord
            }
        } else {
            lastCoordinate = smoothedCoord
        }

        // Elevation Gain accumulator
        if let prevAlt = lastAltitude {
            let diff = filteredAlt - prevAlt
            if diff > 0.5 { // Only consider positive ascents with minimum threshold
                elevationGain += diff
            }
        }
        lastAltitude = filteredAlt

        // Max speed
        if speed > maxSpeedKmh {
            maxSpeedKmh = speed
        }

        // Max & Min altitude
        if recordedPoints.isEmpty {
            maxAltitude = filteredAlt
            minAltitude = filteredAlt
        } else {
            if filteredAlt > maxAltitude { maxAltitude = filteredAlt }
            if filteredAlt < minAltitude { minAltitude = filteredAlt }
        }

        let point = TrackPointItem(
            trackId: currentTrackId,
            timestamp: now,
            latitude: smoothedCoord.latitude,
            longitude: smoothedCoord.longitude,
            altitude: filteredAlt,
            speedKmh: speed,
            accuracy: loc.horizontalAccuracy
        )
        recordedPoints.append(point)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}
