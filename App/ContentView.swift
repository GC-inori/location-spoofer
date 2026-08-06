import SwiftUI

struct ContentView: View {
    @StateObject private var setup = SetupCoordinator()
    @State private var phase: AppPhase = .splash
    @AppStorage("setupCompleted") private var setupCompleted = false

    enum AppPhase { case splash, map }

    var body: some View {
        Group {
            switch phase {
            case .splash:
                VStack(spacing: 16) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 48)).foregroundStyle(.blue)
                    ProgressView()
                    Text("正在初始化地图与本地代理…").font(.subheadline).foregroundStyle(.secondary)
                }
            case .map:
                NavigationView {
                    MapHomeView(setup: setup)
                }
                .fullScreenCover(isPresented: $setup.needsSetup) {
                    FirstSetupView(setup: setup, onComplete: {
                        setupCompleted = true
                        setup.completeSetup()
                    })
                }
            }
        }
        .task { await bootstrap() }
    }

    @MainActor
    private func bootstrap() async {
        await setup.prepareLocalServices()
        do {
            try CoordinateStorageMigration.migrateIfNeeded(favorites: FavoriteLocationStore())
        } catch {
            RuntimeLogger.error("APP", "Startup", "旧坐标数据迁移失败，将在下次启动重试", error: error)
        }

        // MapHomeView is intentionally constructed only after this required
        // coordinate-system gate resolves, so cached pins are never replayed
        // into an unknown Apple Maps coordinate system.
        let mapCoordinateSystem = await CoordinateConverter.resolveInitialMapCoordinateSystem()
        guard !Task.isCancelled else { return }
        RuntimeLogger.info("APP", "Startup", "地图坐标标准初始化完成，开始后续启动流程", details: [
            "地图标准": mapCoordinateSystem.rawValue,
            "使用兜底": String(CoordinateConverter.initialMapCoordinateSystemUsedFallback)
        ])

        // Resolve the first map center before constructing MapHomeView. This
        // prevents a Shenzhen/cache frame followed by a second realtime frame.
        if LastCoordinateStore.load() == nil {
            RuntimeLogger.info("APP", "Startup", "没有持久化图钉，地图创建前请求实时定位")
            if let realtime = await RealtimeLocationManager.shared.requestLocation() {
                let mapCoordinateSystemChange = CoordinateConverter.correctMapCoordinateSystemUsingRealtime(realtime)
                let pair = CoordinateConverter.coordinatePair(
                    lat: realtime.latitude,
                    lon: realtime.longitude,
                    mapCoordinateSystem: .wgs84
                )
                LastCoordinateStore.save(coordinatePair: pair, zoomMeters: 1_000)
                RuntimeLogger.info("APP", "Startup", "已使用实时定位准备唯一初始地图状态", details: [
                    "地图标准": CoordinateConverter.currentMapCoordinateSystem.rawValue,
                    "修正兜底标准": String(mapCoordinateSystemChange != nil),
                    "缩放米": "1000"
                ])
                RealtimeLocationTrace.coordinate(
                    "地图创建前取得的初始实时位置（WGS-84）",
                    coordinate: realtime
                )
            } else {
                RuntimeLogger.warning("APP", "Startup", "地图创建前无法取得实时定位，唯一初始位置使用深圳", details: [
                    "地图标准": mapCoordinateSystem.rawValue,
                    "缩放米": "1000"
                ])
            }
        } else {
            RuntimeLogger.info("APP", "Startup", "已找到持久化图钉，直接准备唯一初始地图状态")
        }
        guard !Task.isCancelled else { return }

        if setupCompleted {
            let result = await setup.runVerificationTest()
            setup.applyVerificationResult(result)
        } else {
            setup.requestSetup()
        }
        RuntimeLogger.info("APP", "Startup", "启动门禁全部完成，现在创建 MapHomeView")
        phase = .map
    }
}
