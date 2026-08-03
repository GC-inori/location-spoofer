import Foundation

@MainActor
final class LocationActionCoordinator: ObservableObject {
    @Published private(set) var state: LocationActionState = .idle
    @Published private(set) var virtualLocationEnabled = false
    @Published private(set) var message = ""

    private let proxy = ProxyManager.shared

    init() {
        self.virtualLocationEnabled = WlocSettingsStore.load()?.enabled == true
    }

    func apply(_ favorite: FavoriteLocation) async -> Bool {
        guard beginApply() else { return false }
        do {
            if !proxy.isRunning { try await proxy.start() }
            guard !Task.isCancelled else {
                finishCancelledApply()
                return false
            }
            return commit(favorite)
        } catch {
            failApply(error)
            return false
        }
    }

    /// Commits a target after SetupCoordinator has completed verification.
    /// This method is synchronous on MainActor so selection revision validation
    /// and the final settings/proxy write cannot be interleaved by a newer map event.
    func applyVerified(_ favorite: FavoriteLocation) -> Bool {
        guard proxy.isRunning else {
            failApply(ProxyError.startFailed)
            return false
        }
        guard beginApply() else { return false }
        return commit(favorite)
    }

    func clear() {
        guard !state.isBusy else { return }
        proxy.setCoords(lat: 0, lon: 0, enabled: false)
        WlocSettingsStore.clear()
        state = .idle
        virtualLocationEnabled = false
        message = "已恢复真实定位"
    }

    private func beginApply() -> Bool {
        guard !state.isBusy else { return false }
        state = .applyingLocation
        message = "启动代理…"
        return true
    }

    private func commit(_ favorite: FavoriteLocation) -> Bool {
        // MKMapView 在中国地区使用高德瓦片（GCJ-02），返回的坐标是 GCJ-02。
        // 但 Apple wloc 定位服务使用 WGS-84，因此写入代理前需要转换为 WGS-84。
        let wgs = CoordinateConverter.gcj02ToWgs84(lat: favorite.latitude, lon: favorite.longitude)
        WlocSettingsStore.save(WlocSettings(
            longitude: wgs.lon,
            latitude: wgs.lat,
            accuracy: favorite.accuracy,
            enabled: true
        ))
        proxy.setCoords(
            lat: wgs.lat,
            lon: wgs.lon,
            enabled: true,
            accuracy: favorite.accuracy
        )
        state = .idle
        virtualLocationEnabled = true
        message = "虚拟定位已开启"
        return true
    }

    private func finishCancelledApply() {
        state = .idle
        message = "已取消位置更新"
    }

    private func failApply(_ error: Error) {
        virtualLocationEnabled = false
        message = "启动失败"
        state = .failed(error.localizedDescription)
        RuntimeLogger.error("APP", "Location", "apply失败", error: error)
    }
}
