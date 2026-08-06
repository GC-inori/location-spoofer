import XCTest
import CoreLocation
import MapKit
@testable import PaopaoLocationSpoofer

@MainActor
final class MapLocationStateTests: XCTestCase {
    private let initial = CLLocationCoordinate2D(latitude: 22.544577, longitude: 113.94114)

    func testStaleRealtimeResultDoesNotReplaceNewerMapPan() {
        let state = MapLocationState(initialCoordinate: initial)
        let request = state.beginRealtimeIntent()

        state.selectUserMapCenter(.init(latitude: 31.23, longitude: 121.47))
        let accepted = state.acceptRealtimeLocation(
            .init(latitude: 39.90, longitude: 116.40),
            intent: request
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(state.selection.coordinate.latitude, 31.23, accuracy: 0.000001)
        XCTAssertEqual(state.realtimeCoordinate?.latitude ?? 0, 39.90, accuracy: 0.000001)
    }

    func testSearchAndFavoriteSelectionsOwnTheirNamesAndRevision() {
        let state = MapLocationState(initialCoordinate: initial)
        let originalRevision = state.selection.revision
        let favoriteID = UUID()

        state.selectSearchResult(.init(latitude: 31.23, longitude: 121.47), name: "外滩")
        XCTAssertGreaterThan(state.selection.revision, originalRevision)
        XCTAssertEqual(state.selection.source, .search)
        XCTAssertEqual(state.displayName, "外滩")

        state.selectFavorite(.init(latitude: 39.90, longitude: 116.40), id: favoriteID, name: "公司")
        XCTAssertEqual(state.selection.source, .favorite(favoriteID))
        XCTAssertEqual(state.displayName, "公司")

        state.updateViewport(distanceMeters: 300_000)
        XCTAssertEqual(state.displayName, "公司")
    }

    func testPanTapAndRealtimeClearOldFavoriteOwnership() {
        let state = MapLocationState(initialCoordinate: initial)
        state.selectFavorite(initial, id: UUID(), name: "旧收藏")

        state.selectMapTap(.init(latitude: 23, longitude: 114))
        XCTAssertEqual(state.selection.source, .mapTap)
        XCTAssertNil(state.selection.explicitName)

        state.selectUserMapCenter(.init(latitude: 24, longitude: 115))
        XCTAssertEqual(state.selection.source, .userPan)

        let intent = state.beginRealtimeIntent()
        XCTAssertTrue(state.acceptRealtimeLocation(.init(latitude: 25, longitude: 116), intent: intent))
        XCTAssertEqual(state.selection.source, .realtime)
    }


    func testUnchangedUserCenterDoesNotClearExplicitSearchName() {
        let state = MapLocationState(initialCoordinate: initial)
        state.selectSearchResult(initial, name: "深圳湾")
        let revision = state.selection.revision

        let returnedRevision = state.selectUserMapCenter(initial)

        XCTAssertEqual(returnedRevision, revision)
        XCTAssertEqual(state.selection.source, .search)
        XCTAssertEqual(state.displayName, "深圳湾")
    }

    func testRepeatedFocusCommandsHaveUniqueIDs() {
        let state = MapLocationState(initialCoordinate: initial)
        state.focusSelection(distanceMeters: 200)
        let first = state.cameraCommand
        state.focusSelection(distanceMeters: 200)
        let second = state.cameraCommand

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id)
    }

    func testZoomCommandDoesNotChangeSelectedCoordinate() {
        let state = MapLocationState(initialCoordinate: initial)
        let before = state.selection
        state.zoom(by: 0.5)

        XCTAssertEqual(state.selection.coordinate.latitude, before.coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(state.selection.coordinate.longitude, before.coordinate.longitude, accuracy: 0.000001)
        guard case .zoom(let factor) = state.cameraCommand?.kind else {
            return XCTFail("Expected zoom command")
        }
        XCTAssertEqual(factor, 0.5)
    }

    func testPlaceLabelChangesWithViewportDistance() {
        let place = MapPlaceDescriptor(
            pointOfInterest: "深圳湾体育中心",
            streetAddress: "滨海大道 3001 号",
            road: "滨海大道",
            neighborhood: "粤海街道",
            district: "南山区",
            city: "深圳市",
            province: "广东省",
            country: "中国"
        )

        XCTAssertEqual(place.displayName(viewportMeters: 300), "深圳湾体育中心")
        XCTAssertEqual(place.displayName(viewportMeters: 2_500), "滨海大道")
        XCTAssertEqual(place.displayName(viewportMeters: 8_000), "粤海街道")
        XCTAssertEqual(place.displayName(viewportMeters: 15_000), "南山区 · 深圳市")
        XCTAssertEqual(place.displayName(viewportMeters: 300_000), "深圳市 · 广东省")
    }

    func testDistrictFallbackStillChangesBetweenNeighborhoodAndCityZoom() {
        let place = MapPlaceDescriptor(
            pointOfInterest: "深圳湾公园",
            streetAddress: "望海路 1 号",
            road: "望海路",
            district: "南山区",
            city: "深圳市",
            province: "广东省",
            country: "中国"
        )

        XCTAssertEqual(place.displayName(viewportMeters: 8_000), "南山区")
        XCTAssertEqual(place.displayName(viewportMeters: 15_000), "南山区 · 深圳市")
        XCTAssertEqual(place.displayName(viewportMeters: 300_000), "深圳市 · 广东省")
    }

    func testPlaceLabelFallsBackAcrossMissingLevels() {
        let place = MapPlaceDescriptor(
            pointOfInterest: nil,
            streetAddress: nil,
            neighborhood: "科技园社区",
            district: nil,
            city: "深圳市",
            province: "广东省",
            country: "中国"
        )

        XCTAssertEqual(place.displayName(viewportMeters: 300), "科技园社区")
        XCTAssertEqual(place.displayName(viewportMeters: 15_000), "深圳市")
        XCTAssertEqual(place.displayName(viewportMeters: 300_000), "深圳市 · 广东省")
    }

    func testStaleGeocodeCannotReplaceCurrentDescriptor() {
        let state = MapLocationState(initialCoordinate: initial)
        let staleRevision = state.selection.revision
        state.selectUserMapCenter(.init(latitude: 31.23, longitude: 121.47))

        let accepted = state.acceptPlaceDescriptor(
            MapPlaceDescriptor(city: "旧城市"),
            selectionRevision: staleRevision
        )

        XCTAssertFalse(accepted)
        XCTAssertNil(state.placeDescriptor)
    }


    func testNativeRealtimeUpdateDoesNotMoveCurrentSelection() {
        let state = MapLocationState(initialCoordinate: initial)
        state.selectSearchResult(.init(latitude: 31.23, longitude: 121.47), name: "外滩")
        let revision = state.selection.revision

        state.updateRealtimeLocation(CLLocation(latitude: 30.42, longitude: 114.25))

        XCTAssertEqual(state.realtimeCoordinate?.latitude ?? 0, 30.42, accuracy: 0.000001)
        XCTAssertEqual(state.selection.coordinate.latitude, 31.23, accuracy: 0.000001)
        XCTAssertEqual(state.selection.revision, revision)
        XCTAssertEqual(state.selection.source, .search)
    }

    func testRealtimeIntentCanImmediatelyAcceptNativeLocation() {
        let state = MapLocationState(initialCoordinate: initial)
        let nativeLocation = CLLocation(latitude: 30.42, longitude: 114.25)
        state.updateRealtimeLocation(nativeLocation)
        let intent = state.beginRealtimeIntent()

        XCTAssertTrue(state.acceptRealtimeLocation(nativeLocation.coordinate, intent: intent))
        XCTAssertEqual(state.selection.source, .realtime)
        XCTAssertEqual(state.selection.coordinate.latitude, 30.42, accuracy: 0.000001)
        XCTAssertNil(state.cameraCommand, "realtime updates preserve the current camera unless the caller explicitly focuses it")
    }

    func testTileReprojectionPreservesSelectionIdentityAndIssuesFocus() {
        let state = MapLocationState(initialCoordinate: initial)
        let favoriteID = UUID()
        state.selectFavorite(.init(latitude: 22.55, longitude: 113.95), id: favoriteID, name: "测试收藏")
        let revision = state.selection.revision

        state.reprojectSelectionForTileChange(.init(latitude: 22.54, longitude: 113.94))

        XCTAssertEqual(state.selection.source, .favorite(favoriteID))
        XCTAssertEqual(state.selection.explicitName, "测试收藏")
        XCTAssertEqual(state.selection.revision, revision)
        XCTAssertEqual(state.selection.coordinate.latitude, 22.54, accuracy: 0.000001)
        guard case let .focus(coordinate, distanceMeters) = state.cameraCommand?.kind else {
            return XCTFail("Expected a focus command after tile reprojection")
        }
        XCTAssertEqual(coordinate.latitude, 22.54, accuracy: 0.000001)
        XCTAssertEqual(distanceMeters, state.viewportMeters)
    }

    func testZoomMathScalesBothAxesInTheSameDirection() {
        let span = MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.1)

        let zoomedIn = MapZoomMath.scaledSpan(span, factor: 0.5)
        XCTAssertEqual(zoomedIn.latitudeDelta, 0.1, accuracy: 0.000001)
        XCTAssertEqual(zoomedIn.longitudeDelta, 0.05, accuracy: 0.000001)

        let zoomedOut = MapZoomMath.scaledSpan(span, factor: 2)
        XCTAssertEqual(zoomedOut.latitudeDelta, 0.4, accuracy: 0.000001)
        XCTAssertEqual(zoomedOut.longitudeDelta, 0.2, accuracy: 0.000001)
    }

    func testViewportScaleLabelUsesReadableMetricUnits() {
        XCTAssertEqual(MapZoomMath.viewportScaleLabel(distanceMeters: 180), "180 m")
        XCTAssertEqual(MapZoomMath.viewportScaleLabel(distanceMeters: 2_500), "2.5 km")
        XCTAssertEqual(MapZoomMath.viewportScaleLabel(distanceMeters: 126_000), "126 km")
    }
}
