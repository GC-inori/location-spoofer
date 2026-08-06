import XCTest
import CoreLocation
@testable import PaopaoLocationSpoofer

final class FavoriteLocationStoreTests: XCTestCase {
    func testSavingFavoriteSelectsItAndPersistsAcrossStoreInstances() {
        let suite = "FavoriteLocationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoriteLocationStore(defaults: defaults)
        let favorite = store.save(
            name: "深圳湾",
            mapCoordinate: .init(latitude: 22.494, longitude: 113.951),
            mapCoordinateSystem: .gcj02,
            accuracy: 20
        )

        XCTAssertEqual(store.selectedFavoriteID, favorite.id)
        XCTAssertEqual(FavoriteLocationStore(defaults: defaults).selectedFavorite?.name, "深圳湾")
    }

    func testFavoriteStoresBothFormsAndSelectsMatchingPairWithoutReadConversion() {
        let suite = "FavoriteLocationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wgs = CLLocationCoordinate2D(latitude: 22.491_438, longitude: 113.945_702)
        let favorite = FavoriteLocation(
            name: "深圳湾",
            coordinatePair: .init(mapCoordinate: wgs, mapCoordinateSystem: .wgs84),
            accuracy: 20
        )

        XCTAssertEqual(favorite.coordinatePair.coordinate(for: .wgs84).latitude, wgs.latitude, accuracy: 0.000_000_1)
        XCTAssertEqual(favorite.coordinatePair.coordinate(for: .wgs84).longitude, wgs.longitude, accuracy: 0.000_000_1)
        XCTAssertNotEqual(favorite.coordinatePair.gcj02.latitude, wgs.latitude)
        XCTAssertNotEqual(favorite.coordinatePair.gcj02.longitude, wgs.longitude)
    }

    func testLegacyFavoriteIsUpgradedAsDomesticGCJAndRewritten() throws {
        let suite = "FavoriteLocationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = LegacyFavoritePayload(
            id: id,
            name: "旧收藏",
            latitude: 22.544_577,
            longitude: 113.941_14,
            accuracy: 25,
            createdAt: createdAt
        )
        defaults.set(try JSONEncoder().encode([payload]), forKey: "favorite_locations")

        let store = FavoriteLocationStore(defaults: defaults)
        XCTAssertTrue(store.favorites[0].isLegacyCoordinateRecord)
        XCTAssertEqual(store.favorites[0].coordinatePair.gcj02.latitude, payload.latitude, accuracy: 0.000_000_1)
        XCTAssertNotEqual(store.favorites[0].coordinatePair.wgs84.longitude, payload.longitude)

        try store.migrateLegacyCoordinates()
        let reloaded = FavoriteLocationStore(defaults: defaults)
        XCTAssertEqual(reloaded.favorites[0].id, id)
        XCTAssertEqual(reloaded.favorites[0].name, "旧收藏")
        XCTAssertFalse(reloaded.favorites[0].isLegacyCoordinateRecord)
    }

    func testOverseasPairUsesIdentityConversion() {
        let eiffelTower = CoordinateConverter.coordinatePair(lat: 48.858_37, lon: 2.294_481, mapCoordinateSystem: .wgs84)

        XCTAssertEqual(eiffelTower.wgs84.latitude, eiffelTower.gcj02.latitude, accuracy: 0.000_000_1)
        XCTAssertEqual(eiffelTower.wgs84.longitude, eiffelTower.gcj02.longitude, accuracy: 0.000_000_1)
    }

    func testDomesticMapCoordinateMatchesPreviouslyActivatedWGS84Value() {
        let gcj = CLLocationCoordinate2D(latitude: 22.544_577, longitude: 113.941_14)
        let pair = CoordinatePair(mapCoordinate: gcj, mapCoordinateSystem: .gcj02)

        XCTAssertTrue(pair.matchesWGS84(
            latitude: pair.wgs84.latitude,
            longitude: pair.wgs84.longitude
        ))
        XCTAssertFalse(pair.matchesWGS84(latitude: gcj.latitude, longitude: gcj.longitude))
    }

    func testMapConfigurationNeverRequestsRealUserLocation() {
        XCTAssertFalse(MapConfiguration.default.showsUserLocation)
        XCTAssertFalse(MapConfiguration.default.allowsCurrentLocationRequest)
    }

}

private struct LegacyFavoritePayload: Encodable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let accuracy: Int
    let createdAt: Date
}
