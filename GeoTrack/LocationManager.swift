import Foundation
import CoreLocation
import Combine

public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var isTracking: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var isGpsActive: Bool = false
    @Published public var isSimulationMode: Bool = false
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
    private var simulationTimer: Timer?
    private var simulationStep: Int = 0
    private var activeTrackingDuration: TimeInterval = 0
    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastAltitude: Double?
    private var lastUpdateTime: Date?
    private var currentTrackId: UUID = UUID()
    private var startTime: Date = Date()

    override public init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = 1.0
        
        #if !targetEnvironment(simulator)
        clManager.allowsBackgroundLocationUpdates = true
        #endif
        clManager.pausesLocationUpdatesAutomatically = false

        // Request permission
        if clManager.authorizationStatus == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        } else {
            clManager.startUpdatingLocation()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            clManager.startUpdatingLocation()
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    public func startStandbyGps() {
        clManager.startUpdatingLocation()
    }

    public func startTracking(title: String) {
        clManager.requestWhenInUseAuthorization()
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
        lastUpdateTime = nil
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
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    public func resumeTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        startTimer()
        if isSimulationMode {
            startSimulationTimer()
        }
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
        stopSimulation()

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

    // MARK: - CoreLocation Delegate
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // If simulation mode is active, ignore static simulator coordinates
        guard !isSimulationMode, let loc = locations.last else { return }
        isGpsActive = true
        accuracyMeters = loc.horizontalAccuracy > 0 ? loc.horizontalAccuracy : 5.0

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
            accuracy: accuracyMeters,
            timestamp: now
        )
        let smoothedCoord = CLLocationCoordinate2D(latitude: smoothed.lat, longitude: smoothed.lng)

        // 3. Determine Speed (Handle simulator returning -1 by calculating displacement speed)
        var speed: Double = 0.0
        if loc.speed >= 0 {
            speed = loc.speed * 3.6
        } else if let prev = lastCoordinate, let prevTime = lastUpdateTime {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0.5 {
                let dist = KalmanLatLong.distance(from: prev, to: smoothedCoord)
                speed = (dist / dt) * 3.6
            }
        }

        processUpdate(coord: smoothedCoord, altitude: filteredAlt, speedKmh: speed, accuracy: accuracyMeters, timestamp: now)
    }

    private func processUpdate(coord: CLLocationCoordinate2D, altitude: Double, speedKmh: Double, accuracy: Double, timestamp: Date) {
        currentCoordinate = coord
        currentSpeedKmh = speedKmh
        currentAltitude = altitude

        // If actively tracking and not paused, accumulate track points & stats
        guard isTracking && !isPaused else { return }

        // Distance accumulator
        if let prev = lastCoordinate {
            let stepDist = KalmanLatLong.distance(from: prev, to: coord)
            if stepDist > 1.2 {
                totalDistanceMeters += stepDist
                lastCoordinate = coord
            }
        } else {
            lastCoordinate = coord
        }

        // Elevation Gain accumulator
        if let prevAlt = lastAltitude {
            let diff = altitude - prevAlt
            if diff > 0.4 {
                elevationGain += diff
            }
        }
        lastAltitude = altitude
        lastUpdateTime = timestamp

        // Max speed
        if speedKmh > maxSpeedKmh {
            maxSpeedKmh = speedKmh
        }

        // Max & Min altitude
        if recordedPoints.isEmpty {
            maxAltitude = altitude
            minAltitude = altitude
        } else {
            if altitude > maxAltitude { maxAltitude = altitude }
            if altitude < minAltitude { minAltitude = altitude }
        }

        let point = TrackPointItem(
            trackId: currentTrackId,
            timestamp: timestamp,
            latitude: coord.latitude,
            longitude: coord.longitude,
            altitude: altitude,
            speedKmh: speedKmh,
            accuracy: accuracy
        )
        recordedPoints.append(point)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }

    // MARK: - Simulation Mode (For Web Appetize.io & Simulator Testing)
    public func startSimulation(title: String = "Simulated Drive") {
        isSimulationMode = true
        simulationStep = 0
        isGpsActive = true
        startTracking(title: title)
        startSimulationTimer()
    }

    public func stopSimulation() {
        isSimulationMode = false
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    private func startSimulationTimer() {
        simulationTimer?.invalidate()
        
        // Base start coordinate: Scenic mountain pass (Tehran / Tochal road)
        var baseLat = 35.8150
        var baseLng = 51.4120
        var baseAlt = 1580.0

        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isTracking, !self.isPaused else { return }
            self.simulationStep += 1

            // Move ~14 meters every second (approx 50 km/h)
            let step = Double(self.simulationStep)
            let latOffset = (step * 0.00012) + (sin(step * 0.15) * 0.00004)
            let lngOffset = (step * 0.00016) + (cos(step * 0.15) * 0.00004)
            let currentCoord = CLLocationCoordinate2D(latitude: baseLat + latOffset, longitude: baseLng + lngOffset)

            // Ascend altitude with natural variation
            let currentAlt = baseAlt + (step * 1.8) + (sin(step * 0.3) * 3.0)

            // Vary speed between 44 and 68 km/h
            let currentSpeed = 48.0 + (sin(step * 0.25) * 14.0) + (cos(step * 0.5) * 4.0)

            self.processUpdate(
                coord: currentCoord,
                altitude: currentAlt,
                speedKmh: max(0.0, currentSpeed),
                accuracy: 3.5,
                timestamp: Date()
            )
        }
    }
}
