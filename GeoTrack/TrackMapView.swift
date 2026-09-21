import SwiftUI
import MapKit

public struct TrackMapView: View {
    public var points: [TrackPointItem]
    public var currentLat: Double?
    public var currentLng: Double?
    public var selectedIndex: Int?
    public var isLiveTracking: Bool
    public var showMarkers: Bool
    public var onPointSelected: ((Int) -> Void)?

    @State private var fitTrigger: Int = 0
    @State private var centerTrigger: Int = 0

    public init(
        points: [TrackPointItem],
        currentLat: Double? = nil,
        currentLng: Double? = nil,
        selectedIndex: Int? = nil,
        isLiveTracking: Bool = false,
        showMarkers: Bool = true,
        onPointSelected: ((Int) -> Void)? = nil
    ) {
        self.points = points
        self.currentLat = currentLat
        self.currentLng = currentLng
        self.selectedIndex = selectedIndex
        self.isLiveTracking = isLiveTracking
        self.showMarkers = showMarkers
        self.onPointSelected = onPointSelected
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            TrackMapUIView(
                points: points,
                currentLat: currentLat,
                currentLng: currentLng,
                selectedIndex: selectedIndex,
                isLiveTracking: isLiveTracking,
                showMarkers: showMarkers,
                fitTrigger: fitTrigger,
                centerTrigger: centerTrigger,
                onPointSelected: onPointSelected
            )

            // Floating Controls: Zoom to Fit & Recenter
            VStack(spacing: 8) {
                // Zoom to Fit (فیت کردن کل مسیر در صفحه)
                if points.count >= 2 {
                    Button(action: {
                        fitTrigger += 1
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemBackground).opacity(0.92))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    }
                    .accessibilityLabel("Zoom to Fit")
                }

                // Recenter / Location button
                if isLiveTracking || (selectedIndex != nil && !points.isEmpty) {
                    Button(action: {
                        centerTrigger += 1
                    }) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemBackground).opacity(0.92))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    }
                    .accessibilityLabel("Center Location")
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }
}

// MARK: - Underlying MapKit UIView
public struct TrackMapUIView: UIViewRepresentable {
    public var points: [TrackPointItem]
    public var currentLat: Double?
    public var currentLng: Double?
    public var selectedIndex: Int?
    public var isLiveTracking: Bool
    public var showMarkers: Bool
    public var fitTrigger: Int
    public var centerTrigger: Int
    public var onPointSelected: ((Int) -> Void)?

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = isLiveTracking
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.layer.cornerRadius = 16
        mapView.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMap(mapView)
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TrackMapUIView
        private var lastPointCount = 0
        private var lastFitTrigger = 0
        private var lastCenterTrigger = 0
        private var currentPolyline: MKPolyline?
        private var currentMarkerSize: CGFloat = 36.0

        init(_ parent: TrackMapUIView) {
            self.parent = parent
        }

        func updateMap(_ mapView: MKMapView) {
            let pts = parent.points

            // 1. Update Polyline
            if pts.count != lastPointCount || currentPolyline == nil {
                lastPointCount = pts.count
                if let polyline = currentPolyline {
                    mapView.removeOverlay(polyline)
                }

                if pts.count >= 2 {
                    let coords = pts.map { $0.coordinate }
                    let polyline = MKPolyline(coordinates: coords, count: coords.count)
                    currentPolyline = polyline
                    mapView.addOverlay(polyline)
                }

                // Update static markers (Start, Finish, Max Speed, Max Altitude)
                if parent.showMarkers && !parent.isLiveTracking && pts.count >= 2 {
                    updateStaticMarkers(mapView)
                }

                // Initial fit to bounds for saved track
                if pts.count >= 2 && !parent.isLiveTracking && lastFitTrigger == 0 {
                    fitToBounds(mapView, points: pts)
                }
            }

            // 2. Handle Zoom to Fit trigger
            if parent.fitTrigger != lastFitTrigger {
                lastFitTrigger = parent.fitTrigger
                if pts.count >= 2 {
                    fitToBounds(mapView, points: pts)
                }
            }

            // 3. Handle Recenter trigger
            if parent.centerTrigger != lastCenterTrigger {
                lastCenterTrigger = parent.centerTrigger
                recenter(mapView)
            }

            // 4. Update Scrubber / Replay position
            updateScrubAnnotation(mapView)

            // 5. Live Tracking auto center (if active and not dragging)
            if parent.isLiveTracking, let lat = parent.currentLat, let lng = parent.currentLng {
                let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let region = MKCoordinateRegion(center: center, latitudinalMeters: 500, longitudinalMeters: 500)
                mapView.setRegion(region, animated: true)
            }
        }

        private func updateStaticMarkers(_ mapView: MKMapView) {
            let existing = mapView.annotations.filter { !($0 is ScrubAnnotation) && !($0 is MKUserLocation) }
            mapView.removeAnnotations(existing)

            guard let first = parent.points.first, let last = parent.points.last else { return }

            // 1. Start Marker
            let startAnn = TrackMarkerAnnotation(
                coordinate: first.coordinate,
                title: "Start (\(FormatUtils.formatTimeOnly(first.timestamp)))",
                subtitle: String(format: "Alt: %.0fm | Speed: %.1f km/h", first.altitude, first.speedKmh),
                type: .start
            )
            mapView.addAnnotation(startAnn)

            // 2. Finish Marker
            let finishAnn = TrackMarkerAnnotation(
                coordinate: last.coordinate,
                title: "Finish (\(FormatUtils.formatTimeOnly(last.timestamp)))",
                subtitle: String(format: "Alt: %.0fm | Speed: %.1f km/h", last.altitude, last.speedKmh),
                type: .finish
            )
            mapView.addAnnotation(finishAnn)

            // 3. Max Speed Marker (Speedometer Icon - حداکثر سرعت)
            if let maxSpeedPt = parent.points.max(by: { $0.speedKmh < $1.speedKmh }), maxSpeedPt.speedKmh > 0 {
                let speedAnn = TrackMarkerAnnotation(
                    coordinate: maxSpeedPt.coordinate,
                    title: String(format: "Max Speed: %.1f km/h", maxSpeedPt.speedKmh),
                    subtitle: String(format: "Alt: %.0fm | Time: %@", maxSpeedPt.altitude, FormatUtils.formatTimeOnly(maxSpeedPt.timestamp)),
                    type: .maxSpeed
                )
                mapView.addAnnotation(speedAnn)
            }

            // 4. Max Altitude Marker (Mountain Icon - حداکثر ارتفاع)
            if let maxAltPt = parent.points.max(by: { $0.altitude < $1.altitude }) {
                let altAnn = TrackMarkerAnnotation(
                    coordinate: maxAltPt.coordinate,
                    title: String(format: "Max Altitude: %.0f m", maxAltPt.altitude),
                    subtitle: String(format: "Speed: %.1f km/h | Time: %@", maxAltPt.speedKmh, FormatUtils.formatTimeOnly(maxAltPt.timestamp)),
                    type: .maxAltitude
                )
                mapView.addAnnotation(altAnn)
            }
        }

        private func updateScrubAnnotation(_ mapView: MKMapView) {
            let scrubAnnotations = mapView.annotations.compactMap { $0 as? ScrubAnnotation }

            var targetCoord: CLLocationCoordinate2D?
            if let idx = parent.selectedIndex, parent.points.indices.contains(idx) {
                targetCoord = parent.points[idx].coordinate
            } else if let lat = parent.currentLat, let lng = parent.currentLng {
                targetCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }

            guard let coord = targetCoord else {
                mapView.removeAnnotations(scrubAnnotations)
                return
            }

            if let existing = scrubAnnotations.first {
                UIView.animate(withDuration: 0.15) {
                    existing.coordinate = coord
                }
            } else {
                let scrub = ScrubAnnotation(coordinate: coord)
                mapView.addAnnotation(scrub)
            }
        }

        public func fitToBounds(_ mapView: MKMapView, points: [TrackPointItem]) {
            guard points.count >= 2 else { return }
            var mapRect = MKMapRect.null
            for pt in points {
                let point = MKMapPoint(pt.coordinate)
                mapRect = mapRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }

            // Fit with generous edge padding for labels and cards
            let insets = UIEdgeInsets(top: 48, left: 36, bottom: 48, right: 36)
            mapView.setVisibleMapRect(mapRect, edgePadding: insets, animated: true)
        }

        private func recenter(_ mapView: MKMapView) {
            if let idx = parent.selectedIndex, parent.points.indices.contains(idx) {
                let coord = parent.points[idx].coordinate
                mapView.setCenter(coord, animated: true)
            } else if let lat = parent.currentLat, let lng = parent.currentLng {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                mapView.setCenter(coord, animated: true)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            guard !parent.points.isEmpty else { return }
            var closestIdx = 0
            var minDistance = Double.greatestFiniteMagnitude

            for (i, pt) in parent.points.enumerated() {
                let dLat = pt.latitude - coord.latitude
                let dLng = pt.longitude - coord.longitude
                let dist = dLat * dLat + dLng * dLng
                if dist < minDistance {
                    minDistance = dist
                    closestIdx = i
                }
            }

            parent.onPointSelected?(closestIdx)
        }

        // MARK: - Dynamic Marker Sizing with Zoom
        public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let newSize = MarkerBadgeHelper.calculateMarkerSize(for: mapView)
            guard abs(newSize - currentMarkerSize) >= 2.0 else { return }
            currentMarkerSize = newSize

            for annotation in mapView.annotations {
                guard let trackMarker = annotation as? TrackMarkerAnnotation,
                      let view = mapView.view(for: trackMarker) else { continue }
                view.image = MarkerBadgeHelper.badge(for: trackMarker.type, size: currentMarkerSize)
                view.bounds = CGRect(x: 0, y: 0, width: currentMarkerSize, height: currentMarkerSize)
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0/255, green: 176/255, blue: 255/255, alpha: 0.95) // Vibrant Cyan
                renderer.lineWidth = 4.5
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // Replay scrubber dot
            if let scrub = annotation as? ScrubAnnotation {
                let identifier = "ScrubAnnotationView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: scrub, reuseIdentifier: identifier)
                    view?.canShowCallout = false

                    let dot = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
                    dot.backgroundColor = UIColor.systemYellow
                    dot.layer.cornerRadius = 11
                    dot.layer.borderWidth = 3
                    dot.layer.borderColor = UIColor.white.cgColor
                    dot.layer.shadowColor = UIColor.black.cgColor
                    dot.layer.shadowOpacity = 0.4
                    dot.layer.shadowOffset = CGSize(width: 0, height: 2)
                    dot.layer.shadowRadius = 4
                    view?.addSubview(dot)
                    view?.frame = dot.frame
                } else {
                    view?.annotation = scrub
                }
                return view
            }

            // Custom dynamic-sized badges for Start, Finish, Max Speed, Max Altitude
            if let trackMarker = annotation as? TrackMarkerAnnotation {
                let identifier = "TrackMarkerBadgeView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                let size = MarkerBadgeHelper.calculateMarkerSize(for: mapView)

                if view == nil {
                    view = MKAnnotationView(annotation: trackMarker, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = trackMarker
                }

                view?.image = MarkerBadgeHelper.badge(for: trackMarker.type, size: size)
                view?.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                view?.centerOffset = CGPoint(x: 0, y: 0)

                return view
            }

            return nil
        }
    }
}

// MARK: - Marker Types & Annotations
public enum TrackMarkerType {
    case start
    case finish
    case maxSpeed
    case maxAltitude
}

public class TrackMarkerAnnotation: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D
    public var title: String?
    public var subtitle: String?
    public var type: TrackMarkerType

    public init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String? = nil, type: TrackMarkerType) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.type = type
    }
}

public class ScrubAnnotation: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D

    public init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

// MARK: - Custom Dynamic Vector Badge Generator
public class MarkerBadgeHelper {
    private static var cache: [String: UIImage] = [:]

    public static func calculateMarkerSize(for mapView: MKMapView) -> CGFloat {
        let delta = mapView.region.span.latitudeDelta
        // Latitude delta ranges from 0.001 (zoomed in street) to 0.20 (regional)
        let clamped = max(0.001, min(0.20, delta))
        let ratio = 1.0 - ((clamped - 0.001) / 0.199)
        let size = 26.0 + (CGFloat(ratio) * 20.0) // 26pt to 46pt
        return round(size / 2.0) * 2.0 // Quantize to 2pt steps
    }

    public static func badge(for type: TrackMarkerType, size: CGFloat) -> UIImage {
        let key = "\(type)_\(Int(size))"
        if let cached = cache[key] {
            return cached
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = size / 2.0
            let radius = (size / 2.0) - 2.0

            // Drop shadow
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)

            switch type {
            case .maxSpeed:
                // Vibrant Speed Amber / Orange (#FF6D00)
                let bgColor = UIColor(red: 255/255, green: 109/255, blue: 0/255, alpha: 1.0)
                cg.setFillColor(bgColor.cgColor)
                cg.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
                cg.restoreGState()

                // Crisp white border
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(size * 0.07)
                cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))

                // Speedometer dial arc
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(size * 0.075)
                cg.setLineCap(.round)
                let arcRect = CGRect(x: center * 0.45, y: center * 0.45, width: center * 1.1, height: center * 1.1)
                cg.addArc(center: CGPoint(x: center, y: center * 1.0), radius: center * 0.55, startAngle: .pi * 0.8, endAngle: .pi * 0.2, clockwise: false)
                cg.strokePath()

                // Speedometer needle (yellow) pointing to high speed
                cg.setStrokeColor(UIColor(red: 255/255, green: 235/255, blue: 59/255, alpha: 1.0).cgColor)
                cg.setLineWidth(size * 0.065)
                cg.move(to: CGPoint(x: center, y: center * 1.05))
                cg.addLine(to: CGPoint(x: center + (center * 0.45), y: center * 0.65))
                cg.strokePath()

                // Center pivot white dot
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: center - (size * 0.06), y: (center * 1.05) - (size * 0.06), width: size * 0.12, height: size * 0.12))

            case .maxAltitude:
                // Mountain Emerald Teal (#00897B)
                let bgColor = UIColor(red: 0/255, green: 137/255, blue: 123/255, alpha: 1.0)
                cg.setFillColor(bgColor.cgColor)
                cg.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
                cg.restoreGState()

                // Crisp white border
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(size * 0.07)
                cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))

                // Mountain peaks silhouette
                cg.setFillColor(UIColor.white.cgColor)

                // Main peak (tall, left)
                cg.beginPath()
                cg.move(to: CGPoint(x: center * 0.40, y: center * 1.40))
                cg.addLine(to: CGPoint(x: center * 0.90, y: center * 0.55))
                cg.addLine(to: CGPoint(x: center * 1.45, y: center * 1.40))
                cg.closePath()
                cg.fillPath()

                // Secondary peak (right, smaller)
                cg.beginPath()
                cg.move(to: CGPoint(x: center * 1.05, y: center * 1.40))
                cg.addLine(to: CGPoint(x: center * 1.40, y: center * 0.80))
                cg.addLine(to: CGPoint(x: center * 1.70, y: center * 1.40))
                cg.closePath()
                cg.fillPath()

                // Ridge separator line
                cg.setStrokeColor(bgColor.cgColor)
                cg.setLineWidth(1.5)
                cg.move(to: CGPoint(x: center * 0.90, y: center * 0.55))
                cg.addLine(to: CGPoint(x: center * 1.05, y: center * 1.40))
                cg.move(to: CGPoint(x: center * 1.40, y: center * 0.80))
                cg.addLine(to: CGPoint(x: center * 1.45, y: center * 1.40))
                cg.strokePath()

            case .finish:
                // Finish Checkered Racing Flag badge
                let bgColor = UIColor(red: 33/255, green: 33/255, blue: 33/255, alpha: 1.0)
                cg.setFillColor(bgColor.cgColor)
                cg.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
                cg.restoreGState()

                // White border
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(size * 0.07)
                cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))

                // Checkered grid in center
                let flagW = size * 0.52
                let flagH = size * 0.36
                let flagLeft = center - (flagW / 2.0)
                let flagTop = center - (flagH / 2.0)
                let rows = 3
                let cols = 4
                let cw = flagW / CGFloat(cols)
                let ch = flagH / CGFloat(rows)

                for r in 0..<rows {
                    for c in 0..<cols {
                        let isBlack = (r + c) % 2 == 0
                        cg.setFillColor(isBlack ? UIColor.black.cgColor : UIColor.white.cgColor)
                        cg.fill(CGRect(x: flagLeft + CGFloat(c) * cw, y: flagTop + CGFloat(r) * ch, width: cw, height: ch))
                    }
                }

            case .start:
                // Start Blue Dot / Pin Badge (Google Maps Blue #1A73E8)
                let bgColor = UIColor(red: 26/255, green: 115/255, blue: 232/255, alpha: 1.0)
                cg.setFillColor(bgColor.cgColor)
                cg.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
                cg.restoreGState()

                // Crisp white ring
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(size * 0.08)
                cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))

                // Inner white start arrow/dot
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: center - (size * 0.16), y: center - (size * 0.16), width: size * 0.32, height: size * 0.32))
            }
        }

        cache[key] = img
        return img
    }
}
