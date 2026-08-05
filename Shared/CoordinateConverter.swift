import Foundation

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

    /// 当前地图瓦片坐标系（每次从地图拿到坐标后更新）
    @MainActor static var currentTileType = CoordType.gcj02

    /// 从地图坐标推算当前瓦片类型并更新全局状态
    @MainActor
    static func updateTileType(lat: Double, lon: Double) {
        let type = detectType(lat: lat, lon: lon)
        if type != currentTileType {
            currentTileType = type
            RuntimeLogger.info("APP", "坐标转换", "地图瓦片切换 → \(type.rawValue)", details: [
                "坐标": "\(lat), \(lon)"
            ])
        }
    }

    // MARK: - 存取转换

    /// 地图坐标 → WGS-84 存储
    @MainActor
    static func toStored(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        updateTileType(lat: lat, lon: lon)
        guard currentTileType == .gcj02 else {
            RuntimeLogger.info("APP", "坐标转换", "toStored: 不转 瓦片=\(currentTileType.rawValue)", details: [
                "lat": String(lat), "lon": String(lon)
            ])
            return (lat, lon)
        }
        let wgs = gcj02ToWgs84(lat: lat, lon: lon)
        let d = distance(lat1: lat, lon1: lon, lat2: wgs.lat, lon2: wgs.lon)
        RuntimeLogger.info("APP", "坐标转换", "toStored: GCJ-02 → WGS-84 瓦片=\(currentTileType.rawValue)", details: [
            "原始": "\(lat), \(lon)",
            "结果": "\(wgs.lat), \(wgs.lon)",
            "偏移": String(format: "%.0fm", d)
        ])
        return wgs
    }

    /// WGS-84 存储 → 当前地图瓦片坐标系（显示用）
    @MainActor
    static func toDisplay(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        guard currentTileType == .gcj02 else {
            RuntimeLogger.info("APP", "坐标转换", "toDisplay: WGS-84 → 不转 瓦片=\(currentTileType.rawValue)", details: [
                "lat": String(lat), "lon": String(lon)
            ])
            return (lat, lon)
        }
        let gcj = wgs84ToGcj02(lat: lat, lon: lon)
        let d = distance(lat1: lat, lon1: lon, lat2: gcj.lat, lon2: gcj.lon)
        RuntimeLogger.info("APP", "坐标转换", "toDisplay: WGS-84 → GCJ-02 瓦片=\(currentTileType.rawValue)", details: [
            "原始": "\(lat), \(lon)",
            "结果": "\(gcj.lat), \(gcj.lon)",
            "偏移": String(format: "%.0fm", d)
        ])
        return gcj
    }

    // MARK: - 类型检测

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

    /// MKMapView 瓦片坐标系：中国境内 GCJ-02，境外 WGS-84
    static func detectType(lat: Double, lon: Double) -> CoordType {
        // GCJ-02 加密只在中国境内生效，用地理边界判断
        if lat > 17.5 && lat < 54.0 && lon > 72.5 && lon < 136.0 {
            return .gcj02
        }
        return .wgs84
    }

    // MARK: - 核心转换

    /// GCJ-02 → WGS-84（迭代法，精度优于 0.5 米）
    static func gcj02ToWgs84(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
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
        let d = delta(lat: lat, lon: lon)
        return (lat + d.lat, lon + d.lon)
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
