import SwiftUI

public struct RecordDetailView: View {
    public let track: TrackItem
    @Environment(\.dismiss) private var dismiss

    @State private var points: [TrackPointItem] = []
    @State private var replayIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0
    @State private var showExportDialog: Bool = false
    @State private var timer: Timer?

    public init(track: TrackItem) {
        self.track = track
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Live Replay / Scrub Telemetry Banner
                if let currentPoint = currentPoint {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .foregroundColor(.cyan)
                            Text("\(FormatUtils.formatSpeed(currentPoint.speedKmh)) km/h")
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "mountain.2.fill")
                                .foregroundColor(.orange)
                            Text("\(FormatUtils.formatAltitude(currentPoint.altitude)) m")
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Text(FormatUtils.formatTimeOnly(currentPoint.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }

                // Interactive Map
                VStack {
                    TrackMapView(
                        points: points,
                        selectedIndex: replayIndex,
                        isLiveTracking: false,
                        showMarkers: true,
                        onPointSelected: { idx in
                            seekTo(idx)
                        }
                    )
                    .frame(height: 280)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                }
                .padding(.horizontal, 16)

                // Interactive Altitude & Speed Diagram
                VStack {
                    AltitudeSpeedChart(
                        points: points,
                        selectedIndex: replayIndex,
                        onPointSelected: { idx in
                            seekTo(idx)
                        }
                    )
                    .frame(height: 210)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .padding(.horizontal, 16)

                // Replay Player Controls
                if !points.isEmpty {
                    ReplayControls(
                        isPlaying: isPlaying,
                        currentIndex: replayIndex,
                        totalPoints: points.count,
                        currentPoint: currentPoint,
                        playbackSpeed: playbackSpeed,
                        onPlayPauseToggle: { togglePlayPause() },
                        onSeek: { idx in seekTo(idx) },
                        onSpeedToggle: { togglePlaybackSpeed() },
                        onRestart: { restartReplay() }
                    )
                    .padding(.horizontal, 16)
                }

                // Overall Track Summary Statistics
                VStack(alignment: .leading, spacing: 12) {
                    Text("Track Statistics")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            MetricDetailCard(
                                title: "Distance",
                                value: FormatUtils.formatDistance(track.totalDistanceMeters),
                                unit: "",
                                icon: "point.topleft.down.curvedto.point.bottomright.up",
                                color: .blue
                            )
                            let duration = track.endTime.timeIntervalSince(track.startTime)
                            MetricDetailCard(
                                title: "Duration",
                                value: FormatUtils.formatDuration(duration),
                                unit: "",
                                icon: "stopwatch",
                                color: .purple
                            )
                        }

                        HStack(spacing: 12) {
                            MetricDetailCard(
                                title: "Avg Speed",
                                value: FormatUtils.formatSpeed(track.avgSpeedKmh),
                                unit: "km/h",
                                icon: "speedometer",
                                color: .green
                            )
                            MetricDetailCard(
                                title: "Max Speed",
                                value: FormatUtils.formatSpeed(track.maxSpeedKmh),
                                unit: "km/h",
                                icon: "bolt.fill",
                                color: .cyan
                            )
                        }

                        HStack(spacing: 12) {
                            MetricDetailCard(
                                title: "Elev. Gain",
                                value: FormatUtils.formatAltitude(track.elevationGain),
                                unit: "m",
                                icon: "arrow.up.right",
                                color: .orange
                            )
                            MetricDetailCard(
                                title: "Max Altitude",
                                value: FormatUtils.formatAltitude(track.maxAltitude),
                                unit: "m",
                                icon: "mountain.2.fill",
                                color: .orange
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 30)
            }
            .padding(.top, 10)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(track.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Export Button (KMZ, GPX, CSV)
                Button(action: { showExportDialog = true }) {
                    Image(systemName: "arrow.down.doc")
                }

                // Direct Share KMZ
                Button(action: { shareKmz() }) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            loadPoints()
        }
        .onDisappear {
            stopTimer()
        }
        .confirmationDialog("Export Recording", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("Export & Share KMZ (Google Earth)") {
                shareKmz()
            }
            Button("Export & Share GPX (GPS Exchange)") {
                shareGpx()
            }
            Button("Export & Share CSV (Spreadsheet)") {
                shareCsv()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose your preferred export format for offline analysis, GIS tools or spreadsheets:")
        }
    }

    private var currentPoint: TrackPointItem? {
        guard !points.isEmpty, points.indices.contains(replayIndex) else { return nil }
        return points[replayIndex]
    }

    private func loadPoints() {
        points = TrackStore.shared.getPoints(for: track.id)
        replayIndex = 0
    }

    private func togglePlayPause() {
        if isPlaying {
            pauseReplay()
        } else {
            startReplay()
        }
    }

    private func startReplay() {
        guard !points.isEmpty else { return }
        isPlaying = true
        if replayIndex >= points.count - 1 {
            replayIndex = 0
        }

        startTimer()
    }

    private func pauseReplay() {
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        let interval = max(0.04, 0.4 / playbackSpeed)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            if replayIndex < points.count - 1 {
                replayIndex += 1
            } else {
                pauseReplay()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func seekTo(_ index: Int) {
        guard !points.isEmpty else { return }
        replayIndex = max(0, min(points.count - 1, index))
    }

    private func togglePlaybackSpeed() {
        let speeds = [1.0, 2.0, 5.0, 10.0]
        if let currentIdx = speeds.firstIndex(of: playbackSpeed) {
            playbackSpeed = speeds[(currentIdx + 1) % speeds.count]
        } else {
            playbackSpeed = 1.0
        }
        if isPlaying {
            startTimer()
        }
    }

    private func restartReplay() {
        seekTo(0)
        startReplay()
    }

    private func shareKmz() {
        if let url = KmzExporter.export(track: track, points: points) {
            ShareSheetHelper.share(fileURL: url)
        }
    }

    private func shareGpx() {
        if let url = GpxExporter.export(track: track, points: points) {
            ShareSheetHelper.share(fileURL: url)
        }
    }

    private func shareCsv() {
        if let url = CsvExporter.export(track: track, points: points) {
            ShareSheetHelper.share(fileURL: url)
        }
    }
}

public struct MetricDetailCard: View {
    public let title: String
    public let value: String
    public let unit: String
    public let icon: String
    public let color: Color

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
