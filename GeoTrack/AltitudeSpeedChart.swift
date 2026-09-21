import SwiftUI

public struct AltitudeSpeedChart: View {
    public var points: [TrackPointItem]
    public var selectedIndex: Int?
    public var onPointSelected: (Int) -> Void

    public init(
        points: [TrackPointItem],
        selectedIndex: Int? = nil,
        onPointSelected: @escaping (Int) -> Void
    ) {
        self.points = points
        self.selectedIndex = selectedIndex
        self.onPointSelected = onPointSelected
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Header Legend & Live Scrubber Tooltip Badge
            HStack(spacing: 12) {
                // Speed Legend
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 8, height: 8)
                    Text("Speed (km/h)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                }

                // Altitude Legend
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Altitude (m)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }

                Spacer()

                // Live Scrubber Tooltip
                if let idx = selectedIndex, idx in points.indices {
                    let pt = points[idx]
                    HStack(spacing: 4) {
                        Text("\(FormatUtils.formatTimeOnly(pt.timestamp)) | \(FormatUtils.formatSpeed(pt.speedKmh)) km/h | \(FormatUtils.formatAltitude(pt.altitude)) m")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 6)

            if points.count < 2 {
                VStack {
                    Spacer()
                    Text("Recording points to build graph...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Interactive Chart Canvas
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    let smoothed = smoothAltitudes(points)
                    let maxAlt = max(smoothed.max() ?? 100, (smoothed.min() ?? 0) + 10)
                    let minAlt = smoothed.min() ?? 0
                    let altRange = max(10.0, maxAlt - minAlt)

                    let maxSpd = max(30.0, points.map { $0.speedKmh }.max() ?? 30.0)
                    let minSpd = 0.0
                    let spdRange = max(10.0, maxSpd - minSpd)

                    ZStack(alignment: .topLeading) {
                        // Background horizontal grid lines
                        VStack {
                            Divider().opacity(0.3)
                            Spacer()
                            Divider().opacity(0.3)
                            Spacer()
                            Divider().opacity(0.3)
                        }

                        // Altitude Filled Area
                        Path { path in
                            for (i, alt) in smoothed.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(points.count - 1)
                                let normalized = CGFloat((alt - minAlt) / altRange)
                                let y = h - (normalized * (h - 16)) - 8
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Altitude Stroke Line
                        Path { path in
                            for (i, alt) in smoothed.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(points.count - 1)
                                let normalized = CGFloat((alt - minAlt) / altRange)
                                let y = h - (normalized * (h - 16)) - 8
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                        // Speed Stroke Line
                        Path { path in
                            for (i, pt) in points.enumerated() {
                                let x = w * CGFloat(i) / CGFloat(points.count - 1)
                                let normalized = CGFloat((pt.speedKmh - minSpd) / spdRange)
                                let y = h - (normalized * (h - 16)) - 8
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                        // Scrub Cursor Line and Dots
                        if let idx = selectedIndex, idx in points.indices {
                            let x = w * CGFloat(idx) / CGFloat(points.count - 1)
                            let alt = smoothed[idx]
                            let normAlt = CGFloat((alt - minAlt) / altRange)
                            let yAlt = h - (normAlt * (h - 16)) - 8

                            let spd = points[idx].speedKmh
                            let normSpd = CGFloat((spd - minSpd) / spdRange)
                            let ySpd = h - (normSpd * (h - 16)) - 8

                            // Vertical dashed line
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: h))
                            }
                            .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                            // Indicator Dots
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: yAlt)

                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 8, height: 8)
                                .position(x: x, y: ySpd)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clampedX = max(0, min(value.location.x, w))
                                let ratio = clampedX / max(1, w)
                                let targetIdx = Int(round(ratio * CGFloat(points.count - 1)))
                                let boundedIdx = max(0, min(points.count - 1, targetIdx))
                                onPointSelected(boundedIdx)
                            }
                    )
                }
            }
        }
        .padding(10)
    }

    private func smoothAltitudes(_ points: [TrackPointItem]) -> [Double] {
        guard points.count > 2 else { return points.map { $0.altitude } }
        var result: [Double] = []
        for i in 0..<points.count {
            let start = max(0, i - 2)
            let end = min(points.count - 1, i + 2)
            let slice = points[start...end].map { $0.altitude }
            let avg = slice.reduce(0.0, +) / Double(slice.count)
            result.append(avg)
        }
        return result
    }
}
