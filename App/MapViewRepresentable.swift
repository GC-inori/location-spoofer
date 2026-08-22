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

final class SelectedLocationAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(coordinate: CLLocationCoordinate2D, title: String? = nil, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

final class SelectedLocationAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "SelectedLocationAnnotationView"

    private let pinImageView = UIImageView()
    private let bubbleView = UIView()
    private let titleLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupViews()
    }

    private func setupViews() {
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -14)

        // 1. 较小尺寸图钉（26pt）
        let pinSize: CGFloat = 26
        let sizeCfg = UIImage.SymbolConfiguration(pointSize: pinSize, weight: .semibold)
        let paletteCfg = UIImage.SymbolConfiguration(paletteColors: [.white, .red])
        let pinImage = UIImage(systemName: "mappin", withConfiguration: sizeCfg.applying(paletteCfg))
        pinImageView.image = pinImage
        pinImageView.contentMode = .scaleAspectFit
        pinImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pinImageView)

        // 2. 图钉下方的详细位置描述气泡
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        bubbleView.layer.cornerRadius = 8
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowOpacity = 0.22
        bubbleView.layer.shadowRadius = 4
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 2)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = UIColor.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        bubbleView.addSubview(titleLabel)

        addSubview(bubbleView)

        NSLayoutConstraint.activate([
            pinImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            pinImageView.topAnchor.constraint(equalTo: topAnchor),
            pinImageView.widthAnchor.constraint(equalToConstant: pinSize),
            pinImageView.heightAnchor.constraint(equalToConstant: pinSize),

            bubbleView.topAnchor.constraint(equalTo: pinImageView.bottomAnchor, constant: 4),
            bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -4),
            titleLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8)
        ])
    }

    func configure(with annotation: MKAnnotation?) {
        self.annotation = annotation
        if let customAnno = annotation as? SelectedLocationAnnotation,
           let text = customAnno.title, !text.isEmpty {
            titleLabel.text = text
            bubbleView.isHidden = false
        } else {
            bubbleView.isHidden = true
        }
        setNeedsLayout()
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let selection: MapSelection
    let addressDescription: String?
    let initialViewportMeters: CLLocationDistance
    let cameraCommand: MapCameraCommand?
    let onRealtimeLocationChanged: (CLLocation) -> Void
    let onViewportChanged: (CLLocationDistance) -> Void
    let onMapLongPress: (CLLocationCoordinate2D) -> Void
    let onUserZoomChanged: ((CLLocationDistance) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.register(
            SelectedLocationAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: SelectedLocationAnnotationView.reuseIdentifier
        )

        let initialDistance = max(50, initialViewportMeters)
        map.setRegion(
            MKCoordinateRegion(
                center: selection.coordinate,
                latitudinalMeters: initialDistance,
                longitudinalMeters: initialDistance
            ),
            animated: false
        )

        // 指南针按钮放置在左上角
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            compass.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 68)
        ])

        // 长按手势选点
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        map.addGestureRecognizer(longPress)

        context.coordinator.map = map
        context.coordinator.updateAnnotation(on: map, coordinate: selection.coordinate, address: addressDescription)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.consume(cameraCommand, on: map)
        context.coordinator.updateAnnotation(on: map, coordinate: selection.coordinate, address: addressDescription)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        weak var map: MKMapView?

        private var lastConsumedCommandID: UInt64?
        private var activeCameraCommandID: UInt64?
        private var activeCommandIsZoom = false
        private var isPinchZoom = false
        private var selectedAnnotation: SelectedLocationAnnotation?
        private var userDotDiameter: CGFloat = 20
        private var lastForwardedRealtimeTimestamp: Date?

        init(parent: MapViewRepresentable) {
            self.parent = parent
        }

        func updateAnnotation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D, address: String?) {
            if let anno = selectedAnnotation {
                if !anno.coordinate.isApproximatelyEqual(to: coordinate) {
                    anno.coordinate = coordinate
                }
                anno.title = address
                if let view = mapView.view(for: anno) as? SelectedLocationAnnotationView {
                    view.configure(with: anno)
                }
            } else {
                let anno = SelectedLocationAnnotation(coordinate: coordinate, title: address)
                selectedAnnotation = anno
                mapView.addAnnotation(anno)
            }
        }

        func consume(_ command: MapCameraCommand?, on map: MKMapView) {
            guard let command, command.id != lastConsumedCommandID else { return }
            lastConsumedCommandID = command.id
            activeCameraCommandID = command.id
            activeCommandIsZoom = command.kind.isZoom
            map.userTrackingMode = .none

            let region: MKCoordinateRegion
            switch command.kind {
            case let .focus(coordinate, distance):
                let meters = max(100, distance)
                region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                )
            case let .zoom(factor):
                region = MKCoordinateRegion(
                    center: map.centerCoordinate,
                    span: MapZoomMath.scaledSpan(map.region.span, factor: factor)
                )
            }

            map.setRegion(region, animated: true)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let point = gesture.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            // 触觉反馈
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.prepare()
            feedback.impactOccurred()
            parent.onMapLongPress(coord)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let selectedAnno = annotation as? SelectedLocationAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: SelectedLocationAnnotationView.reuseIdentifier,
                for: selectedAnno
            ) as? SelectedLocationAnnotationView ?? SelectedLocationAnnotationView(
                annotation: selectedAnno,
                reuseIdentifier: SelectedLocationAnnotationView.reuseIdentifier
            )
            view.configure(with: selectedAnno)
            return view
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view.annotation is MKUserLocation {
                userDotDiameter = view.bounds.width
                for sub in view.subviews where sub.bounds.width > userDotDiameter + 4 {
                    sub.isHidden = true
                }
            }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = visibleUserLocationSample(userLocation) else { return }
            guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0 else { return }
            forwardRealtimeLocation(location)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let activeRecognizers = ([mapView as UIView] + mapView.subviews)
                .compactMap(\.gestureRecognizers)
                .flatMap { $0 }
                .filter { $0.state == .began || $0.state == .changed }
            let hasActiveGesture = !activeRecognizers.isEmpty
            let hasActivePan = activeRecognizers.contains { $0 is UIPanGestureRecognizer }
            let hasActivePinch = activeRecognizers.contains { $0 is UIPinchGestureRecognizer }
            _ = hasActivePan
            isPinchZoom = hasActivePinch
            if hasActiveGesture {
                activeCameraCommandID = nil
                activeCommandIsZoom = false
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let distance = visibleVerticalDistance(in: mapView)
            parent.onViewportChanged(distance)

            if let ul = visibleUserLocationSample(mapView.userLocation),
               CLLocationCoordinate2DIsValid(ul.coordinate), ul.horizontalAccuracy >= 0 {
                if lastForwardedRealtimeTimestamp.map({ ul.timestamp > $0 }) ?? true {
                    forwardRealtimeLocation(ul)
                }
            }

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
            }
        }

        private func forwardRealtimeLocation(_ location: CLLocation) {
            lastForwardedRealtimeTimestamp = location.timestamp
            parent.onRealtimeLocationChanged(location)
        }

        private func visibleUserLocationSample(_ userLocation: MKUserLocation) -> CLLocation? {
            guard let native = userLocation.location else { return nil }
            return CLLocation(
                coordinate: userLocation.coordinate,
                altitude: native.altitude,
                horizontalAccuracy: native.horizontalAccuracy,
                verticalAccuracy: native.verticalAccuracy,
                course: native.course,
                speed: native.speed,
                timestamp: native.timestamp
            )
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