import SwiftUI
import CoreLocation

public struct ContentView: View {
    @StateObject private var locManager = LocationManager()
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @State private var showStartDialog: Bool = false
    @State private var trackTitleInput: String = ""
    @State private var showStopConfirmDialog: Bool = false
    @State private var selectedScrubIndex: Int? = nil
    @State private var toastMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        // 1. Primary Telemetry Metrics Row (Speed & Altitude)
                        HStack(spacing: 12) {
                            MetricCardView(
                                title: "Speed",
                                value: FormatUtils.formatSpeed(locManager.currentSpeedKmh),
                                unit: "km/h",
                                icon: "speedometer",
                                accentColor: .cyan
                            )

                            MetricCardView(
                                title: "Altitude",
                                value: FormatUtils.formatAltitude(locManager.currentAltitude),
                                unit: "m",
                                icon: "mountain.2.fill",
                                accentColor: .orange
                            )
                        }
                        .padding(.horizontal, 16)

                        // 2. Secondary Metrics Row (Distance & Duration)
                        HStack(spacing: 12) {
                            MetricCardView(
                                title: "Distance",
                                value: FormatUtils.formatDistance(locManager.totalDistanceMeters),
                                unit: "",
                                icon: "point.topleft.down.curvedto.point.bottomright.up",
                                accentColor: .blue
                            )

                            MetricCardView(
                                title: "Duration",
                                value: FormatUtils.formatDuration(locManager.elapsedTimeSeconds),
                                unit: "",
                                icon: "stopwatch",
                                accentColor: .purple
                            )
                        }
                        .padding(.horizontal, 16)

                        // 3. Speed Analytics Row (Avg Speed & Max Speed)
                        HStack(spacing: 12) {
                            MetricCardView(
                                title: "Avg Speed",
                                value: FormatUtils.formatSpeed(locManager.avgSpeedKmh),
                                unit: "km/h",
                                icon: "speedometer",
                                accentColor: .green
                            )

                            MetricCardView(
                                title: "Max Speed",
                                value: FormatUtils.formatSpeed(locManager.maxSpeedKmh),
                                unit: "km/h",
                                icon: "bolt.fill",
                                accentColor: .cyan
                            )
                        }
                        .padding(.horizontal, 16)

                        // 4. Live Map Container
                        VStack {
                            TrackMapView(
                                points: locManager.recordedPoints,
                                currentLat: locManager.currentCoordinate?.latitude,
                                currentLng: locManager.currentCoordinate?.longitude,
                                selectedIndex: selectedScrubIndex,
                                isLiveTracking: true,
                                showMarkers: false,
                                onPointSelected: { idx in
                                    selectedScrubIndex = idx
                                }
                            )
                            .frame(height: 260)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                        }
                        .padding(.horizontal, 16)

                        // 5. Live Altitude & Speed Interactive Diagram Container
                        VStack {
                            AltitudeSpeedChart(
                                points: locManager.recordedPoints,
                                selectedIndex: selectedScrubIndex,
                                onPointSelected: { idx in
                                    selectedScrubIndex = idx
                                }
                            )
                            .frame(height: 190)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                        }
                        .padding(.horizontal, 16)

                        // 6. Action Recording Controls (When actively tracking)
                        if locManager.isTracking {
                            VStack {
                                HStack(spacing: 12) {
                                    // Pause / Resume Button
                                    Button(action: {
                                        if locManager.isPaused {
                                            locManager.resumeTracking()
                                        } else {
                                            locManager.pauseTracking()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: locManager.isPaused ? "play.fill" : "pause.fill")
                                            Text(locManager.isPaused ? "Resume" : "Pause")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color(.tertiarySystemGroupedBackground))
                                        .foregroundColor(.primary)
                                        .cornerRadius(14)
                                    }

                                    // Stop & Auto-Save Button
                                    Button(action: {
                                        showStopConfirmDialog = true
                                    }) {
                                        HStack {
                                            Image(systemName: "stop.fill")
                                            Text("Stop & Auto-Save")
                                                .fontWeight(.bold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(14)
                                        .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 3)
                                    }
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(18)
                            }
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.top, 8)
                }

                // Toast Notification Banner
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(20)
                            .shadow(radius: 6)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Top Leading: GPS Status
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusIndicatorColor)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("GeoTrack")
                                .font(.headline)
                                .fontWeight(.bold)

                            Text(statusSubtitle)
                                .font(.system(size: 10))
                                .foregroundColor(locManager.isTracking ? .blue : .secondary)
                        }
                    }
                }

                // Top Trailing: Record Button + Day/Night Toggle + History
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Record Action Button
                    if !locManager.isTracking {
                        Button(action: {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MMM dd HH:mm"
                            trackTitleInput = "Track \(formatter.string(from: Date()))"
                            showStartDialog = true
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Record")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(10)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Button(action: {
                                if locManager.isPaused {
                                    locManager.resumeTracking()
                                } else {
                                    locManager.pauseTracking()
                                }
                            }) {
                                Image(systemName: locManager.isPaused ? "play.fill" : "pause.fill")
                                    .foregroundColor(.blue)
                            }

                            Button(action: {
                                showStopConfirmDialog = true
                            }) {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // Day / Night Toggle
                    Button(action: {
                        isDarkMode.toggle()
                    }) {
                        Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(.primary)
                    }

                    // History Folder Button
                    NavigationLink(destination: HistoryListView()) {
                        Image(systemName: "folder")
                            .foregroundColor(.primary)
                    }
                }
            }
            .alert("Start New Track", isPresented: $showStartDialog) {
                TextField("Track Name", text: $trackTitleInput)
                Button("Start") {
                    locManager.startTracking(title: trackTitleInput)
                    showToast("Recording started in background")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Track will record in background with live speed, altitude, and location. It will automatically save as KMZ when stopped.")
            }
            .confirmationDialog("Stop Recording?", isPresented: $showStopConfirmDialog, titleVisibility: .visible) {
                Button("Stop & Save KMZ", role: .destructive) {
                    if let _ = locManager.stopAndSaveTracking() {
                        showToast("Track stopped & automatically saved as KMZ!")
                    }
                }
                Button("Continue Recording", role: .cancel) {}
            } message: {
                Text("Recording will be stopped and automatically exported as KMZ format for Google Earth and GIS software.")
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    private var statusIndicatorColor: Color {
        if locManager.isTracking {
            return .green
        } else if locManager.isGpsActive && locManager.currentCoordinate != nil {
            return Color(red: 0, green: 0.85, blue: 0.3)
        } else {
            return .gray
        }
    }

    private var statusSubtitle: String {
        if locManager.isTracking {
            return locManager.isPaused ? "Recording Paused" : "Recording Active (Background)"
        } else if locManager.isGpsActive && locManager.currentCoordinate != nil {
            return String(format: "GPS Active • ±%.0fm", locManager.accuracyMeters)
        } else {
            return "Connecting to GPS..."
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
}

public struct MetricCardView: View {
    public let title: String
    public let value: String
    public let unit: String
    public let icon: String
    public let accentColor: Color

    public init(title: String, value: String, unit: String, icon: String, accentColor: Color = .blue) {
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.accentColor = accentColor
    }

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
                    .foregroundColor(accentColor)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
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
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
