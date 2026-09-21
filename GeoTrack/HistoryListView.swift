import SwiftUI

public struct HistoryListView: View {
    @ObservedObject private var trackStore = TrackStore.shared
    @State private var trackToDelete: TrackItem?
    @State private var showDeleteAlert: Bool = false
    @State private var exportTrackTarget: TrackItem?
    @State private var showExportSheet: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if trackStore.tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("No Saved Tracks Yet")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Start recording a track from the home screen. It will automatically save here as KMZ when stopped.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(trackStore.tracks) { track in
                            NavigationLink(destination: RecordDetailView(track: track)) {
                                TrackRowCard(
                                    track: track,
                                    onShareKmz: {
                                        shareTrack(track, format: .kmz)
                                    },
                                    onExport: {
                                        exportTrackTarget = track
                                        showExportSheet = true
                                    },
                                    onDelete: {
                                        trackToDelete = track
                                        showDeleteAlert = true
                                    }
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Saved Recordings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Track?", isPresented: $showDeleteAlert, presenting: trackToDelete) { track in
            Button("Delete", role: .destructive) {
                trackStore.deleteTrack(track)
            }
            Button("Cancel", role: .cancel) {}
        } message: { track in
            Text("Are you sure you want to delete \"\(track.title)\"? This action cannot be undone.")
        }
        .confirmationDialog("Export Recording", isPresented: $showExportSheet, presenting: exportTrackTarget) { track in
            Button("Export & Share KMZ (Google Earth)") {
                shareTrack(track, format: .kmz)
            }
            Button("Export & Share GPX (GPS Exchange)") {
                shareTrack(track, format: .gpx)
            }
            Button("Export & Share CSV (Spreadsheet)") {
                shareTrack(track, format: .csv)
            }
            Button("Cancel", role: .cancel) {}
        } message: { track in
            Text("Choose export format for \"\(track.title)\":")
        }
        .onAppear {
            trackStore.loadTracks()
        }
    }

    private func shareTrack(_ track: TrackItem, format: ExportFormat) {
        let points = trackStore.getPoints(for: track.id)
        var fileURL: URL?
        switch format {
        case .kmz:
            fileURL = KmzExporter.export(track: track, points: points)
        case .gpx:
            fileURL = GpxExporter.export(track: track, points: points)
        case .csv:
            fileURL = CsvExporter.export(track: track, points: points)
        }
        if let url = fileURL {
            ShareSheetHelper.share(fileURL: url)
        }
    }
}

public struct TrackRowCard: View {
    public let track: TrackItem
    public let onShareKmz: () -> Void
    public let onExport: () -> Void
    public let onDelete: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title & Date Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(FormatUtils.formatDateTime(track.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundColor(.red.opacity(0.8))
                        .padding(6)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            // Metric Summary Chips
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(FormatUtils.formatDistance(track.totalDistanceMeters))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                let duration = track.endTime.timeIntervalSince(track.startTime)
                HStack(spacing: 4) {
                    Image(systemName: "stopwatch")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text(FormatUtils.formatDuration(duration))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)

                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    Text("\(FormatUtils.formatSpeed(track.avgSpeedKmh)) km/h")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(8)

                Spacer()
            }

            Divider()

            // Action Buttons Footer
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(track.pointCount) pts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Export Menu Button
                Button(action: onExport) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                        Text("Export")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())

                // Share KMZ Direct Button
                Button(action: onShareKmz) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share KMZ")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
