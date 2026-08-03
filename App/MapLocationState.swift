import Combine
import CoreLocation
import Foundation

struct MapSelection: Equatable {
    let coordinate: CLLocationCoordinate2D
    let source: MapSelectionSource
    let explicitName: String?
    let revision: UInt64

    static func == (lhs: MapSelection, rhs: MapSelection) -> Bool {
        lhs.coordinate.isApproximatelyEqual(to: rhs.coordinate)
            && lhs.source == rhs.source
            && lhs.explicitName == rhs.explicitName
            && lhs.revision == rhs.revision
    }
}

enum MapSelectionSource: Equatable {
    case initial
    case userPan
    case mapTap
    case realtime
    case search
    case favorite(UUID)
}

struct RealtimeLocationIntent: Equatable {
    let id: UInt64
    let selectionRevision: UInt64
}

struct MapCameraCommand: Equatable, Identifiable {
    enum Kind: Equatable {
        case focus(coordinate: CLLocationCoordinate2D, distanceMeters: CLLocationDistance)
        case zoom(factor: Double)

        var isZoom: Bool { if case .zoom = self { return true }; return false }

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case let (.focus(lhsCoordinate, lhsDistance), .focus(rhsCoordinate, rhsDistance)):
                return lhsCoordinate.isApproximatelyEqual(to: rhsCoordinate)
                    && lhsDistance == rhsDistance
            case let (.zoom(lhsFactor), .zoom(rhsFactor)):
                return lhsFactor == rhsFactor
            default:
                return false
            }
        }
    }

    let id: UInt64
    let kind: Kind
}

struct MapPlaceDescriptor: Equatable {
    var pointOfInterest: String?
    var streetAddress: String?
    var road: String?
    var neighborhood: String?
    var district: String?
    var city: String?
    var province: String?
    var country: String?

    init(
        pointOfInterest: String? = nil,
        streetAddress: String? = nil,
        road: String? = nil,
        neighborhood: String? = nil,
        district: String? = nil,
        city: String? = nil,
        province: String? = nil,
        country: String? = nil
    ) {
        self.pointOfInterest = pointOfInterest?.nonEmpty
        self.streetAddress = streetAddress?.nonEmpty
        self.road = road?.nonEmpty
        self.neighborhood = neighborhood?.nonEmpty
        self.district = district?.nonEmpty
        self.city = city?.nonEmpty
        self.province = province?.nonEmpty
        self.country = country?.nonEmpty
    }

    func displayName(viewportMeters: CLLocationDistance) -> String? {
        switch viewportMeters {
        case ..<1_000:
            return firstAvailable(pointOfInterest, streetAddress, road, neighborhood, district, districtCity, cityProvince, country)
        case ..<5_000:
            return firstAvailable(road, streetAddress, neighborhood, district, districtCity, cityProvince, country)
        case ..<12_000:
            return firstAvailable(neighborhood, district, districtCity, road, city, cityProvince, country)
        case ..<100_000:
            return firstAvailable(districtCity, city, cityProvince, province, country, neighborhoodCity)
        default:
            return firstAvailable(cityProvince, provinceCountry, city, province, country, districtCity)
        }
    }

    private var districtCity: String? { joinedDistinct(district, city) }
    private var neighborhoodCity: String? { joinedDistinct(neighborhood, city) }
    private var cityProvince: String? { joinedDistinct(city, province) }
    private var provinceCountry: String? { joinedDistinct(province, country) }

    private func firstAvailable(_ values: String?...) -> String? {
        values.compactMap { $0?.nonEmpty }.first
    }

    private func joinedDistinct(_ first: String?, _ second: String?) -> String? {
        let values = [first?.nonEmpty, second?.nonEmpty].compactMap { $0 }
        let unique = values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        return unique.isEmpty ? nil : unique.joined(separator: " · ")
    }
}

@MainActor
final class MapLocationState: ObservableObject {
    @Published private(set) var selection: MapSelection
    @Published private(set) var realtimeCoordinate: CLLocationCoordinate2D?
    @Published private(set) var realtimeLocation: CLLocation?
    @Published private(set) var cameraCommand: MapCameraCommand?
    @Published private(set) var viewportMeters: CLLocationDistance
    @Published private(set) var placeDescriptor: MapPlaceDescriptor?

    private var nextSelectionRevision: UInt64 = 0
    private var nextCameraCommandID: UInt64 = 0
    private var nextRealtimeIntentID: UInt64 = 0
    private var latestRealtimeIntentID: UInt64 = 0

    init(initialCoordinate: CLLocationCoordinate2D, initialViewportMeters: CLLocationDistance = 1_000) {
        viewportMeters = initialViewportMeters
        selection = MapSelection(
            coordinate: initialCoordinate,
            source: .initial,
            explicitName: nil,
            revision: nextSelectionRevision
        )
    }

    var displayName: String? {
        selection.explicitName?.nonEmpty ?? placeDescriptor?.displayName(viewportMeters: viewportMeters)
    }

    @discardableResult
    func selectUserMapCenter(_ coordinate: CLLocationCoordinate2D) -> UInt64 {
        guard !selection.coordinate.isApproximatelyEqual(to: coordinate) else {
            return selection.revision
        }
        return replaceSelection(coordinate: coordinate, source: .userPan, explicitName: nil, focusDistance: nil)
    }

    @discardableResult
    func selectMapTap(_ coordinate: CLLocationCoordinate2D) -> UInt64 {
        replaceSelection(coordinate: coordinate, source: .mapTap, explicitName: nil, focusDistance: viewportMeters)
    }

    @discardableResult
    func selectSearchResult(
        _ coordinate: CLLocationCoordinate2D,
        name: String
    ) -> UInt64 {
        replaceSelection(coordinate: coordinate, source: .search, explicitName: name, focusDistance: viewportMeters)
    }

    @discardableResult
    func selectFavorite(
        _ coordinate: CLLocationCoordinate2D,
        id: UUID,
        name: String
    ) -> UInt64 {
        replaceSelection(coordinate: coordinate, source: .favorite(id), explicitName: name, focusDistance: viewportMeters)
    }

    func beginRealtimeIntent() -> RealtimeLocationIntent {
        nextRealtimeIntentID &+= 1
        latestRealtimeIntentID = nextRealtimeIntentID
        return RealtimeLocationIntent(id: nextRealtimeIntentID, selectionRevision: selection.revision)
    }

    @discardableResult
    func acceptRealtimeLocation(
        _ coordinate: CLLocationCoordinate2D,
        intent: RealtimeLocationIntent
    ) -> Bool {
        realtimeCoordinate = coordinate
        guard intent.id == latestRealtimeIntentID,
              intent.selectionRevision == selection.revision else {
            return false
        }
        _ = replaceSelection(
            coordinate: coordinate,
            source: .realtime,
            explicitName: nil,
            focusDistance: nil
        )
        return true
    }

    func updateRealtimeLocation(_ location: CLLocation?) {
        guard let location else {
            realtimeLocation = nil
            realtimeCoordinate = nil
            return
        }
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0 else { return }
        if let current = realtimeLocation, current.timestamp > location.timestamp { return }
        realtimeLocation = location
        realtimeCoordinate = location.coordinate
    }

    func updateRealtimeCoordinate(_ coordinate: CLLocationCoordinate2D?) {
        realtimeCoordinate = coordinate
        if coordinate == nil { realtimeLocation = nil }
    }

    func updateExplicitName(_ name: String, forFavoriteID favoriteID: UUID) {
        guard selection.source == .favorite(favoriteID) else { return }
        selection = MapSelection(
            coordinate: selection.coordinate,
            source: selection.source,
            explicitName: name,
            revision: selection.revision
        )
    }

    func updateViewport(distanceMeters: CLLocationDistance) {
        viewportMeters = max(50, distanceMeters)
    }

    @discardableResult
    func acceptPlaceDescriptor(_ descriptor: MapPlaceDescriptor, selectionRevision: UInt64) -> Bool {
        guard selection.revision == selectionRevision, selection.explicitName == nil else { return false }
        placeDescriptor = descriptor
        return true
    }

    func focusSelection(distanceMeters: CLLocationDistance = 200) {
        issueCameraCommand(.focus(coordinate: selection.coordinate, distanceMeters: distanceMeters))
    }

    func zoom(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        issueCameraCommand(.zoom(factor: factor))
    }

    private func replaceSelection(
        coordinate: CLLocationCoordinate2D,
        source: MapSelectionSource,
        explicitName: String?,
        focusDistance: CLLocationDistance?
    ) -> UInt64 {
        nextSelectionRevision &+= 1
        placeDescriptor = nil
        selection = MapSelection(
            coordinate: coordinate,
            source: source,
            explicitName: explicitName?.nonEmpty,
            revision: nextSelectionRevision
        )
        if let focusDistance {
            issueCameraCommand(.focus(coordinate: coordinate, distanceMeters: focusDistance))
        }
        return nextSelectionRevision
    }

    private func issueCameraCommand(_ kind: MapCameraCommand.Kind) {
        nextCameraCommandID &+= 1
        cameraCommand = MapCameraCommand(id: nextCameraCommandID, kind: kind)
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

extension CLLocationCoordinate2D {
    func isApproximatelyEqual(to other: CLLocationCoordinate2D, tolerance: CLLocationDegrees = 0.000_001) -> Bool {
        abs(latitude - other.latitude) < tolerance && abs(longitude - other.longitude) < tolerance
    }
}

// MARK: - 持久化存储

enum ViewportStore {
    private static let key = "mapViewportMeters"
    static func save(_ meters: CLLocationDistance) {
        UserDefaults.standard.set(meters, forKey: key)
    }
    /// 取持久化缩放值；未存过返回 nil
    static func load() -> CLLocationDistance? {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : nil
    }
    /// 取持久化缩放值，取不到返回默认 1km 并立即存储
    static func loadOrDefault() -> CLLocationDistance {
        if let v = load() { return v }
        let fallback: CLLocationDistance = 1_000
        save(fallback)
        return fallback
    }
}

struct LastCoordinate {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var isValid: Bool { CLLocationCoordinate2DIsValid(coordinate) && (latitude != 0 || longitude != 0) }
}

enum LastCoordinateStore {
    private static let latKey = "lastMapLat"
    private static let lonKey = "lastMapLon"
    static func save(lat: Double, lon: Double) {
        UserDefaults.standard.set(lat, forKey: latKey)
        UserDefaults.standard.set(lon, forKey: lonKey)
    }
    /// 取持久化坐标，未存过或无效返回 nil
    static func load() -> LastCoordinate? {
        let c = LastCoordinate(
            latitude: UserDefaults.standard.double(forKey: latKey),
            longitude: UserDefaults.standard.double(forKey: lonKey)
        )
        return c.isValid ? c : nil
    }
}
