import XCTest
@testable import PaopaoLocationSpoofer

final class FavoriteLocationStoreTests: XCTestCase {
    func testSavingFavoriteSelectsItAndPersistsAcrossStoreInstances() {
        let suite = "FavoriteLocationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoriteLocationStore(defaults: defaults)
        let favorite = store.save(name: "深圳湾", latitude: 22.494, longitude: 113.951, accuracy: 20)

        XCTAssertEqual(store.selectedFavoriteID, favorite.id)
        XCTAssertEqual(FavoriteLocationStore(defaults: defaults).selectedFavorite?.name, "深圳湾")
    }

    func testMapConfigurationNeverRequestsRealUserLocation() {
        XCTAssertFalse(MapConfiguration.default.showsUserLocation)
        XCTAssertFalse(MapConfiguration.default.allowsCurrentLocationRequest)
    }
}
