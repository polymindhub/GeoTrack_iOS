import Foundation

public class TrackStore: ObservableObject {
    public static let shared = TrackStore()

    @Published public var tracks: [TrackItem] = []

    private let fileManager = FileManager.default
    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var tracksIndexUrl: URL {
        documentsDir.appendingPathComponent("tracks_index.json")
    }

    public init() {
        loadTracks()
    }

    public func loadTracks() {
        guard fileManager.fileExists(atPath: tracksIndexUrl.path) else {
            self.tracks = []
            return
        }
        do {
            let data = try Data(contentsOf: tracksIndexUrl)
            let decoded = try JSONDecoder().decode([TrackItem].self, from: data)
            self.tracks = decoded.sorted(by: { $0.startTime > $1.startTime })
        } catch {
            print("Failed to load tracks: \(error)")
            self.tracks = []
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: tracksIndexUrl, options: .atomic)
        } catch {
            print("Failed to save tracks index: \(error)")
        }
    }

    private func pointsUrl(for trackId: UUID) -> URL {
        documentsDir.appendingPathComponent("points_\(trackId.uuidString).json")
    }

    public func saveTrack(track: TrackItem, points: [TrackPointItem]) {
        var updated = tracks.filter { $0.id != track.id }
        updated.insert(track, at: 0)
        self.tracks = updated.sorted(by: { $0.startTime > $1.startTime })
        saveIndex()

        do {
            let data = try JSONEncoder().encode(points)
            try data.write(to: pointsUrl(for: track.id), options: .atomic)
        } catch {
            print("Failed to save points: \(error)")
        }
    }

    public func getPoints(for trackId: UUID) -> [TrackPointItem] {
        let url = pointsUrl(for: trackId)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([TrackPointItem].self, from: data)
        } catch {
            print("Failed to load points for \(trackId): \(error)")
            return []
        }
    }

    public func deleteTrack(_ track: TrackItem) {
        tracks.removeAll(where: { $0.id == track.id })
        saveIndex()
        let url = pointsUrl(for: track.id)
        try? fileManager.removeItem(at: url)
    }
}
