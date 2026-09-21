import SwiftUI
import MapKit

public struct TrackMapView: UIViewRepresentable {
    public var points: [TrackPointItem]
    public var currentLat: Double?
    public var currentLng: Double?
    public var selectedIndex: Int?
    public var isLiveTracking: Bool
    public var showMarkers: Bool = true
    public var onPointSelected: ((Int) -> Void)? = nil

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
        var parent: TrackMapView
        private var lastPointCount = 0
        private var currentPolyline: MKPolyline?

        init(_ parent: TrackMapView) {
            self.parent = parent
        }

        func updateMap(_ mapView: MKMapView) {
            let pts = parent.points

            // Update polyline if point count changed
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

                // Update static markers (Start, Finish, Max Speed, Max Alt)
                if parent.showMarkers && !parent.isLiveTracking && pts.count >= 2 {
                    updateStaticMarkers(mapView)
                }

                // Fit map to points bounds initially
                if pts.count >= 2 && !parent.isLiveTracking {
                    fitToBounds(mapView, points: pts)
                }
            }

            // Update Replay / Scrubber cursor annotation
            updateScrubAnnotation(mapView)

            // Live tracking auto center
            if parent.isLiveTracking, let lat = parent.currentLat, let lng = parent.currentLng {
                let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let region = MKCoordinateRegion(center: center, latitudinalMeters: 600, longitudinalMeters: 600)
                mapView.setRegion(region, animated: true)
            }
        }

        private func updateStaticMarkers(_ mapView: MKMapView) {
            // Remove existing static annotations
            let existing = mapView.annotations.filter { !($0 is ScrubAnnotation) && !($0 is MKUserLocation) }
            mapView.removeAnnotations(existing)

            guard let first = parent.points.first, let last = parent.points.last else { return }

            // Start marker
            let startAnn = TrackMarkerAnnotation(coordinate: first.coordinate, title: "Start", type: .start)
            mapView.addAnnotation(startAnn)

            // Finish marker
            let finishAnn = TrackMarkerAnnotation(coordinate: last.coordinate, title: "Finish", type: .finish)
            mapView.addAnnotation(finishAnn)

            // Max Speed marker
            if let maxSpeedPt = parent.points.max(by: { $0.speedKmh < $1.speedKmh }), maxSpeedPt.speedKmh > 0 {
                let speedAnn = TrackMarkerAnnotation(
                    coordinate: maxSpeedPt.coordinate,
                    title: String(format: "Max Speed: %.1f km/h", maxSpeedPt.speedKmh),
                    type: .maxSpeed
                )
                mapView.addAnnotation(speedAnn)
            }

            // Max Altitude marker
            if let maxAltPt = parent.points.max(by: { $0.altitude < $1.altitude }) {
                let altAnn = TrackMarkerAnnotation(
                    coordinate: maxAltPt.coordinate,
                    title: String(format: "Max Alt: %.0f m", maxAltPt.altitude),
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
                let newAnn = ScrubAnnotation(coordinate: coord)
                mapView.addAnnotation(newAnn)
            }
        }

        private func fitToBounds(_ mapView: MKMapView, points: [TrackPointItem]) {
            guard !points.isEmpty else { return }
            var minLat = points[0].latitude
            var maxLat = points[0].latitude
            var minLng = points[0].longitude
            var maxLng = points[0].longitude

            for p in points {
                if p.latitude < minLat { minLat = p.latitude }
                if p.latitude > maxLat { maxLat = p.latitude }
                if p.longitude < minLng { minLng = p.longitude }
                if p.longitude > maxLng { maxLng = p.longitude }
            }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2.0,
                longitude: (minLng + maxLng) / 2.0
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.005, (maxLng - minLng) * 1.4)
            )
            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            // Find closest track point
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

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0/255, green: 176/255, blue: 255/255, alpha: 0.95) // Cyan
                renderer.lineWidth = 4.5
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

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

            if let trackMarker = annotation as? TrackMarkerAnnotation {
                let identifier = "TrackMarkerAnnotationView"
                var markerView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if markerView == nil {
                    markerView = MKMarkerAnnotationView(annotation: trackMarker, reuseIdentifier: identifier)
                    markerView?.canShowCallout = true
                } else {
                    markerView?.annotation = trackMarker
                }

                switch trackMarker.type {
                case .start:
                    markerView?.markerTintColor = UIColor.systemGreen
                    markerView?.glyphImage = UIImage(systemName: "flag.fill")
                case .finish:
                    markerView?.markerTintColor = UIColor.systemRed
                    markerView?.glyphImage = UIImage(systemName: "checkerboard.rectangle")
                case .maxSpeed:
                    markerView?.markerTintColor = UIColor.systemCyan
                    markerView?.glyphImage = UIImage(systemName: "speedometer")
                case .maxAltitude:
                    markerView?.markerTintColor = UIColor.systemOrange
                    markerView?.glyphImage = UIImage(systemName: "mountain.2.fill")
                }
                return markerView
            }

            return nil
        }
    }
}

public enum TrackMarkerType {
    case start
    case finish
    case maxSpeed
    case maxAltitude
}

public class TrackMarkerAnnotation: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D
    public var title: String?
    public var type: TrackMarkerType

    public init(coordinate: CLLocationCoordinate2D, title: String, type: TrackMarkerType) {
        self.coordinate = coordinate
        self.title = title
        self.type = type
    }
}

public class ScrubAnnotation: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D

    public init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}
