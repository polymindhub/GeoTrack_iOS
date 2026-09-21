import Foundation
import CoreLocation

public enum ExportFormat: String, CaseIterable, Identifiable {
    case kmz
    case gpx
    case csv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kmz: return "KMZ (Google Earth / 3D)"
        case .gpx: return "GPX (GPS Exchange)"
        case .csv: return "CSV (Spreadsheet / GIS)"
        }
    }

    public var fileExtension: String {
        return rawValue
    }
}

public struct TrackPointItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var trackId: UUID
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var speedKmh: Double
    public var accuracy: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(
        id: UUID = UUID(),
        trackId: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speedKmh: Double,
        accuracy: Double
    ) {
        self.id = id
        self.trackId = trackId
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedKmh = speedKmh
        self.accuracy = accuracy
    }
}

public struct TrackItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var totalDistanceMeters: Double
    public var maxSpeedKmh: Double
    public var avgSpeedKmh: Double
    public var maxAltitude: Double
    public var minAltitude: Double
    public var elevationGain: Double
    public var pointCount: Int
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date = Date(),
        totalDistanceMeters: Double = 0,
        maxSpeedKmh: Double = 0,
        avgSpeedKmh: Double = 0,
        maxAltitude: Double = 0,
        minAltitude: Double = 0,
        elevationGain: Double = 0,
        pointCount: Int = 0,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.totalDistanceMeters = totalDistanceMeters
        self.maxSpeedKmh = maxSpeedKmh
        self.avgSpeedKmh = avgSpeedKmh
        self.maxAltitude = maxAltitude
        self.minAltitude = minAltitude
        self.elevationGain = elevationGain
        self.pointCount = pointCount
        self.isCompleted = isCompleted
    }
}
