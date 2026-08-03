import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

enum MapZoomMath {
    private static let minimumDelta = 0.000_05
    private static let maximumLatitudeDelta = 170.0
    private static let maximumLongitudeDelta = 360.0

    static func scaledSpan(_ span: MKCoordinateSpan, factor: Double) -> MKCoordinateSpan {
        guard factor.isFinite, factor > 0 else { return span }
        return MKCoordinateSpan(
            latitudeDelta: min(max(span.latitudeDelta * factor, minimumDelta), maximumLatitudeDelta),
            longitudeDelta: min(max(span.longitudeDelta * factor, minimumDelta), maximumLongitudeDelta)
        )
    }

    static func viewportScaleLabel(distanceMeters: CLLocationDistance) -> String {
        let meters = max(0, distanceMeters)
        if meters < 1_000 {
            return "\(Int(meters.rounded())) m"
        }
        let kilometers = meters / 1_000
        if kilometers < 10 {
            return String(format: "%.1f km", kilometers)
        }
        return "\(Int(kilometers.rounded())) km"
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let selection: MapSelection
    let cameraCommand: MapCameraCommand?
    let onRealtimeLocationChanged: (CLLocation) -> Void
    let onUserCenterChanged: (CLLocationCoordinate2D, CLLocationDistance) -> Void
    let onViewportChanged: (CLLocationDistance) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onUserZoomChanged: ((CLLocationDistance) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        let initialDistance = ViewportStore.loadOrDefault()
        map.setRegion(
            MKCoordinateRegion(
                center: selection.coordinate,
                latitudinalMeters: initialDistance,
                longitudinalMeters: initialDistance
            ),
            animated: false
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.consume(cameraCommand, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        weak var map: MKMapView?

        private var lastConsumedCommandID: UInt64?
        private var activeCameraCommandID: UInt64?
        private var activeCommandIsZoom = false
        private var regionChangeWasUserDriven = false
        private var isPinchZoom = false

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        func consume(_ command: MapCameraCommand?, on map: MKMapView) {
            guard let command, command.id != lastConsumedCommandID else { return }
            lastConsumedCommandID = command.id
            activeCameraCommandID = command.id
            activeCommandIsZoom = command.kind.isZoom
            regionChangeWasUserDriven = false
            map.userTrackingMode = .none

            let region: MKCoordinateRegion
            switch command.kind {
            case let .focus(coordinate, _):
                // 保持当前 span 不变，只移动中心点，避免 latitudinalMeters
                // 与 visibleVerticalDistance 之间因屏幕宽高比引入 2x 漂移
                region = MKCoordinateRegion(center: coordinate, span: map.region.span)
            case let .zoom(factor):
                region = MKCoordinateRegion(
                    center: map.centerCoordinate,
                    span: MapZoomMath.scaledSpan(map.region.span, factor: factor)
                )
            }

            map.setRegion(region, animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map else { return }
            let point = gesture.location(in: map)
            parent.onMapTap(map.convert(point, toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location,
                  CLLocationCoordinate2DIsValid(location.coordinate),
                  location.horizontalAccuracy >= 0 else { return }
            parent.onRealtimeLocationChanged(location)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let activeRecognizers = ([mapView as UIView] + mapView.subviews)
                .compactMap(\.gestureRecognizers)
                .flatMap { $0 }
                .filter { recognizer in
                    recognizer.state == .began || recognizer.state == .changed
                }
            let hasActiveGesture = !activeRecognizers.isEmpty

            // Pinching updates the viewport/name granularity only. MapKit can
            // keep its pan recognizer active during a pinch, so only a pure pan
            // is allowed to replace the selected center coordinate.
            let hasActivePan = activeRecognizers.contains { $0 is UIPanGestureRecognizer }
            let hasActivePinch = activeRecognizers.contains { $0 is UIPinchGestureRecognizer }
            regionChangeWasUserDriven = hasActivePan && !hasActivePinch
            isPinchZoom = hasActivePinch
            if hasActiveGesture {
                activeCameraCommandID = nil
                activeCommandIsZoom = false
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let distance = visibleVerticalDistance(in: mapView)
            parent.onViewportChanged(distance)

            let userZoomed: Bool
            if activeCameraCommandID != nil {
                userZoomed = activeCommandIsZoom
                activeCameraCommandID = nil
                activeCommandIsZoom = false
            } else if isPinchZoom {
                userZoomed = true
                isPinchZoom = false
            } else {
                userZoomed = false
            }

            if userZoomed {
                parent.onUserZoomChanged?(distance)
            } else if regionChangeWasUserDriven {
                parent.onUserCenterChanged(mapView.centerCoordinate, distance)
            }

            regionChangeWasUserDriven = false
        }

        private func visibleVerticalDistance(in map: MKMapView) -> CLLocationDistance {
            let centerX = map.bounds.midX
            let north = map.convert(CGPoint(x: centerX, y: map.bounds.minY), toCoordinateFrom: map)
            let south = map.convert(CGPoint(x: centerX, y: map.bounds.maxY), toCoordinateFrom: map)
            let northLocation = CLLocation(latitude: north.latitude, longitude: north.longitude)
            let southLocation = CLLocation(latitude: south.latitude, longitude: south.longitude)
            let measured = northLocation.distance(from: southLocation)
            return measured.isFinite && measured > 0 ? measured : 1_000
        }
    }
}
