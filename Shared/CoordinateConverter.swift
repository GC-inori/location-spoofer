import Foundation
import CoreLocation
import MapKit

struct CoordinatePair: Codable, Equatable {
    static let currentConversionVersion = 1

    struct Value: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    let wgs84: Value
    let gcj02: Value
    let conversionVersion: Int

    init(wgs84: Value, gcj02: Value, conversionVersion: Int = CoordinatePair.currentConversionVersion) {
        self.wgs84 = wgs84
        self.gcj02 = gcj02
        self.conversionVersion = conversionVersion
    }

    init(mapCoordinate: CLLocationCoordinate2D, mapCoordinateSystem: CoordinateConverter.MapCoordinateSystem) {
        self = CoordinateConverter.coordinatePair(
            lat: mapCoordinate.latitude,
            lon: mapCoordinate.longitude,
            mapCoordinateSystem: mapCoordinateSystem
        )
    }

    func coordinate(for mapCoordinateSystem: CoordinateConverter.MapCoordinateSystem) -> CLLocationCoordinate2D {
        switch mapCoordinateSystem {
        case .wgs84: return wgs84.coordinate
        case .gcj02: return gcj02.coordinate
        }
    }

    func matchesWGS84(latitude: Double, longitude: Double, tolerance: Double = 0.0001) -> Bool {
        abs(wgs84.latitude - latitude) <= tolerance
            && abs(wgs84.longitude - longitude) <= tolerance
    }
}

/// GCJ-02 (火星坐标) ↔ WGS-84 坐标转换。
///
/// MapKit does not expose a public API for its active coordinate reference system.
/// The app resolves it with a bounded heuristic, then stores both WGS-84 and
/// GCJ-02 representations at each write boundary so replay does not convert again.
enum CoordinateConverter {
    // 椭球参数 (Krasovsky 1940)
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    /// 坐标类型
    enum MapCoordinateSystem: String {
        case gcj02 = "GCJ-02"
        case wgs84 = "WGS-84"

        var diagnosticName: String {
            switch self {
            case .gcj02: return "国内标准(GCJ-02)"
            case .wgs84: return "国际标准(WGS-84)"
            }
        }
    }

    struct CoordinateRepresentationDiagnosis: Equatable {
        let inferredSystem: MapCoordinateSystem?
        let distanceToWGS84: CLLocationDistance
        let distanceToGCJ02: CLLocationDistance

        var inferredName: String {
            inferredSystem?.diagnosticName ?? "无法判定"
        }
    }

    // MARK: - 地图坐标标准

    struct MapCoordinateSystemChange: Equatable {
        let previous: MapCoordinateSystem
        let current: MapCoordinateSystem
    }

    /// 当前 Apple 地图坐标标准。检测不可用时使用国内 GCJ-02 作为兜底。
    @MainActor static var currentMapCoordinateSystem = MapCoordinateSystem.gcj02
    @MainActor private static var mapCoordinateSystemCheckPending = false
    @MainActor private(set) static var initialMapCoordinateSystemUsedFallback = true

    /// Startup gate: only request realtime location if the public MapKit probe
    /// cannot resolve a coordinate type. This guarantees a finite answer before
    /// persisted map positions are replayed.
    @MainActor
    static func resolveInitialMapCoordinateSystem() async -> MapCoordinateSystem {
        guard !mapCoordinateSystemCheckPending else {
            RuntimeLogger.warning("APP", "坐标转换", "地图坐标标准检测已有请求进行中")
            return currentMapCoordinateSystem
        }
        mapCoordinateSystemCheckPending = true
        defer { mapCoordinateSystemCheckPending = false }
        RuntimeLogger.info("APP", "坐标转换", "地图坐标标准检测开始", details: [
            "锚点": "22.283819,114.158439",
            "判定规则": "首条名称=林士街→GCJ-02，否则→WGS-84",
            "缓存": "false"
        ])

        let nextType: MapCoordinateSystem
        switch await fixedAnchorCoordinateSystemProbe() {
        case let .response(name, count):
            nextType = mapCoordinateSystem(anchorName: name)
            initialMapCoordinateSystemUsedFallback = false
            RuntimeLogger.info("APP", "坐标转换", "地图坐标标准检测获得明确结果", details: [
                "首条名称": name,
                "结果数": String(count),
                "命中林士街": String(name == "林士街"),
                "最终标准": nextType.rawValue,
                "结果来源": "固定锚点"
            ])
        case .unavailable(let reason), .timedOut(let reason):
            RuntimeLogger.warning("APP", "坐标转换", "地图坐标标准检测不可用，开始实时定位兜底", details: [
                "原因": reason
            ])
            let realtime = await RealtimeLocationManager.shared.requestLocation()
            if let realtime,
               CLLocationCoordinate2DIsValid(realtime),
               !usesGCJ02ServiceArea(lat: realtime.latitude, lon: realtime.longitude) {
                nextType = .wgs84
            } else {
                nextType = .gcj02
            }
            initialMapCoordinateSystemUsedFallback = true
            RuntimeLogger.warning("APP", "坐标转换", "地图坐标标准检测使用兜底结果", details: [
                "探测失败原因": reason,
                "实时定位存在": String(realtime != nil),
                "最终标准": nextType.rawValue,
                "结果来源": realtime == nil ? "默认国内标准" : "实时定位服务区域"
            ])
        case .cancelled:
            initialMapCoordinateSystemUsedFallback = true
            RuntimeLogger.warning("APP", "坐标转换", "地图坐标标准检测被取消，保留默认国内标准", details: [
                "最终标准": currentMapCoordinateSystem.rawValue
            ])
            return currentMapCoordinateSystem
        }

        _ = applyDetectedMapCoordinateSystem(nextType)
        RuntimeLogger.info("APP", "坐标转换", "地图坐标标准已确定，允许创建地图", details: [
            "最终标准": nextType.rawValue,
            "使用兜底": String(initialMapCoordinateSystemUsedFallback),
            "缓存": "false"
        ])
        return nextType
    }

    /// Re-runs the same location-independent fixed-anchor probe after a
    /// spoofing environment change. Runtime callers must never infer MapKit's
    /// representation from the geographic region of the current location: that
    /// sample may itself already be virtual.
    @MainActor
    static func refreshMapCoordinateSystem() async -> MapCoordinateSystemChange? {
        guard !mapCoordinateSystemCheckPending else {
            RuntimeLogger.info("APP", "坐标转换", "运行期地图坐标标准刷新已在进行中")
            return nil
        }
        mapCoordinateSystemCheckPending = true
        defer { mapCoordinateSystemCheckPending = false }

        RuntimeLogger.info("APP", "坐标转换", "运行期地图坐标标准刷新开始", details: [
            "当前标准": currentMapCoordinateSystem.rawValue,
            "锚点": "22.283819,114.158439"
        ])
        switch await fixedAnchorCoordinateSystemProbe() {
        case let .response(name, count):
            let detected = mapCoordinateSystem(anchorName: name)
            initialMapCoordinateSystemUsedFallback = false
            let change = applyDetectedMapCoordinateSystem(detected)
            RuntimeLogger.info("APP", "坐标转换", "运行期地图坐标标准刷新完成", details: [
                "首条名称": name,
                "结果数": String(count),
                "探测标准": detected.rawValue,
                "发生切换": String(change != nil)
            ])
            return change
        case .unavailable(let reason), .timedOut(let reason):
            RuntimeLogger.warning("APP", "坐标转换", "运行期地图坐标标准刷新不可用，保留当前标准", details: [
                "原因": reason,
                "当前标准": currentMapCoordinateSystem.rawValue
            ])
            return nil
        case .cancelled:
            RuntimeLogger.info("APP", "坐标转换", "运行期地图坐标标准刷新被取消，保留当前标准", details: [
                "当前标准": currentMapCoordinateSystem.rawValue
            ])
            return nil
        }
    }

    /// Applies a coordinate system that was resolved by the fixed-anchor
    /// probe. Kept as a small deterministic seam for regression tests.
    @MainActor
    static func applyDetectedMapCoordinateSystem(_ detected: MapCoordinateSystem) -> MapCoordinateSystemChange? {
        guard detected != currentMapCoordinateSystem else { return nil }
        let change = MapCoordinateSystemChange(
            previous: currentMapCoordinateSystem,
            current: detected
        )
        currentMapCoordinateSystem = detected
        return change
    }

    private static func mapCoordinateSystem(anchorName: String) -> MapCoordinateSystem {
        anchorName == "林士街" ? .gcj02 : .wgs84
    }

    /// A user-requested realtime sample is WGS-84 and can correct a provisional
    /// startup map coordinate system without altering persisted coordinate pairs.
    @MainActor
    static func correctMapCoordinateSystemUsingRealtime(_ coordinate: CLLocationCoordinate2D) -> MapCoordinateSystemChange? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        guard initialMapCoordinateSystemUsedFallback else {
            RuntimeLogger.info("APP", "坐标转换", "实时定位不覆盖固定锚点的明确检测结果", details: [
                "当前标准": currentMapCoordinateSystem.rawValue
            ])
            return nil
        }
        let next: MapCoordinateSystem = usesGCJ02ServiceArea(lat: coordinate.latitude, lon: coordinate.longitude) ? .gcj02 : .wgs84
        guard let change = applyDetectedMapCoordinateSystem(next) else {
            RuntimeLogger.info("APP", "坐标转换", "实时定位确认兜底地图坐标标准无需修正", details: [
                "当前标准": currentMapCoordinateSystem.rawValue
            ])
            return nil
        }
        RuntimeLogger.warning("APP", "坐标转换", "实时定位修正启动兜底地图坐标标准", details: [
            "from": change.previous.rawValue,
            "to": change.current.rawValue
        ])
        return change
    }

    private static func fixedAnchorCoordinateSystemProbe() async -> MapCoordinateSystemProbeResult {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "22.283819, 114.158439"
        let search = MKLocalSearch(request: request)
        let resolver = MapCoordinateSystemProbeResolver()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let timeout = DispatchWorkItem {
                    search.cancel()
                    resolver.resolve(.timedOut(reason: "固定锚点查询超过5秒"))
                }
                resolver.install(continuation, timeout: timeout)
                guard !resolver.isResolved else { return }
                search.start { response, error in
                    if let error {
                        let nsError = error as NSError
                        resolver.resolve(.unavailable(
                            reason: "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
                        ))
                        return
                    }
                    let items = response?.mapItems ?? []
                    guard let first = items.first,
                          let name = first.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !name.isEmpty else {
                        resolver.resolve(.unavailable(reason: "固定锚点查询返回空结果"))
                        return
                    }
                    resolver.resolve(.response(name: name, count: items.count))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            }
        }, onCancel: {
            search.cancel()
            resolver.resolve(.cancelled)
        })
    }

    /// Creates the complete persisted pair once at the map input boundary.
    static func coordinatePair(lat: Double, lon: Double, mapCoordinateSystem: MapCoordinateSystem) -> CoordinatePair {
        let raw = CoordinatePair.Value(latitude: lat, longitude: lon)
        switch mapCoordinateSystem {
        case .wgs84:
            let gcj = wgs84ToGcj02(lat: lat, lon: lon)
            return CoordinatePair(
                wgs84: raw,
                gcj02: .init(latitude: gcj.lat, longitude: gcj.lon)
            )
        case .gcj02:
            let wgs = gcj02ToWgs84(lat: lat, lon: lon)
            return CoordinatePair(
                wgs84: .init(latitude: wgs.lat, longitude: wgs.lon),
                gcj02: raw
            )
        }
    }

    /// Legacy raw domestic map values were historically displayed as GCJ-02;
    /// overseas values were WGS-84 and stay identity coordinates.
    static func legacyCoordinatePair(lat: Double, lon: Double) -> CoordinatePair {
        let type: MapCoordinateSystem = usesGCJ02ServiceArea(lat: lat, lon: lon) ? .gcj02 : .wgs84
        return coordinatePair(lat: lat, lon: lon, mapCoordinateSystem: type)
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

    /// Identifies which stored representation a runtime sample most closely
    /// resembles. Overseas identity pairs and unrelated samples stay ambiguous.
    static func diagnoseRepresentation(
        sample: CLLocationCoordinate2D,
        pair: CoordinatePair,
        maximumDistance: CLLocationDistance = 1_000,
        minimumSeparation: CLLocationDistance = 30
    ) -> CoordinateRepresentationDiagnosis {
        let distanceToWGS84 = distance(
            lat1: sample.latitude,
            lon1: sample.longitude,
            lat2: pair.wgs84.latitude,
            lon2: pair.wgs84.longitude
        )
        let distanceToGCJ02 = distance(
            lat1: sample.latitude,
            lon1: sample.longitude,
            lat2: pair.gcj02.latitude,
            lon2: pair.gcj02.longitude
        )
        let nearestDistance = min(distanceToWGS84, distanceToGCJ02)
        let separation = abs(distanceToWGS84 - distanceToGCJ02)
        let inferredSystem: MapCoordinateSystem?
        if nearestDistance > maximumDistance || separation < minimumSeparation {
            inferredSystem = nil
        } else {
            inferredSystem = distanceToWGS84 < distanceToGCJ02 ? .wgs84 : .gcj02
        }
        return CoordinateRepresentationDiagnosis(
            inferredSystem: inferredSystem,
            distanceToWGS84: distanceToWGS84,
            distanceToGCJ02: distanceToGCJ02
        )
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

    /// Keep the GCJ-02 service region explicit. Outside this region, conversion
    /// is identity so the domestic fallback can never shift an overseas value.
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

private enum MapCoordinateSystemProbeResult {
    case response(name: String, count: Int)
    case unavailable(reason: String)
    case timedOut(reason: String)
    case cancelled
}

private final class MapCoordinateSystemProbeResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var result: MapCoordinateSystemProbeResult?
    private var continuation: CheckedContinuation<MapCoordinateSystemProbeResult, Never>?
    private var timeout: DispatchWorkItem?

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func install(
        _ continuation: CheckedContinuation<MapCoordinateSystemProbeResult, Never>,
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

    func resolve(_ nextResult: MapCoordinateSystemProbeResult) {
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
