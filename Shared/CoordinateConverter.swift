import Foundation
import CoreLocation
import MapKit

/// GCJ-02 (火星坐标) ↔ WGS-84 坐标转换。
///
/// MKMapView 根据实时定位动态切换瓦片源：中国境内用高德 GCJ-02，境外用 Apple WGS-84。
/// App 内部统一以 WGS-84 存储，仅在地图交互时按当前瓦片类型双向转换。
enum CoordinateConverter {
    // 椭球参数 (Krasovsky 1940)
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    /// 坐标类型
    enum CoordType: String {
        case gcj02 = "GCJ-02"
        case wgs84 = "WGS-84"
    }

    // MARK: - 全局瓦片类型

    struct TileTypeChange: Equatable {
        let previous: CoordType
        let current: CoordType
    }

    /// 当前地图瓦片坐标系。探测不可用时使用国内 GCJ-02 作为兜底。
    @MainActor static var currentTileType = CoordType.gcj02
    @MainActor private static var lastTileCheck: Date?
    @MainActor private static var tileCheckPending = false

    /// Uses one fixed, known reference result as a best-effort tile heuristic.
    ///
    /// MapKit does not expose a supported public API for its active tile CRS. A
    /// timeout, empty response, or search error is therefore not evidence for
    /// WGS-84: those cases deliberately fall back to the domestic GCJ-02 mode.
    @MainActor
    @discardableResult
    static func detectTileByFixedGeocode(force: Bool = false) async -> TileTypeChange? {
        guard !tileCheckPending else {
            RuntimeLogger.info("APP", "坐标转换", "瓦片检测: 跳过(进行中)")
            return nil
        }
        if !force, let last = lastTileCheck, -last.timeIntervalSinceNow < 30 {
            RuntimeLogger.info("APP", "坐标转换", "瓦片检测: 跳过(缓存\(Int(-last.timeIntervalSinceNow))s)")
            return nil
        }

        tileCheckPending = true
        defer { tileCheckPending = false }
        RuntimeLogger.info("APP", "坐标转换", "瓦片检测: 发起查询", details: [
            "force": String(force),
            "当前瓦片": currentTileType.rawValue
        ])

        let probeResult = await fixedGeocodeProbe()
        guard !Task.isCancelled else { return nil }
        lastTileCheck = Date()

        let nextType: CoordType
        switch probeResult {
        case let .response(name, count):
            nextType = name == "林士街" ? .gcj02 : .wgs84
            RuntimeLogger.info("APP", "坐标转换", "瓦片检测完成 → \(nextType.rawValue)", details: [
                "结果数": String(count),
                "命中锚点": String(nextType == .gcj02)
            ])
        case .unavailable:
            nextType = .gcj02
            RuntimeLogger.warning("APP", "坐标转换", "瓦片检测无结果，回退 GCJ-02")
        case .timedOut:
            nextType = .gcj02
            RuntimeLogger.warning("APP", "坐标转换", "瓦片检测超时，回退 GCJ-02")
        case .cancelled:
            return nil
        }

        guard nextType != currentTileType else { return nil }
        let change = TileTypeChange(previous: currentTileType, current: nextType)
        currentTileType = nextType
        return change
    }

    /// Reprojects a map-display coordinate after the tile heuristic changes.
    /// The physical coordinate remains WGS-84 in between the two display modes.
    static func reprojectDisplayCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        from previous: CoordType,
        to current: CoordType
    ) -> CLLocationCoordinate2D {
        guard previous != current else { return coordinate }
        let stored = storedCoordinate(lat: coordinate.latitude, lon: coordinate.longitude, tileType: previous)
        let display = displayCoordinate(lat: stored.lat, lon: stored.lon, tileType: current)
        return CLLocationCoordinate2D(latitude: display.lat, longitude: display.lon)
    }

    private static func fixedGeocodeProbe() async -> TileProbeResult {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "22.283819, 114.158439"
        let search = MKLocalSearch(request: request)
        let resolver = TileProbeResolver()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let timeout = DispatchWorkItem {
                    search.cancel()
                    resolver.resolve(.timedOut)
                }
                resolver.install(continuation, timeout: timeout)
                guard !resolver.isResolved else { return }
                search.start { response, error in
                    guard error == nil else {
                        resolver.resolve(.unavailable)
                        return
                    }
                    resolver.resolve(.response(
                        name: response?.mapItems.first?.name ?? "",
                        count: response?.mapItems.count ?? 0
                    ))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            }
        }, onCancel: {
            search.cancel()
            resolver.resolve(.cancelled)
        })
    }

    // MARK: - 存取转换

    /// 地图坐标 → WGS-84 存储
    @MainActor
    static func toStored(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        let stored = storedCoordinate(lat: lat, lon: lon, tileType: currentTileType)
        RuntimeLogger.info("APP", "坐标转换", "地图坐标已规范为 WGS-84", details: [
            "转换": String(currentTileType == .gcj02 && usesGCJ02ServiceArea(lat: lat, lon: lon))
        ])
        return stored
    }

    /// WGS-84 存储 → 当前地图瓦片坐标系（显示用）
    @MainActor
    static func toDisplay(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        let display = displayCoordinate(lat: lat, lon: lon, tileType: currentTileType)
        RuntimeLogger.info("APP", "坐标转换", "WGS-84 坐标已适配地图显示", details: [
            "转换": String(currentTileType == .gcj02 && usesGCJ02ServiceArea(lat: lat, lon: lon))
        ])
        return display
    }

    private static func storedCoordinate(
        lat: Double,
        lon: Double,
        tileType: CoordType
    ) -> (lat: Double, lon: Double) {
        guard tileType == .gcj02, usesGCJ02ServiceArea(lat: lat, lon: lon) else {
            return (lat, lon)
        }
        return gcj02ToWgs84(lat: lat, lon: lon)
    }

    private static func displayCoordinate(
        lat: Double,
        lon: Double,
        tileType: CoordType
    ) -> (lat: Double, lon: Double) {
        guard tileType == .gcj02, usesGCJ02ServiceArea(lat: lat, lon: lon) else {
            return (lat, lon)
        }
        return wgs84ToGcj02(lat: lat, lon: lon)
    }

    // MARK: - 工具

    /// Haversine 距离（米）
    static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0)
              * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    // MARK: - 核心转换

    /// GCJ-02 → WGS-84（迭代法，精度优于 0.5 米）
    static func gcj02ToWgs84(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        guard usesGCJ02ServiceArea(lat: lat, lon: lon) else { return (lat, lon) }
        var wgsLat = lat
        var wgsLon = lon
        for _ in 0..<2 {
            let d = delta(lat: wgsLat, lon: wgsLon)
            wgsLat = lat - d.lat
            wgsLon = lon - d.lon
        }
        return (wgsLat, wgsLon)
    }

    /// WGS-84 → GCJ-02
    static func wgs84ToGcj02(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        guard usesGCJ02ServiceArea(lat: lat, lon: lon) else { return (lat, lon) }
        let d = delta(lat: lat, lon: lon)
        return (lat + d.lat, lon + d.lon)
    }

    /// AMap documents GCJ-02 for mainland China, Hong Kong, Macao and Taiwan;
    /// its overseas world map uses WGS-84. Keep the bounds explicit so the
    /// domestic fallback tile type never shifts an overseas coordinate.
    static func usesGCJ02ServiceArea(lat: Double, lon: Double) -> Bool {
        let mainland = lat >= 0.8293 && lat <= 55.8271 && lon >= 72.004 && lon <= 137.8347
        let hongKong = lat >= 22.13 && lat <= 22.57 && lon >= 113.82 && lon <= 114.45
        let macao = lat >= 22.05 && lat <= 22.25 && lon >= 113.52 && lon <= 113.65
        let taiwan = lat >= 21.75 && lat <= 25.35 && lon >= 119.30 && lon <= 122.10
        return mainland || hongKong || macao || taiwan
    }

    // MARK: - 内部

    /// 计算偏移量 (WGS-84 → GCJ-02 的增量)
    private static func delta(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        let dLat = transformLat(x: lon - 105.0, y: lat - 35.0)
        let dLon = transformLon(x: lon - 105.0, y: lat - 35.0)
        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        return (
            lat: (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi),
            lon: (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        )
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}

private enum TileProbeResult {
    case response(name: String, count: Int)
    case unavailable
    case timedOut
    case cancelled
}

private final class TileProbeResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var result: TileProbeResult?
    private var continuation: CheckedContinuation<TileProbeResult, Never>?
    private var timeout: DispatchWorkItem?

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func install(
        _ continuation: CheckedContinuation<TileProbeResult, Never>,
        timeout: DispatchWorkItem
    ) {
        lock.lock()
        if let result {
            lock.unlock()
            timeout.cancel()
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
        self.timeout = timeout
        lock.unlock()
    }

    func resolve(_ nextResult: TileProbeResult) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = nextResult
        let continuation = continuation
        let timeout = timeout
        self.continuation = nil
        self.timeout = nil
        lock.unlock()

        timeout?.cancel()
        continuation?.resume(returning: nextResult)
    }
}
