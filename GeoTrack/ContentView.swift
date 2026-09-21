import SwiftUI

struct ContentView: View {
    @StateObject private var locManager = LocationManager()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("GeoTrack iOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(locManager.isTracking ? "Recording Active (Background GPS)" : "Ready to Start")
                        .font(.subheadline)
                        .foregroundColor(locManager.isTracking ? .green : .secondary)
                }
                .padding(.top, 20)

                // Metric Cards Grid
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        MetricCardView(
                            title: "Speed",
                            value: String(format: "%.1f", locManager.currentSpeedKmh),
                            unit: "km/h",
                            icon: "speedometer"
                        )

                        MetricCardView(
                            title: "Filtered Altitude",
                            value: String(format: "%.0f", locManager.currentAltitude),
                            unit: "m",
                            icon: "mountain.2"
                        )
                    }

                    HStack(spacing: 16) {
                        MetricCardView(
                            title: "Distance",
                            value: String(format: "%.2f", locManager.totalDistanceMeters / 1000.0),
                            unit: "km",
                            icon: "point.topleft.down.curvedto.point.bottomright.up"
                        )

                        let totalSeconds = Int(locManager.elapsedTimeSeconds)
                        let minutes = totalSeconds / 60
                        let seconds = totalSeconds % 60
                        MetricCardView(
                            title: "Duration",
                            value: String(format: "%02d:%02d", minutes, seconds),
                            unit: "",
                            icon: "stopwatch"
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Action Button
                Button(action: {
                    if locManager.isTracking {
                        locManager.stopTracking()
                    } else {
                        locManager.startTracking()
                    }
                }) {
                    HStack {
                        Image(systemName: locManager.isTracking ? "stop.fill" : "play.fill")
                        Text(locManager.isTracking ? "Stop Recording" : "Start Recording")
                            .fontWeight(.semibold)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(locManager.isTracking ? Color.red : Color.blue)
                    .cornerRadius(18)
                    .shadow(color: (locManager.isTracking ? Color.red : Color.blue).opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}
