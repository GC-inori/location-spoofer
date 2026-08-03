import Foundation

/// GCJ-02 (火星坐标) ↔ WGS-84 坐标转换。
///
/// 在中国地区，MKMapView 使用高德 (AutoNavi) 瓦片数据（GCJ-02 坐标系），
/// 因此从 MKMapView 的 `centerCoordinate`、`convert(point:toCoordinateFrom:)`
/// 等方法返回的坐标也是 GCJ-02。但 CoreLocation / CLLocationManager 返回的
/// 以及 Apple wloc 定位服务使用的都是 WGS-84。
///
/// 虚拟定位的坐标流中：
/// - 地图 UI 层（显示、选点）：GCJ-02（与瓦片一致）
/// - 代理写出层（wloc 响应改写）：WGS-84
///
/// 因此需要在坐标从地图 UI 进入代理之前做 GCJ-02 → WGS-84 转换。
enum CoordinateConverter {
    // 椭球参数 (Krasovsky 1940)
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    /// GCJ-02 → WGS-84（迭代法，精度优于 0.5 米）
    static func gcj02ToWgs84(lat: Double, lon: Double) -> (lat: Double, lon: Double) {
        var wgsLat = lat
        var wgsLon = lon
        // 两次迭代足以收敛到亚米级精度
        for _ in 0..<2 {
            let d = delta(lat: wgsLat, lon: wgsLon)
            wgsLat = lat - d.lat
            wgsLon = lon - d.lon
        }
        return (wgsLat, wgsLon)
    }

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
