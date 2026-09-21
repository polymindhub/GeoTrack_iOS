import SwiftUI

public struct ReplayControls: View {
    public var isPlaying: Bool
    public var currentIndex: Int
    public var totalPoints: Int
    public var currentPoint: TrackPointItem?
    public var playbackSpeed: Double
    public var onPlayPauseToggle: () -> Void
    public var onSeek: (Int) -> Void
    public var onSpeedToggle: () -> Void
    public var onRestart: () -> Void

    public init(
        isPlaying: Bool,
        currentIndex: Int,
        totalPoints: Int,
        currentPoint: TrackPointItem?,
        playbackSpeed: Double,
        onPlayPauseToggle: @escaping () -> Void,
        onSeek: @escaping (Int) -> Void,
        onSpeedToggle: @escaping () -> Void,
        onRestart: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.currentIndex = currentIndex
        self.totalPoints = totalPoints
        self.currentPoint = currentPoint
        self.playbackSpeed = playbackSpeed
        self.onPlayPauseToggle = onPlayPauseToggle
        self.onSeek = onSeek
        self.onSpeedToggle = onSpeedToggle
        self.onRestart = onRestart
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Scrub Slider
            HStack(spacing: 10) {
                Text("\(currentIndex + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)

                Slider(
                    value: Binding<Double>(
                        get: { Double(currentIndex) },
                        set: { onSeek(Int($0)) }
                    ),
                    in: 0...Double(max(1, totalPoints - 1)),
                    step: 1
                )
                .accentColor(.blue)

                Text("\(totalPoints)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .leading)
            }

            // Controls Row
            HStack(spacing: 16) {
                // Restart Button
                Button(action: onRestart) {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // Play / Pause Main Button
                Button(action: onPlayPauseToggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: Color.blue.opacity(0.35), radius: 6, x: 0, y: 3)
                }

                // Speed Multiplier Button (1x -> 2x -> 5x -> 10x)
                Button(action: onSpeedToggle) {
                    Text("\(Int(playbackSpeed))x")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }

                Spacer()

                // Point Details summary
                if let pt = currentPoint {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(FormatUtils.formatTimeOnly(pt.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Text("\(FormatUtils.formatSpeed(pt.speedKmh)) km/h")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(FormatUtils.formatAltitude(pt.altitude)) m")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
