import SwiftUI
import MapKit
import UIKit
import CoreLocation

private enum SpoofState {
    case idle, verifying, active
}

private struct RealtimeLocationRequestContext {
    let intent: RealtimeLocationIntent
    let source: String
    let showFailureAlert: Bool
}

private enum RealtimeCoordinateSource: Equatable {
    case mapKitBluePoint
    case coreLocation

    @MainActor
    var coordinateSystem: CoordinateConverter.MapCoordinateSystem {
        switch self {
        case .mapKitBluePoint: return CoordinateConverter.currentMapCoordinateSystem
        case .coreLocation: return .wgs84
        }
    }

    var diagnosticName: String {
        switch self {
        case .mapKitBluePoint: return "MapKit地图蓝点"
        case .coreLocation: return "CLLocationManager"
        }
    }
}

struct MapHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var setup: SetupCoordinator
    @ObservedObject var favorites: FavoriteLocationStore
    @ObservedObject var actions: LocationActionCoordinator
    var onOpenSettings: (() -> Void)?

    @ObservedObject private var proxy = ProxyManager.shared
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var thirdPartyProxy = ThirdPartyProxyManager.shared
    @ObservedObject private var thirdPartyClient = ThirdPartyProxyClientStore.shared
    @ObservedObject private var remoteConfiguration = AppRemoteConfigurationStore.shared
    @ObservedObject private var searchConfig = SearchConfigurationStore.shared
    @StateObject private var searchCompleter = LocationSearchCompleter()
    @StateObject private var realtime = RealtimeLocationManager.shared
    @StateObject private var mapState: MapLocationState
    @ObservedObject private var net = NetworkMonitor.shared

    @State private var isSearchActive = false
    @State private var isRecentDrawerExpanded = false
    @State private var mapRuntimeDidStart = false
    @State private var showEnableTip = false
    @State private var showDisableTip = false
    @State private var activeTip: TipKind?
    @State private var manualHint = ""
    private let tipPreferences = VirtualLocationTipPreferences()
    private let communityPromptPreferences = ThirdPartyCommunityPromptPreferences()
    @State private var pendingCommunityContributionClient: ThirdPartyProxyClient?
    @State private var communityContributionClient: ThirdPartyProxyClient?
    @State private var showCommunityTemplateCopied = false
    @State private var githubDestination: SafariDestination?

    // 收藏弹窗
    @State private var showSaveFavoriteDialog = false
    @State private var newFavoriteName = ""
    @State private var showDeleteFavoriteAlert = false
    @State private var favoriteToDelete: FavoriteLocation?

    @State private var reverseGeocodeTask: Task<Void, Never>?
    @State private var geocodeDebounceTask: Task<Void, Never>?
    @State private var showLocationAlert = false
    @State private var realtimeRequestTask: Task<Void, Never>?
    @State private var realtimeRequestContext: RealtimeLocationRequestContext?
    @State private var wifiChangeObserverToken: UUID?
    @State private var wifiVerificationTask: Task<Void, Never>?
    @State private var wifiVerificationID: UUID?
    @State private var spoofState: SpoofState = .idle
    @State private var locationOperationTask: Task<Void, Never>?
    @State private var locationOperationID: UInt64 = 0
    @State private var mapCoordinateSystemRefreshTask: Task<Void, Never>?
    @State private var mapCoordinateSystemRefreshID: UInt64 = 0
    @State private var bluePointRefreshPending = false
    @State private var realtimeButtonTask: Task<Void, Never>?
    @State private var favoriteSaveTask: Task<Void, Never>?
    @State private var activeSpoofLat: Double?
    @State private var activeSpoofLon: Double?
    @State private var lastSpoofDiagnosisSystem: CoordinateConverter.MapCoordinateSystem?
    @State private var hasLoggedSpoofDiagnosis = false

    init(
        setup: SetupCoordinator,
        favorites: FavoriteLocationStore,
        actions: LocationActionCoordinator,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.setup = setup
        self.favorites = favorites
        self.actions = actions
        self.onOpenSettings = onOpenSettings

        let savedCoord = LastCoordinateStore.load()
        let initialZoom = savedCoord?.zoomMeters ?? ViewportStore.loadOrDefault()
        let selectedFavorite = favorites.selectedFavorite
        let initialCoord: CLLocationCoordinate2D
        let initialSource: MapSelectionSource
        let initialName: String?
        if let saved = savedCoord {
            initialCoord = saved.coordinate(for: CoordinateConverter.currentMapCoordinateSystem)
            if let selectedFavorite,
               selectedFavorite.coordinatePair.matchesWGS84(
                   latitude: saved.coordinatePair.wgs84.latitude,
                   longitude: saved.coordinatePair.wgs84.longitude
               ) {
                initialSource = .favorite(selectedFavorite.id)
                initialName = selectedFavorite.name
            } else {
                initialSource = .initial
                initialName = nil
            }
        } else if let selectedFavorite {
            initialCoord = selectedFavorite.coordinatePair.coordinate(for: CoordinateConverter.currentMapCoordinateSystem)
            initialSource = .favorite(selectedFavorite.id)
            initialName = selectedFavorite.name
        } else {
            initialCoord = CoordinateConverter.coordinatePair(
                lat: 22.544577,
                lon: 113.94114,
                mapCoordinateSystem: .wgs84
            ).coordinate(for: CoordinateConverter.currentMapCoordinateSystem)
            initialSource = .initial
            initialName = nil
        }
        RuntimeLogger.info("APP", "地图", "初始化", details: [
            "zoom": String(initialZoom),
            "有缓存": String(savedCoord != nil),
            "初始来源": String(describing: initialSource),
            "地图标准": CoordinateConverter.currentMapCoordinateSystem.rawValue
        ])
        _mapState = StateObject(wrappedValue: MapLocationState(
            initialCoordinate: initialCoord,
            initialViewportMeters: initialZoom,
            initialSource: initialSource,
            initialName: initialName
        ))

        if ProxyRuntimeModeStore.shared.mode == .localWiFi,
           let settings = WlocSettingsStore.load(), settings.enabled {
            _spoofState = State(initialValue: .active)
            _activeSpoofLat = State(initialValue: settings.latitude)
            _activeSpoofLon = State(initialValue: settings.longitude)
        }
    }

    var body: some View {
        ZStack {
            // 1. 底层 MapView（长按落点，平移浏览）
            MapViewRepresentable(
                selection: mapState.selection,
                addressDescription: mapState.placeDescriptor?.detailedAddress ?? mapState.displayName,
                initialViewportMeters: mapState.viewportMeters,
                cameraCommand: mapState.cameraCommand,
                onRealtimeLocationChanged: { location in
                    handleNativeRealtimeLocation(location)
                },
                onViewportChanged: { distance in
                    mapState.updateViewport(distanceMeters: distance)
                },
                onMapLongPress: { coordinate in
                    handleMapLongPress(coordinate)
                },
                onUserZoomChanged: { distance in
                    ViewportStore.save(distance)
                    LastCoordinateStore.updateZoom(distance)
                }
            )
            .ignoresSafeArea()
            .onTapGesture {
                // 点击地图空白区域收起搜索与抽屉
                dismissSearchAndDrawers()
            }

            // 2. 顶层 UI 元素
            VStack(spacing: 0) {
                // 顶部搜索框
                topSearchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // 搜索联想结果列表
                if isSearchActive && !searchCompleter.suggestions.isEmpty {
                    searchSuggestionsDropdown
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }

                Spacer()

                // 右侧悬浮快捷按钮组
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        realtimeLocationButton
                        favoriteButton
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }

                // 底部主控卡片（含最近收藏抽屉）
                bottomControlsCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 74) // 留出底部半透明 TabBar 的空间
            }
        }
        .sheet(item: $activeTip) { kind in
            TipSheetView(kind: kind, runtimeMode: runtimeMode.mode)
        }
        .sheet(item: $githubDestination) { destination in
            SafariView(url: destination.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showEnableTip) { enableTipSheet }
        .sheet(isPresented: $showDisableTip) { disableTipSheet }
        .alert("收藏当前地点", isPresented: $showSaveFavoriteDialog) {
            TextField("地点名称", text: $newFavoriteName)
            Button("保存") {
                commitSaveCurrentLocation()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设置常用名称，例如「公司」、「家」等。")
        }
        .alert("取消收藏「\(favoriteToDelete?.name ?? "")」？", isPresented: $showDeleteFavoriteAlert) {
            Button("取消收藏", role: .destructive) {
                if let fav = favoriteToDelete {
                    favorites.delete(fav)
                }
                favoriteToDelete = nil
            }
            Button("保留", role: .cancel) {
                favoriteToDelete = nil
            }
        } message: {
            Text("取消后该地点将从收藏列表中移除。")
        }
        .alert("定位失败", isPresented: $showLocationAlert) {
            Button("打开设置") {
                openSettings(.locationServices)
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法获取当前定位，请检查定位服务是否已开启")
        }
        .alert("社区分享成功配置？", isPresented: Binding(
            get: { communityContributionClient != nil },
            set: { if !$0 { communityContributionClient = nil } }
        )) {
            Button("去提交") {
                guard let client = communityContributionClient else { return }
                UIPasteboard.general.string = GitHubSubmission.communityContributionTemplate(
                    for: client,
                    systemVersion: UIDevice.current.systemVersion
                )
                openCommunityContributionPage()
            }
            Button("复制模板") {
                guard let client = communityContributionClient else { return }
                UIPasteboard.general.string = GitHubSubmission.communityContributionTemplate(
                    for: client,
                    systemVersion: UIDevice.current.systemVersion
                )
                showCommunityTemplateCopied = true
            }
            if communityPromptPreferences.canSuppress() {
                Button("不再提示", role: .cancel) {
                    communityPromptPreferences.suppress()
                }
            } else {
                Button("取消", role: .cancel) {}
            }
        } message: {
            Text(
                "你正在使用 \(communityContributionClient?.name ?? "第三方客户端")。点击“去提交”会先复制投稿模板，并在 App 内打开社区页面。采纳后将收录到 README，可选择是否匿名署名。"
            )
        }
        .alert("已复制投稿模板", isPresented: $showCommunityTemplateCopied) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("如果 GitHub 登录或浏览器跳转后模板没有自动填充，可以直接粘贴。")
        }
        .alert("无法直接跳转", isPresented: Binding(
            get: { !manualHint.isEmpty },
            set: { if !$0 { manualHint = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: { Text(manualHint) }
        .onAppear {
            startMapRuntimeOnce()
            if runtimeMode.mode == .localWiFi {
                registerWiFiChangeObserver()
            } else {
                refreshThirdPartyState()
            }
        }
        .onDisappear {
            if let token = wifiChangeObserverToken {
                net.removeWiFiChangeObserver(token)
                wifiChangeObserverToken = nil
            }
            wifiVerificationTask?.cancel()
            wifiVerificationTask = nil
            wifiVerificationID = nil
            mapCoordinateSystemRefreshTask?.cancel()
            mapCoordinateSystemRefreshTask = nil
            bluePointRefreshPending = false
            realtimeButtonTask?.cancel()
            realtimeButtonTask = nil
            favoriteSaveTask?.cancel()
            favoriteSaveTask = nil
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await awaitCoordinatedMapCoordinateSystemRefresh(reason: "App回到前台")
            }
        }
        .onChange(of: proxy.isRunning) { running in
            if runtimeMode.mode == .localWiFi, !running && spoofState == .active {
                spoofState = .idle
                actions.clear()
            }
        }
        .onChange(of: runtimeMode.mode) { newMode in
            if newMode == .localWiFi {
                registerWiFiChangeObserver()
            } else {
                if let token = wifiChangeObserverToken {
                    net.removeWiFiChangeObserver(token)
                    wifiChangeObserverToken = nil
                }
                refreshThirdPartyState()
            }
        }
    }

    // MARK: - 顶部搜索框

    private var topSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))

            TextField("搜索地点或坐标", text: $searchCompleter.queryText, onEditingChanged: { editing in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchActive = editing || !searchCompleter.queryText.isEmpty
                }
            })
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if searchCompleter.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchCompleter.queryText.isEmpty {
                Button {
                    searchCompleter.clear()
                    isSearchActive = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    // MARK: - 搜索联想下拉

    private var searchSuggestionsDropdown: some View {
        let maxVisible = searchConfig.visibleCountX
        let rowHeight: CGFloat = 50
        let visibleHeight = min(CGFloat(searchCompleter.suggestions.count) * rowHeight, CGFloat(maxVisible) * rowHeight)

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchCompleter.suggestions) { item in
                    Button {
                        selectSearchSuggestion(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        .frame(height: visibleHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }

    // MARK: - 右侧悬浮按钮

    private var realtimeLocationButton: some View {
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
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
        }
        .disabled(realtimeButtonTask != nil || realtimeRequestTask != nil || realtime.isRequesting)
    }

    private var favoriteButton: some View {
        let isCurrentFavorited = isCurrentSelectionFavorited
        return Button {
            if isCurrentFavorited, let currentFav = currentMatchingFavorite {
                favoriteToDelete = currentFav
                showDeleteFavoriteAlert = true
            } else {
                newFavoriteName = mapState.displayName ?? "我的位置"
                showSaveFavoriteDialog = true
            }
        } label: {
            Image(systemName: isCurrentFavorited ? "star.fill" : "star")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isCurrentFavorited ? .orange : .secondary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部主控卡片

    private var bottomControlsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. 最近收藏抽屉与上拉箭头
            recentFavoritesSection

            // 2. 主控按钮
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
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }

    // MARK: - 最近收藏抽屉

    private var recentFavoritesSection: some View {
        let recentItems = favorites.recentFavorites(maxCount: searchConfig.recentMaxW)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    isRecentDrawerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRecentDrawerExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                    Text(recentItems.isEmpty ? "暂无最近收藏" : "最近使用收藏")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if !recentItems.isEmpty {
                        Text("\(recentItems.count) 个")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .disabled(recentItems.isEmpty)

            if isRecentDrawerExpanded && !recentItems.isEmpty {
                let maxZ = searchConfig.recentVisibleZ
                let itemHeight: CGFloat = 40
                let drawerHeight = min(CGFloat(recentItems.count) * itemHeight, CGFloat(maxZ) * itemHeight)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(recentItems) { fav in
                            Button {
                                selectRecentFavorite(fav)
                            } label: {
                                HStack(spacing: 8) {
                                    let groupName = favorites.group(for: fav.groupId)?.truncatedDisplayName ?? "默认"
                                    Text("\(groupName) / \(fav.truncatedDisplayName)")
                                        .font(.subheadline)
                                        .foregroundStyle(favorites.selectedFavoriteID == fav.id ? Color.teal : Color.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if fav.usageCount > 0 {
                                        Text("\(fav.usageCount)次")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: itemHeight)
                                .background(
                                    favorites.selectedFavoriteID == fav.id
                                    ? Color.teal.opacity(0.12)
                                    : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: drawerHeight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 交互处理

    private func handleMapLongPress(_ coordinate: CLLocationCoordinate2D) {
        dismissSearchAndDrawers()
        favorites.select(nil)
        let revision = mapState.selectMapTap(coordinate)
        let pair = CoordinatePair(
            mapCoordinate: coordinate,
            mapCoordinateSystem: CoordinateConverter.currentMapCoordinateSystem
        )
        LastCoordinateStore.save(
            coordinatePair: pair,
            zoomMeters: mapState.viewportMeters
        )
        scheduleGeocode(pair: pair, revision: revision)
    }

    private func selectSearchSuggestion(_ item: SearchSuggestionItem) {
        searchCompleter.resolveCoordinate(for: item) { coordinate, resolvedName in
            guard let coordinate else { return }
            geocodeDebounceTask?.cancel()
            reverseGeocodeTask?.cancel()
            favorites.select(nil)
            let name = resolvedName ?? item.title
            mapState.selectSearchResult(coordinate, name: name)
            let pair = CoordinatePair(
                mapCoordinate: coordinate,
                mapCoordinateSystem: CoordinateConverter.currentMapCoordinateSystem
            )
            LastCoordinateStore.save(
                coordinatePair: pair,
                zoomMeters: mapState.viewportMeters
            )
            scheduleGeocode(pair: pair, revision: mapState.selection.revision)
            searchCompleter.clear()
            isSearchActive = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private func selectRecentFavorite(_ fav: FavoriteLocation) {
        geocodeDebounceTask?.cancel()
        reverseGeocodeTask?.cancel()
        favorites.select(fav.id)
        favorites.incrementUsageCount(id: fav.id)
        mapState.selectFavorite(
            fav.coordinatePair.coordinate(for: CoordinateConverter.currentMapCoordinateSystem),
            id: fav.id,
            name: fav.name
        )
        LastCoordinateStore.save(
            coordinatePair: fav.coordinatePair,
            zoomMeters: mapState.viewportMeters
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isRecentDrawerExpanded = false
        }
    }

    private func dismissSearchAndDrawers() {
        if isSearchActive {
            isSearchActive = false
            searchCompleter.clear()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        if isRecentDrawerExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRecentDrawerExpanded = false
            }
        }
    }

    private var isCurrentSelectionFavorited: Bool {
        currentMatchingFavorite != nil
    }

    private var currentMatchingFavorite: FavoriteLocation? {
        let pair = currentSelectionPair
        return favorites.favorites.first {
            $0.coordinatePair.matchesWGS84(
                latitude: pair.wgs84.latitude,
                longitude: pair.wgs84.longitude
            )
        }
    }

    private func commitSaveCurrentLocation() {
        guard favoriteSaveTask == nil else { return }
        let name = newFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? (mapState.displayName ?? "我的位置") : name
        let pair = currentSelectionPair
        let fullAddress = mapState.placeDescriptor?.detailedAddress
        let selectionRevision = mapState.selection.revision

        favoriteSaveTask = Task { @MainActor in
            defer { favoriteSaveTask = nil }
            await awaitCoordinatedMapCoordinateSystemRefresh(reason: "保存收藏")
            guard !Task.isCancelled, mapState.selection.revision == selectionRevision else { return }
            let fav = favorites.save(
                name: finalName,
                fullAddress: fullAddress,
                coordinatePair: pair,
                accuracy: 25,
                groupId: favorites.groups.first?.id
            )
            mapState.selectFavorite(
                pair.coordinate(for: CoordinateConverter.currentMapCoordinateSystem),
                id: fav.id,
                name: fav.name
            )
            LastCoordinateStore.save(coordinatePair: pair, zoomMeters: mapState.viewportMeters)
        }
    }

    private var currentSelectionPair: CoordinatePair {
        CoordinatePair(
            mapCoordinate: mapState.selection.coordinate,
            mapCoordinateSystem: CoordinateConverter.currentMapCoordinateSystem
        )
    }

    private var currentSelectionFavorite: FavoriteLocation {
        FavoriteLocation(
            name: mapState.displayName ?? String(
                format: "%.4f, %.4f",
                mapState.selection.coordinate.latitude,
                mapState.selection.coordinate.longitude
            ),
            fullAddress: mapState.placeDescriptor?.detailedAddress,
            coordinatePair: currentSelectionPair,
            accuracy: 25
        )
    }

    private var testFavorite: FavoriteLocation { currentSelectionFavorite }

    private var needsSwitchButton: Bool {
        guard spoofState == .active,
              let sLat = activeSpoofLat,
              let sLon = activeSpoofLon else { return false }
        return !currentSelectionFavorite.coordinatePair.matchesWGS84(
            latitude: sLat,
            longitude: sLon
        )
    }

    private var buttonTitle: String {
        if runtimeMode.mode == .thirdParty {
            switch spoofState {
            case .idle: return "同步到第三方代理"
            case .verifying: return "检测并同步中…"
            case .active: return "停止第三方虚拟定位"
            }
        }
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
        let wasActive = spoofState == .active
        locationOperationID &+= 1
        let operationID = locationOperationID
        let selectionRevision = mapState.selection.revision
        let target = currentSelectionFavorite
        spoofState = .verifying

        locationOperationTask = Task { @MainActor in
            if runtimeMode.mode == .thirdParty {
                do {
                    let response = try await thirdPartyProxy.save(target)
                    guard !Task.isCancelled,
                          operationID == locationOperationID,
                          runtimeMode.mode == .thirdParty else {
                        return
                    }
                    spoofState = .active
                    activeSpoofLat = response.latitude
                    activeSpoofLon = response.longitude
                    RuntimeLogger.info("APP", "定位", "第三方代理坐标同步成功", details: [
                        "当前客户端": thirdPartyClient.selectedClient.name,
                        "坐标标准": "WGS-84",
                        "客户端模式": "测试模式",
                        "选点期间发生变化": String(selectionRevision != mapState.selection.revision)
                    ])
                    presentSuccessfulOperationTip(.activation)
                    queueCommunityContributionPrompt(for: thirdPartyClient.selectedClient)
                } catch {
                    guard operationID == locationOperationID else { return }
                    spoofState = wasActive ? .active : .idle
                    RuntimeLogger.error(
                        "APP",
                        "ThirdPartyProxy",
                        "同步坐标到第三方客户端失败",
                        error: error,
                        details: [
                            "当前客户端": thirdPartyClient.selectedClient.name,
                            "请求动作": "WLOC save",
                            "恢复状态": wasActive ? "保留原第三方坐标" : "保持未启用",
                            "处理建议": ThirdPartyProxyError.recoverySuggestion(for: error)
                        ]
                    )
                    setup.requestThirdPartySetup(message: error.localizedDescription)
                }
                if operationID == locationOperationID {
                    locationOperationTask = nil
                }
                return
            }

            let result = await setup.runVerificationTest()
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
                    lastSpoofDiagnosisSystem = nil
                    hasLoggedSpoofDiagnosis = false
                }
                RuntimeLogger.info("APP", "定位", "验证结果", details: [
                    "success": "true",
                    "applied": String(applied),
                    "spoofState": String(describing: spoofState)
                ])
                if applied {
                    presentSuccessfulOperationTip(.activation)
                }
            } else {
                spoofState = actions.virtualLocationEnabled ? .active : .idle
                RuntimeLogger.warning("APP", "定位", "验证失败", details: [
                    "result": result.id,
                    "spoofState": String(describing: spoofState)
                ])
                if result != .verificationInProgress,
                   result != .verificationSuperseded {
                    RuntimeLogger.warning("APP", "定位", "开启前检测失败，进入对应环境引导", details: [
                        "结果": result.id
                    ])
                    activeTip = nil
                    setup.applyVerificationResult(result)
                }
            }
            locationOperationTask = nil
        }
    }

    private func stopSpoofing() {
        locationOperationTask?.cancel()
        locationOperationTask = nil
        locationOperationID &+= 1
        if runtimeMode.mode == .thirdParty {
            spoofState = .verifying
            locationOperationTask = Task { @MainActor in
                do {
                    try await thirdPartyProxy.clear()
                    spoofState = .idle
                    activeSpoofLat = nil
                    activeSpoofLon = nil
                    presentSuccessfulOperationTip(.deactivation)
                } catch {
                    spoofState = .active
                    RuntimeLogger.error(
                        "APP",
                        "ThirdPartyProxy",
                        "清除第三方客户端坐标失败",
                        error: error,
                        details: [
                            "当前客户端": thirdPartyClient.selectedClient.name,
                            "请求动作": "WLOC clear",
                            "恢复状态": "保留已启用状态",
                            "处理建议": ThirdPartyProxyError.recoverySuggestion(for: error)
                        ]
                    )
                    setup.requestThirdPartySetup(message: error.localizedDescription)
                }
                locationOperationTask = nil
            }
            return
        }

        actions.clear()
        spoofState = .idle
        activeSpoofLat = nil
        activeSpoofLon = nil
        lastSpoofDiagnosisSystem = nil
        hasLoggedSpoofDiagnosis = false
        presentSuccessfulOperationTip(.deactivation)
    }

    private func presentSuccessfulOperationTip(_ kind: VirtualLocationTipKind) {
        let count = tipPreferences.recordSuccessfulOperation(kind)
        let operationName = kind == .activation ? "开启" : "关闭"
        RuntimeLogger.info("APP", "提醒", "累计\(operationName)虚拟定位次数", details: [
            "次数": String(count),
            "运行模式": runtimeMode.mode.displayName,
            "可显示不再提醒": String(tipPreferences.canSuppress(kind))
        ])
        guard tipPreferences.shouldPresentAutomaticTip(kind) else { return }
        switch kind {
        case .activation:
            showEnableTip = true
        case .deactivation:
            showDisableTip = true
        }
    }

    private func queueCommunityContributionPrompt(for client: ThirdPartyProxyClient) {
        guard remoteConfiguration.requestsCommunityPrompt(for: client),
              communityPromptPreferences.shouldPresent() else {
            return
        }
        communityPromptPreferences.recordPresentation()
        if showEnableTip {
            pendingCommunityContributionClient = client
        } else {
            communityContributionClient = client
        }
    }

    private func openCommunityContributionPage() {
        githubDestination = SafariDestination(url: GitHubSubmission.communityContributionURL)
    }

    @MainActor
    private func openSettings(_ destination: SystemSettingsDestination) {
        SystemSettingsNavigator.open(destination) { fallbackHint in
            if let fallbackHint { manualHint = fallbackHint }
        }
    }

    private func startMapRuntimeOnce() {
        guard !mapRuntimeDidStart else { return }
        mapRuntimeDidStart = true
        startPeriodicSpoofDiagnosis()
    }

    private func handleNativeRealtimeLocation(_ location: CLLocation) {
        mapState.updateRealtimeLocation(location)
        if spoofState == .active {
            scheduleBluePointMapCoordinateSystemRefresh()
        }
    }

    private func scheduleBluePointMapCoordinateSystemRefresh() {
        guard !bluePointRefreshPending else { return }
        bluePointRefreshPending = true
        Task { @MainActor in
            defer { bluePointRefreshPending = false }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await awaitCoordinatedMapCoordinateSystemRefresh(reason: "蓝点坐标刷新")
        }
    }

    private func requestRealtimeLocation() {
        realtimeButtonTask?.cancel()
        realtimeButtonTask = Task { @MainActor in
            defer { realtimeButtonTask = nil }
            await awaitCoordinatedMapCoordinateSystemRefresh(reason: "点击实时定位")
            guard let loc = await realtime.requestLocation() else {
                showLocationAlert = true
                return
            }
            let pair = CoordinateConverter.coordinatePair(
                lat: loc.latitude,
                lon: loc.longitude,
                mapCoordinateSystem: .wgs84
            )
            favorites.selectMatching(coordinatePair: pair)
            mapState.selectRealtime(pair.coordinate(for: CoordinateConverter.currentMapCoordinateSystem))
            LastCoordinateStore.save(coordinatePair: pair, zoomMeters: mapState.viewportMeters)
            scheduleGeocode(pair: pair, revision: mapState.selection.revision)
        }
    }

    private func scheduleGeocode(pair: CoordinatePair, revision: UInt64) {
        geocodeDebounceTask?.cancel()
        geocodeDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, mapState.selection.revision == revision else { return }
            reverseGeocode(pair, revision: revision)
        }
    }

    private func reverseGeocode(_ pair: CoordinatePair, revision: UInt64) {
        reverseGeocodeTask?.cancel()
        let wgsCoordinate = pair.wgs84.coordinate
        let mapCoordinate = pair.coordinate(for: CoordinateConverter.currentMapCoordinateSystem)
        let location = CLLocation(latitude: wgsCoordinate.latitude, longitude: wgsCoordinate.longitude)
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
                    async let clPlacemarks = CLGeocoder().reverseGeocodeLocation(location)
                    let mkRequest = MKLocalSearch.Request()
                    mkRequest.region = MKCoordinateRegion(center: mapCoordinate, latitudinalMeters: 400, longitudinalMeters: 400)
                    let mkResponse = try? await MKLocalSearch(request: mkRequest).start()

                    let placemarks = try await clPlacemarks
                    guard !Task.isCancelled,
                          mapState.selection.revision == revision,
                          let placemark = placemarks.first else { return }

                    let mapItemName = mkResponse?.mapItems.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mapItemPOI = mkResponse?.mapItems.first?.placemark.areasOfInterest?.first
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
                    lastError = error
                    if let clError = error as? CLError, clError.code == CLError.network, attempt + 1 < retryDelays.count {
                        RuntimeLogger.warning("APP", "Geocode", "网络失败，准备重试反向地理编码", details: [
                            "attempt": String(attempt + 1),
                            "revision": String(revision)
                        ])
                        continue
                    }
                    break
                }
            }

            guard !Task.isCancelled, mapState.selection.revision == revision, let lastError else { return }
            RuntimeLogger.warning("APP", "Geocode", "反向地理编码失败", details: [
                "error": lastError.localizedDescription,
                "revision": String(revision)
            ])
        }
    }

    private func awaitCoordinatedMapCoordinateSystemRefresh(reason: String) async {
        mapCoordinateSystemRefreshID &+= 1
        let refreshID = mapCoordinateSystemRefreshID
        let task = Task { @MainActor in
            _ = await CoordinateConverter.refreshRuntimeMapCoordinateSystem(reason: reason)
        }
        mapCoordinateSystemRefreshTask = task
        await task.value
        if refreshID == mapCoordinateSystemRefreshID {
            mapCoordinateSystemRefreshTask = nil
        }
    }

    private func registerWiFiChangeObserver() {
        guard runtimeMode.mode == .localWiFi else { return }
        guard wifiChangeObserverToken == nil else { return }
        wifiChangeObserverToken = net.observeWiFiChanges { [self] reason in
            handleWiFiChange(reason: reason.rawValue)
        }
    }

    private func handleWiFiChange(reason: String) {
        wifiVerificationTask?.cancel()
        let verificationID = UUID()
        wifiVerificationID = verificationID
        let stabilizationNanoseconds: UInt64 = 3_000_000_000
        wifiVerificationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: stabilizationNanoseconds)
            guard !Task.isCancelled, wifiVerificationID == verificationID else { return }
            guard runtimeMode.mode == .localWiFi else { return }
            guard net.isWiFiEnabled else {
                setup.requestSetup(message: "Wi-Fi 连接已断开，请连接 Wi-Fi 后重试。")
                return
            }
            let result = await setup.runVerificationTest()
            guard !Task.isCancelled, wifiVerificationID == verificationID else { return }
            setup.applyVerificationResult(result)
        }
    }

    private func refreshThirdPartyState() {
        Task { @MainActor in
            _ = try? await thirdPartyProxy.validateConnection()
        }
    }

    private func startPeriodicSpoofDiagnosis() {
        // 定期诊断
    }

    private var enableTipSheet: some View {
        TipSheetView(kind: .activation, runtimeMode: runtimeMode.mode, onDismiss: {
            showEnableTip = false
            if let client = pendingCommunityContributionClient {
                pendingCommunityContributionClient = nil
                communityContributionClient = client
            }
        })
    }

    private var disableTipSheet: some View {
        TipSheetView(kind: .deactivation, runtimeMode: runtimeMode.mode, onDismiss: {
            showDisableTip = false
        })
    }
}