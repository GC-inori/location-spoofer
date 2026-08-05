import SwiftUI
import MapKit
import UIKit
import CoreLocation

private struct SearchLocationResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

private enum HomeSheet: String, Identifiable {
    case settings, logs
    var id: String { rawValue }
}

private enum SpoofState {
    case idle, verifying, active
}

private struct RealtimeLocationRequestContext {
    let intent: RealtimeLocationIntent
    let source: String
    let showFailureAlert: Bool
}

struct MapHomeView: View {
    @ObservedObject var setup: SetupCoordinator
    @StateObject private var favorites = FavoriteLocationStore()
    @StateObject private var actions = LocationActionCoordinator()
    @ObservedObject private var proxy = ProxyManager.shared
    @StateObject private var realtime = RealtimeLocationManager.shared
    @StateObject private var mapState: MapLocationState
    @ObservedObject private var net = NetworkMonitor.shared

    @State private var searchText = ""
    @State private var searchResults: [SearchLocationResult] = []
    @State private var isSearching = false
    @State private var searchRequestID: UInt64 = 0
    @State private var searchError = ""
    @State private var mapDidInitialize = false
    @State private var activeSheet: HomeSheet?
    @State private var showEnableTip = false
    @State private var showDisableTip = false
    @State private var activeTip: TipKind?
    @State private var manualHint = ""
    @AppStorage("activationTipCount") private var activationTipCount = 0
    @AppStorage("activationTipDisabled") private var activationTipDisabled = false
    @State private var editingFavorite: FavoriteLocation?
    @State private var editName = ""
    @State private var reverseGeocodeTask: Task<Void, Never>?
    @State private var geocodeDebounceTask: Task<Void, Never>?
    @State private var showLocationAlert = false
    @State private var realtimeRequestTask: Task<Void, Never>?
    @State private var realtimeRequestContext: RealtimeLocationRequestContext?
    @State private var copyConfirmed = false
    @State private var spoofState: SpoofState = .idle
    @State private var locationOperationTask: Task<Void, Never>?
    @State private var locationOperationID: UInt64 = 0
    // 激活时的坐标（本地存，绕过 C 桥接层精度丢失）
    @State private var activeSpoofLat: Double?
    @State private var activeSpoofLon: Double?

    init(setup: SetupCoordinator) {
        self.setup = setup
        let savedCoord = LastCoordinateStore.load()
        let initialZoom = ViewportStore.loadOrDefault()
        // 持久化存的是 WGS-84，直接转当前瓦片坐标系显示
        let initialCoord: CLLocationCoordinate2D
        if let coord = savedCoord?.coordinate {
            let display = CoordinateConverter.toDisplay(lat: coord.latitude, lon: coord.longitude)
            initialCoord = CLLocationCoordinate2D(latitude: display.lat, longitude: display.lon)
        } else {
            initialCoord = CLLocationCoordinate2D(latitude: 22.544577, longitude: 113.94114)
        }
        _mapState = StateObject(wrappedValue: MapLocationState(
            initialCoordinate: initialCoord,
            initialViewportMeters: initialZoom
        ))
    }

    var body: some View {
        ZStack {
            MapViewRepresentable(
                selection: mapState.selection,
                cameraCommand: mapState.cameraCommand,
                onRealtimeLocationChanged: { location in
                    handleNativeRealtimeLocation(location)
                },
                onUserCenterChanged: { coordinate, distance in
                    mapState.updateViewport(distanceMeters: distance)
                    CoordinateConverter.updateTileType(lat: coordinate.latitude, lon: coordinate.longitude)
                    let previousRevision = mapState.selection.revision
                    let revision = mapState.selectUserMapCenter(coordinate)
                    guard revision != previousRevision else { return }
                    let wgs = CoordinateConverter.toStored(lat: coordinate.latitude, lon: coordinate.longitude)
                    LastCoordinateStore.save(lat: wgs.lat, lon: wgs.lon)
                    favorites.select(nil)
                    scheduleGeocode(coordinate: coordinate, revision: revision)
                },
                onViewportChanged: { distance in
                    mapState.updateViewport(distanceMeters: distance)
                },
                onMapTap: { coordinate in
                    favorites.select(nil)
                    CoordinateConverter.updateTileType(lat: coordinate.latitude, lon: coordinate.longitude)
                    let revision = mapState.selectMapTap(coordinate)
                    let wgs = CoordinateConverter.toStored(lat: coordinate.latitude, lon: coordinate.longitude)
                    LastCoordinateStore.save(lat: wgs.lat, lon: wgs.lon)
                    scheduleGeocode(coordinate: coordinate, revision: revision)
                },
                onUserZoomChanged: { distance in
                    ViewportStore.save(distance)
                },
                onZoomIn: { mapState.zoom(by: 0.5) },
                onZoomOut: { mapState.zoom(by: 2) }
            )
                .ignoresSafeArea(.container)

            VStack(spacing: 10) {
                topControls
                if !searchResults.isEmpty || !searchError.isEmpty { searchResultList }
                Spacer()
                // 右下角按钮
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button {
                            if let url = URL(string: "maps://app") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "map.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        }
                        Button {
                            requestRealtimeLocation()
                        } label: {
                            if realtime.isRequesting {
                                ProgressView()
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                            }
                        }
                        .disabled(realtimeRequestTask != nil || realtime.isRequesting)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                bottomControls
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
        .sheet(item: $activeSheet) { sheet in
            NavigationView {
                switch sheet {
                case .settings: SettingsView(setup: setup, actions: actions)
                case .logs: RuntimeLogsView(setup: setup, actions: actions, testFavorite: testFavorite)
                }
            }
        }
        .sheet(item: $activeTip) { kind in
            TipSheetView(kind: kind)
        }
        .alert("无法直接跳转", isPresented: Binding(
            get: { !manualHint.isEmpty },
            set: { if !$0 { manualHint = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: { Text(manualHint) }
        .onAppear {
            initializeMap()
            NetworkMonitor.shared.onWiFiChanged = { [self] in
                guard spoofState == .active else { return }
                Task { @MainActor in
                    let target = currentSelectionFavorite
                    let result = await setup.runVerificationTest(testLat: target.latitude, testLon: target.longitude)
                    if !result.isSuccess, let tip = result.tipKind {
                        activeTip = tip
                    }
                }
            }
        }
        .onChange(of: net.isAirplaneMode) { airplane in
            if !airplane {
                Task { await setup.refreshTrust() }
            }
        }
        .onChange(of: proxy.isRunning) { running in
            if !running && spoofState == .active {
                spoofState = .idle
                actions.clear()
            }
        }
        .sheet(isPresented: $showEnableTip) { enableTipSheet }
        .sheet(isPresented: $showDisableTip) { disableTipSheet }
        .alert("定位失败", isPresented: $showLocationAlert) {
            Button("打开设置") {
                openSettings(.locationServices)
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法获取当前定位，请检查定位服务是否已开启")
        }
        .alert("编辑收藏名称", isPresented: Binding(
            get: { editingFavorite != nil },
            set: { if !$0 { editingFavorite = nil } }
        )) {
            TextField("名称", text: $editName)
            Button("保存") {
                if let f = editingFavorite {
                    let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = name.isEmpty ? f.name : name
                    favorites.rename(f.id, to: finalName)
                    mapState.updateExplicitName(finalName, forFavoriteID: f.id)
                }
                editingFavorite = nil
            }
            Button("取消", role: .cancel) { editingFavorite = nil }
        } message: { Text("修改收藏地点名称") }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索地点或坐标", text: $searchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search).onSubmit(doSearch)
                if isSearching { ProgressView().controlSize(.small) }
                else if !searchText.isEmpty {
                    Button {
                        searchRequestID &+= 1
                        isSearching = false
                        searchText = ""
                        searchResults = []
                        searchError = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Button(action: doSearch) { Image(systemName: "arrow.right.circle.fill").font(.title3) }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.13), radius: 9, y: 4)
            Menu {
                Button { activeSheet = .logs } label: { Label("日志", systemImage: "list.bullet.rectangle") }
                Button { activeSheet = .settings } label: { Label("设置", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.13), radius: 9, y: 4)
                    .contentShape(Circle())
            }.accessibilityLabel("更多")
        }
    }

    // 搜索列表：动态高度，不写死
    private var searchResultList: some View {
        VStack(spacing: 0) {
            if !searchError.isEmpty {
                Text(searchError).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            ForEach(searchResults) { r in
                HStack(spacing: 8) {
                    Button { selectSearchResult(r) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button(role: .destructive) { deleteSearchResult(r) } label: {
                        Image(systemName: "trash").frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.red)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                if r.id != searchResults.last?.id { Divider().padding(.leading, 46) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // 底部：当前选点 + 收藏 + 主控按钮
    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 当前选点
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mapState.displayName ?? "当前选点").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(String(format: "%.6f, %.6f", mapState.selection.coordinate.latitude, mapState.selection.coordinate.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(copyConfirmed ? .green : .secondary)
                        .onTapGesture {
                            let text = String(format: "%.6f, %.6f", mapState.selection.coordinate.latitude, mapState.selection.coordinate.longitude)
                            UIPasteboard.general.string = text
                            RuntimeLogger.info("APP", "地图", "复制坐标: \(text)")
                            copyConfirmed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyConfirmed = false }
                        }
                        .overlay(alignment: .top) {
                            if copyConfirmed {
                                Text("已复制")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                                    .offset(y: -24)
                            }
                        }
                }
                Spacer()
                // 帮助说明按钮
                Button {
                    if actions.virtualLocationEnabled {
                        activeTip = .activation
                    } else {
                        showDisableTip = true
                    }
                } label: {
                    Text(actions.virtualLocationEnabled ? "无法生效？" : "无法取消？")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                // 收藏按钮
                Button {
                    if favorites.selectedFavoriteID != nil {
                        favorites.select(nil)
                        return
                    }
                    let snapshot = currentSelectionFavorite
                    let wgs = CoordinateConverter.toStored(lat: snapshot.latitude, lon: snapshot.longitude)
                    let favorite = favorites.save(
                        name: snapshot.name,
                        latitude: wgs.lat,
                        longitude: wgs.lon,
                        accuracy: snapshot.accuracy
                    )
                    let display = CoordinateConverter.toDisplay(lat: favorite.latitude, lon: favorite.longitude)
                    mapState.selectFavorite(
                        CLLocationCoordinate2D(latitude: display.lat, longitude: display.lon),
                        id: favorite.id,
                        name: favorite.name
                    )
                } label: {
                    Image(systemName: favorites.selectedFavoriteID != nil ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background((favorites.selectedFavoriteID != nil ? Color.yellow : Color.gray).opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(favorites.selectedFavoriteID != nil ? .orange : .gray)
                .accessibilityLabel(favorites.selectedFavoriteID != nil ? "已收藏，点击取消收藏" : "收藏当前选点")
            }
            // 收藏
            if favorites.favorites.isEmpty {
                Text("搜索或点击地图选点后，保存为收藏。").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(favorites.favorites) { f in favoriteChip(f) } }.padding(.vertical, 2)
                }
            }
            // 主控按钮（带动画）
            HStack(spacing: 10) {
                Button(action: handleMainButtonTap) {
                    HStack(spacing: 6) {
                        if spoofState == .verifying {
                            ProgressView().tint(.white)
                        }
                        Text(spoofState == .active && needsSwitchButton ? "关闭" : buttonTitle)
                            .font(.headline).lineLimit(1)
                    }
                    .frame(maxWidth: needsSwitchButton ? nil : .infinity)
                    .frame(minWidth: needsSwitchButton ? 56 : nil)
                    .padding(.vertical, 14)
                    .padding(.horizontal, needsSwitchButton ? 12 : 14)
                }
                .background(buttonColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .disabled(spoofState == .verifying)

                if needsSwitchButton {
                    Button {
                        beginLocationOperation()
                    } label: {
                        Label("切换到此处", systemImage: "arrow.triangle.swap")
                            .font(.body.weight(.medium)).lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12).padding(.horizontal, 16)
                    }
                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: needsSwitchButton)
            .padding(.top, 4)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }


    private var needsSwitchButton: Bool {
        guard spoofState == .active,
              let sLat = activeSpoofLat,
              let sLon = activeSpoofLon else { return false }
        return abs(sLat - mapState.selection.coordinate.latitude) > 0.0001
            || abs(sLon - mapState.selection.coordinate.longitude) > 0.0001
    }

    private var buttonTitle: String {
        switch spoofState {
        case .idle: return "开始虚拟定位"
        case .verifying: return "验证环境中…"
        case .active: return "停止虚拟定位"
        }
    }

    private var buttonColor: Color {
        switch spoofState {
        case .idle: return .blue
        case .verifying: return .gray
        case .active: return .green
        }
    }

    private func handleMainButtonTap() {
        switch spoofState {
        case .idle:
            beginLocationOperation()
        case .active:
            stopSpoofing()
        case .verifying:
            break
        }
    }

    private func beginLocationOperation() {
        guard spoofState != .verifying, locationOperationTask == nil else { return }
        locationOperationID &+= 1
        let operationID = locationOperationID
        let selectionRevision = mapState.selection.revision
        let target = currentSelectionFavorite
        spoofState = .verifying

        locationOperationTask = Task { @MainActor in
            let result = await setup.runVerificationTest(testLat: target.latitude, testLon: target.longitude)
            guard !Task.isCancelled,
                  operationID == locationOperationID,
                  selectionRevision == mapState.selection.revision else {
                if operationID == locationOperationID {
                    spoofState = actions.virtualLocationEnabled ? .active : .idle
                    locationOperationTask = nil
                }
                return
            }

            if result.isSuccess {
                let applied = actions.applyVerified(target)
                spoofState = applied ? .active : .idle
                if applied {
                    activeSpoofLat = target.latitude
                    activeSpoofLon = target.longitude
                }
                RuntimeLogger.info("APP", "定位", "验证结果", details: [
                    "success": "true",
                    "applied": String(applied),
                    "spoofState": String(describing: spoofState)
                ])
                if applied && !activationTipDisabled {
                    showEnableTip = true
                    activationTipCount += 1
                }
            } else {
                spoofState = actions.virtualLocationEnabled ? .active : .idle
                RuntimeLogger.warning("APP", "定位", "验证失败", details: [
                    "result": result.id,
                    "spoofState": String(describing: spoofState)
                ])
                if let tip = result.tipKind {
                    activeTip = tip
                }
            }
            locationOperationTask = nil
        }
    }

    private func stopSpoofing() {
        locationOperationTask?.cancel()
        locationOperationTask = nil
        locationOperationID &+= 1
        actions.clear()
        spoofState = .idle
        activeSpoofLat = nil
        activeSpoofLon = nil
        showDisableTip = true
    }


    private func favoriteChip(_ f: FavoriteLocation) -> some View {
        HStack(spacing: 0) {
            Button { select(f) } label: {
                Label(f.name, systemImage: favorites.selectedFavoriteID == f.id ? "checkmark.circle.fill" : "mappin")
                    .lineLimit(1).padding(.leading, 10).padding(.vertical, 8).padding(.trailing, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider().frame(height: 22)
            Button {
                editingFavorite = f
                editName = f.name
            } label: {
                Image(systemName: "pencil").font(.caption2).frame(width: 32, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.primary.opacity(0.55))
            Divider().frame(height: 22)
            Button(role: .destructive) { favorites.delete(f) } label: {
                Image(systemName: "trash").font(.caption.weight(.semibold)).frame(width: 36, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.red)
        }
        .background((favorites.selectedFavoriteID == f.id ? Color.red.opacity(0.14) : Color.secondary.opacity(0.12)), in: Capsule())
        .overlay(Capsule().stroke(favorites.selectedFavoriteID == f.id ? Color.red.opacity(0.7) : Color.clear))
    }

    @MainActor
    private func openSettings(_ destination: SystemSettingsDestination) {
        SystemSettingsNavigator.open(destination) { fallbackHint in
            if let fallbackHint { manualHint = fallbackHint }
        }
    }


    private var currentSelectionFavorite: FavoriteLocation {
        FavoriteLocation(
            name: mapState.displayName ?? String(
                format: "%.4f, %.4f",
                mapState.selection.coordinate.latitude,
                mapState.selection.coordinate.longitude
            ),
            latitude: mapState.selection.coordinate.latitude,
            longitude: mapState.selection.coordinate.longitude,
            accuracy: 25
        )
    }

    private var testFavorite: FavoriteLocation { currentSelectionFavorite }

    private func initializeMap() {
        guard !mapDidInitialize else { return }
        mapDidInitialize = true

        if let selected = favorites.selectedFavorite {
            let display = CoordinateConverter.toDisplay(lat: selected.latitude, lon: selected.longitude)
            mapState.selectFavorite(
                CLLocationCoordinate2D(latitude: display.lat, longitude: display.lon),
                id: selected.id,
                name: selected.name
            )
            LastCoordinateStore.save(lat: selected.latitude, lon: selected.longitude)
        } else {
            mapState.focusSelection(distanceMeters: mapState.viewportMeters)
            scheduleGeocode(
                coordinate: mapState.selection.coordinate,
                revision: mapState.selection.revision
            )
        }

        // 启动坐标获取优先级：缓存 > 实时定位 > 深圳兜底（init 时已给兜底）
        let savedCoord = LastCoordinateStore.load()
        if savedCoord == nil {
            requestRealtimeLocation()
        }
    }

    private func requestRealtimeLocation() {
        let intent = mapState.beginRealtimeIntent()
        // 蓝点存在就直接用，不限时（MKMapView 的 userLocation 只在位置变化时才更新）
        if let loc = mapState.realtimeLocation {
            acceptRealtimeLocation(loc.coordinate, intent: intent, source: "MapKit蓝点")
            return
        }
        startRealtimeLocationRequest(
            source: "CLLocationManager",
            showFailureAlert: true,
            intent: intent
        )
    }

    private func handleNativeRealtimeLocation(_ location: CLLocation) {
        mapState.updateRealtimeLocation(location)
        guard let context = realtimeRequestContext else { return }

        // MKMapView's MKUserLocation is the visible blue point. When it arrives,
        // fulfill the pending intent from that exact sample and cancel the slower
        // CLLocationManager fallback so the camera and dot cannot disagree.
        realtimeRequestContext = nil
        realtimeRequestTask?.cancel()
        acceptRealtimeLocation(location.coordinate, intent: context.intent, source: "蓝点(途中)→\(context.source)")
    }

    private func startRealtimeLocationRequest(
        source: String,
        showFailureAlert: Bool,
        intent suppliedIntent: RealtimeLocationIntent? = nil
    ) {
        let intent = suppliedIntent ?? mapState.beginRealtimeIntent()
        realtimeRequestContext = RealtimeLocationRequestContext(
            intent: intent,
            source: source,
            showFailureAlert: showFailureAlert
        )

        // A button tap during the startup request retargets that same in-flight
        // Core Location request to the newer intent instead of being ignored.
        guard realtimeRequestTask == nil, !realtime.isRequesting else { return }
        realtimeRequestTask = Task { @MainActor in
            defer {
                realtimeRequestTask = nil
                realtimeRequestContext = nil
            }
            guard let coordinate = await realtime.requestLocation() else {
                guard let context = realtimeRequestContext,
                      context.showFailureAlert,
                      !Task.isCancelled,
                      mapState.selection.revision == context.intent.selectionRevision else { return }
                RuntimeLogger.info("APP", "地图", "定位失败 status=\(realtime.authorizationStatus.rawValue)")
                showLocationAlert = true
                return
            }
            guard !Task.isCancelled, let context = realtimeRequestContext else { return }
            acceptRealtimeLocation(coordinate, intent: context.intent, source: context.source)
        }
    }

    private func acceptRealtimeLocation(
        _ coordinate: CLLocationCoordinate2D,
        intent: RealtimeLocationIntent,
        source: String
    ) {
        let currentViewport = mapState.viewportMeters
        let accepted = mapState.acceptRealtimeLocation(coordinate, intent: intent)
        RuntimeLogger.info("APP", "地图", "\(source)返回", details: [
            "accepted": String(accepted),
            "lat": String(coordinate.latitude),
            "lon": String(coordinate.longitude)
        ])
        guard accepted else { return }
        // 用点击时的缩放级别居中，不改变缩放
        mapState.focusSelection(distanceMeters: currentViewport)
        // 蓝点坐标已是 WGS-84，直接存，不需要 toStored
        LastCoordinateStore.save(lat: coordinate.latitude, lon: coordinate.longitude)
        favorites.select(nil)
        scheduleGeocode(coordinate: coordinate, revision: mapState.selection.revision)
    }

    private func scheduleGeocode(coordinate: CLLocationCoordinate2D, revision: UInt64) {
        geocodeDebounceTask?.cancel()
        reverseGeocodeTask?.cancel()
        geocodeDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, mapState.selection.revision == revision else { return }
            reverseGeocode(coordinate, revision: revision)
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D, revision: UInt64) {
        reverseGeocodeTask?.cancel()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        reverseGeocodeTask = Task { @MainActor in
            let retryDelays: [UInt64] = [0, 800_000_000, 1_600_000_000]
            var lastError: Error?

            for (attempt, delay) in retryDelays.enumerated() {
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: delay) }
                    catch { return }
                }
                guard !Task.isCancelled, mapState.selection.revision == revision else { return }

                do {
                    // 并⾏获取：CLGeocoder（地址结构化） + MKLocalSearch（地图显⽰名称）
                    // MKLocalSearch 在无结果时抛错，不可与 CLGeocoder 共用 try await 导致互相影响
                    async let clPlacemarks = CLGeocoder().reverseGeocodeLocation(location)
                    let mkRequest = MKLocalSearch.Request()
                    mkRequest.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
                    let mkResponse = try? await MKLocalSearch(request: mkRequest).start()

                    let placemarks = try await clPlacemarks
                    guard !Task.isCancelled,
                          mapState.selection.revision == revision,
                          let placemark = placemarks.first else { return }

                    if let firstItem = mkResponse?.mapItems.first {
                        RuntimeLogger.info("APP", "Geocode", "MKLocalSearch 坐标对比", details: [
                            "输入坐标": "\(coordinate.latitude), \(coordinate.longitude)",
                            "搜索返回坐标": "\(firstItem.placemark.coordinate.latitude), \(firstItem.placemark.coordinate.longitude)",
                            "名称": firstItem.name ?? "nil"
                        ])
                    }
                    let mapItemName = mkResponse?.mapItems.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mapItemPOI = mkResponse?.mapItems.first?.placemark.areasOfInterest?.first
                    // 优先使⽤ MKLocalSearch 结果（与地图显⽰一致），CLGeocoder 作为 fallback
                    let poi = { () -> String? in
                        if let v = mapItemPOI?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
                        if let v = mapItemName?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
                        return placemark.areasOfInterest?.first ?? placemark.name
                    }()
                    let streetAddress = [placemark.thoroughfare, placemark.subThoroughfare]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let descriptor = MapPlaceDescriptor(
                        pointOfInterest: poi,
                        streetAddress: streetAddress,
                        road: placemark.thoroughfare,
                        neighborhood: placemark.subLocality,
                        district: placemark.subLocality ?? placemark.subAdministrativeArea,
                        city: placemark.locality ?? placemark.subAdministrativeArea,
                        province: placemark.administrativeArea,
                        country: placemark.country
                    )
                    _ = mapState.acceptPlaceDescriptor(descriptor, selectionRevision: revision)
                    return
                } catch {
                    guard !Task.isCancelled, mapState.selection.revision == revision else { return }
                    lastError = error
                    let nsError = error as NSError
                    let isNetworkError = nsError.domain == kCLErrorDomain
                        && nsError.code == CLError.network.rawValue
                    guard isNetworkError, attempt < retryDelays.count - 1 else { break }
                    RuntimeLogger.info("APP", "Geocode", "反向地理编码网络失败，准备重试", details: [
                        "attempt": String(attempt + 1),
                        "revision": String(revision)
                    ])
                }
            }

            guard !Task.isCancelled,
                  mapState.selection.revision == revision,
                  let lastError else { return }
            RuntimeLogger.warning("APP", "Geocode", "反向地理编码失败", details: [
                "error": lastError.localizedDescription,
                "revision": String(revision)
            ])
        }
    }

    private func doSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        searchRequestID &+= 1
        let requestID = searchRequestID
        isSearching = true
        searchError = ""
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                guard requestID == searchRequestID else { return }
                isSearching = false
                if let error {
                    searchResults = []
                    searchError = error.localizedDescription
                    return
                }
                let items = (response?.mapItems ?? []).prefix(6)
                // 用首个搜索结果坐标推算瓦片类型
                if let first = items.first {
                    let c = first.placemark.coordinate
                    if let newType = CoordinateConverter.detectTile(
                        resultCoord: (c.latitude, c.longitude),
                        userLocation: mapState.realtimeLocation
                    ) {
                        CoordinateConverter.currentTileType = newType
                    }
                }
                searchResults = items.map { item in
                    let r = SearchLocationResult(
                        name: item.name ?? "未命名",
                        subtitle: [item.placemark.locality, item.placemark.subLocality, item.placemark.thoroughfare]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        coordinate: item.placemark.coordinate
                    )
                    RuntimeLogger.info("APP", "搜索", "结果: \(r.name)", details: [
                        "lat": String(r.coordinate.latitude),
                        "lon": String(r.coordinate.longitude)
                    ])
                    return r
                }
                if searchResults.isEmpty { searchError = "没有找到相关地点" }
            }
        }
    }

    private func selectSearchResult(_ result: SearchLocationResult) {
        geocodeDebounceTask?.cancel()
        reverseGeocodeTask?.cancel()
        favorites.select(nil)
        CoordinateConverter.updateTileType(lat: result.coordinate.latitude, lon: result.coordinate.longitude)
        mapState.selectSearchResult(result.coordinate, name: result.name)
        let wgs = CoordinateConverter.toStored(lat: result.coordinate.latitude, lon: result.coordinate.longitude)
        LastCoordinateStore.save(lat: wgs.lat, lon: wgs.lon)
        searchText = result.name
        searchResults = []
        searchError = ""
    }

    private func deleteSearchResult(_ result: SearchLocationResult) {
        searchResults.removeAll { $0.id == result.id }
    }

    private func select(_ favorite: FavoriteLocation) {
        geocodeDebounceTask?.cancel()
        reverseGeocodeTask?.cancel()
        favorites.select(favorite.id)
        let display = CoordinateConverter.toDisplay(lat: favorite.latitude, lon: favorite.longitude)
        mapState.selectFavorite(
            CLLocationCoordinate2D(latitude: display.lat, longitude: display.lon),
            id: favorite.id,
            name: favorite.name
        )
        LastCoordinateStore.save(lat: favorite.latitude, lon: favorite.longitude)
    }

    private var enableTipSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ActivationTipContent(dismiss: {})
                    if activationTipCount >= 3 {
                        Button(role: .destructive) {
                            activationTipDisabled = true
                            showEnableTip = false
                        } label: {
                            Label("关闭不再弹出", systemImage: "bell.slash").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                }.padding(16)
            }
            .navigationTitle("虚拟定位已开启").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { showEnableTip = false } label: {
                    Text("知道了").font(.body.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.blue).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    private var disableTipSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DeactivationTipContent(dismiss: {})
                    RemoveProxyTipContent(dismiss: {})
                }.padding(16)
            }
            .navigationTitle("虚拟定位已关闭").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { showDisableTip = false } label: {
                    Text("知道了").font(.body.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.blue).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }
}
