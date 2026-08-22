import CoreLocation
import Foundation

struct FavoriteGroup: Codable, Identifiable, Equatable, Hashable {
    static let defaultGroupId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var sortOrder: Int
    var isDefault: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = String(name.prefix(10))
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    static var defaultGroup: FavoriteGroup {
        FavoriteGroup(
            id: defaultGroupId,
            name: "默认分组",
            sortOrder: 0,
            isDefault: true
        )
    }

    /// 中间省略格式化：最多展示 3 个字（不算省略号），过长如“默认新分组” -> “默认...组”
    var truncatedDisplayName: String {
        FavoriteDisplayFormatter.truncateMiddle(name, maxChars: 3)
    }
}

struct FavoriteLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var groupId: UUID
    var name: String
    var fullAddress: String?
    var coordinatePair: CoordinatePair
    var accuracy: Int
    var usageCount: Int
    var sortOrder: Int
    var createdAt: Date
    private var wasDecodedFromLegacyCoordinates = false

    /// WGS-84 compatibility accessor. WLOC consumers must use this value.
    var latitude: Double { coordinatePair.wgs84.latitude }
    var longitude: Double { coordinatePair.wgs84.longitude }
    var isLegacyCoordinateRecord: Bool { wasDecodedFromLegacyCoordinates }

    init(
        id: UUID = UUID(),
        groupId: UUID = FavoriteGroup.defaultGroupId,
        name: String,
        fullAddress: String? = nil,
        coordinatePair: CoordinatePair,
        accuracy: Int,
        usageCount: Int = 0,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.name = name
        self.fullAddress = fullAddress
        self.coordinatePair = coordinatePair
        self.accuracy = accuracy
        self.usageCount = usageCount
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        groupId: UUID = FavoriteGroup.defaultGroupId,
        name: String,
        fullAddress: String? = nil,
        latitude: Double,
        longitude: Double,
        accuracy: Int,
        usageCount: Int = 0,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        mapCoordinateSystem: CoordinateConverter.MapCoordinateSystem = .gcj02
    ) {
        self.init(
            id: id,
            groupId: groupId,
            name: name,
            fullAddress: fullAddress,
            coordinatePair: CoordinateConverter.coordinatePair(lat: latitude, lon: longitude, mapCoordinateSystem: mapCoordinateSystem),
            accuracy: accuracy,
            usageCount: usageCount,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, groupId, name, fullAddress, coordinatePair, accuracy, usageCount, sortOrder, createdAt, latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId) ?? FavoriteGroup.defaultGroupId
        name = try container.decode(String.self, forKey: .name)
        fullAddress = try container.decodeIfPresent(String.self, forKey: .fullAddress)
        accuracy = try container.decode(Int.self, forKey: .accuracy)
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let pair = try container.decodeIfPresent(CoordinatePair.self, forKey: .coordinatePair) {
            coordinatePair = pair
        } else {
            let latitude = try container.decode(Double.self, forKey: .latitude)
            let longitude = try container.decode(Double.self, forKey: .longitude)
            coordinatePair = CoordinateConverter.legacyCoordinatePair(lat: latitude, lon: longitude)
            wasDecodedFromLegacyCoordinates = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(fullAddress, forKey: .fullAddress)
        try container.encode(coordinatePair, forKey: .coordinatePair)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encode(usageCount, forKey: .usageCount)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
    }

    /// 抽屉展示名称：最多 3 个字，超出末尾加“...”
    var truncatedDisplayName: String {
        FavoriteDisplayFormatter.truncateEnd(name, maxChars: 3)
    }
}

enum FavoriteDisplayFormatter {
    /// 中间省略：例如“默认特别长分组” -> “默认...组” (最多展示 maxChars 个字)
    static func truncateMiddle(_ text: String, maxChars: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let prefixCount = max(1, maxChars - 1)
        let prefix = String(trimmed.prefix(prefixCount))
        let suffix = String(trimmed.suffix(1))
        return "\(prefix)...\(suffix)"
    }

    /// 结尾省略：例如“秣陵路东段” -> “秣陵路...”
    static func truncateEnd(_ text: String, maxChars: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        return "\(String(trimmed.prefix(maxChars)))..."
    }
}

struct MapConfiguration: Equatable {
    let showsUserLocation: Bool
    let allowsCurrentLocationRequest: Bool

    static let `default` = MapConfiguration(showsUserLocation: false, allowsCurrentLocationRequest: false)
}

final class FavoriteLocationStore: ObservableObject {
    private enum Keys {
        static let groups = "favorite_groups"
        static let favorites = "favorite_locations"
        static let selectedID = "favorite_locations_selected_id"
    }

    @Published private(set) var groups: [FavoriteGroup]
    @Published private(set) var favorites: [FavoriteLocation]
    @Published private(set) var selectedFavoriteID: UUID?
    private let defaults: UserDefaults
    private var saveTask: Task<Void, Never>?

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults

        // 1. 加载分组
        if let gData = defaults.data(forKey: Keys.groups),
           let decodedGroups = try? JSONDecoder().decode([FavoriteGroup].self, from: gData),
           !decodedGroups.isEmpty {
            self.groups = decodedGroups.sorted(by: { $0.sortOrder < $1.sortOrder })
        } else {
            self.groups = [FavoriteGroup.defaultGroup]
        }

        // 确保默认分组一定存在
        if !self.groups.contains(where: { $0.isDefault || $0.id == FavoriteGroup.defaultGroupId }) {
            self.groups.insert(FavoriteGroup.defaultGroup, at: 0)
        }

        // 2. 加载收藏项
        if let data = defaults.data(forKey: Keys.favorites),
           let decoded = try? JSONDecoder().decode([FavoriteLocation].self, from: data) {
            let defaultId = self.groups.first?.id ?? FavoriteGroup.defaultGroupId
            self.favorites = decoded.map { loc in
                var item = loc
                if !self.groups.contains(where: { $0.id == item.groupId }) {
                    item.groupId = defaultId
                }
                return item
            }
        } else {
            self.favorites = []
        }

        self.selectedFavoriteID = defaults.string(forKey: Keys.selectedID).flatMap(UUID.init(uuidString:))
    }

    var selectedFavorite: FavoriteLocation? {
        guard let selectedFavoriteID else { return nil }
        return favorites.first(where: { $0.id == selectedFavoriteID })
    }

    // MARK: - 分组操作

    @discardableResult
    func addGroup(name: String) -> FavoriteGroup {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let finalName = trimmed.isEmpty ? "新分组" : trimmed
        let maxOrder = groups.map(\.sortOrder).max() ?? 0
        let group = FavoriteGroup(
            name: finalName,
            sortOrder: maxOrder + 1,
            isDefault: false
        )
        groups.append(group)
        persistAsync()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        guard !trimmed.isEmpty else { return }
        groups[idx].name = trimmed
        persistAsync()
    }

    func deleteGroup(_ id: UUID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        // 默认分组且没有其他分组时不允许删除
        if group.isDefault && groups.count <= 1 {
            return
        }
        // 连带删除该分组下的所有收藏
        favorites.removeAll { $0.groupId == id }
        groups.removeAll { $0.id == id }

        // 如果删除了默认分组且还有其他分组，将第一个分组设为默认
        if group.isDefault, let first = groups.first {
            if let idx = groups.firstIndex(where: { $0.id == first.id }) {
                groups[idx].isDefault = true
            }
        }

        if let selectedId = selectedFavoriteID, !favorites.contains(where: { $0.id == selectedId }) {
            selectedFavoriteID = nil
            defaults.removeObject(forKey: Keys.selectedID)
        }
        persistAsync()
    }

    func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        for (index, _) in groups.enumerated() {
            groups[index].sortOrder = index
        }
        persistAsync()
    }

    func group(for id: UUID) -> FavoriteGroup? {
        groups.first(where: { $0.id == id })
    }

    // MARK: - 收藏操作

    func locations(in groupId: UUID) -> [FavoriteLocation] {
        favorites.filter { $0.groupId == groupId }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    @discardableResult
    func save(
        name: String,
        fullAddress: String? = nil,
        mapCoordinate: CLLocationCoordinate2D,
        mapCoordinateSystem: CoordinateConverter.MapCoordinateSystem,
        accuracy: Int,
        groupId: UUID? = nil
    ) -> FavoriteLocation {
        save(
            FavoriteLocation(
                groupId: groupId ?? groups.first?.id ?? FavoriteGroup.defaultGroupId,
                name: name,
                fullAddress: fullAddress,
                coordinatePair: .init(mapCoordinate: mapCoordinate, mapCoordinateSystem: mapCoordinateSystem),
                accuracy: accuracy
            )
        )
    }

    @discardableResult
    func save(
        name: String,
        fullAddress: String? = nil,
        coordinatePair: CoordinatePair,
        accuracy: Int,
        groupId: UUID? = nil
    ) -> FavoriteLocation {
        save(
            FavoriteLocation(
                groupId: groupId ?? groups.first?.id ?? FavoriteGroup.defaultGroupId,
                name: name,
                fullAddress: fullAddress,
                coordinatePair: coordinatePair,
                accuracy: accuracy
            )
        )
    }

    @discardableResult
    private func save(_ favorite: FavoriteLocation) -> FavoriteLocation {
        var mutableFav = favorite
        if mutableFav.groupId == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ||
            !groups.contains(where: { $0.id == mutableFav.groupId }) {
            mutableFav.groupId = groups.first?.id ?? FavoriteGroup.defaultGroupId
        }

        // 经纬度去重（同位置则替换）
        favorites.removeAll {
            abs($0.coordinatePair.wgs84.latitude - mutableFav.coordinatePair.wgs84.latitude) < 0.000001
                && abs($0.coordinatePair.wgs84.longitude - mutableFav.coordinatePair.wgs84.longitude) < 0.000001
        }

        let maxOrder = favorites.filter({ $0.groupId == mutableFav.groupId }).map(\.sortOrder).max() ?? 0
        mutableFav.sortOrder = maxOrder + 1
        favorites.insert(mutableFav, at: 0)
        select(mutableFav.id)
        persistAsync()
        return mutableFav
    }

    @discardableResult
    func save(
        name: String,
        latitude: Double,
        longitude: Double,
        accuracy: Int,
        mapCoordinateSystem: CoordinateConverter.MapCoordinateSystem = .gcj02
    ) -> FavoriteLocation {
        save(
            name: name,
            fullAddress: nil,
            mapCoordinate: .init(latitude: latitude, longitude: longitude),
            mapCoordinateSystem: mapCoordinateSystem,
            accuracy: accuracy,
            groupId: nil
        )
    }

    func select(_ id: UUID?) {
        selectedFavoriteID = id
        if let id {
            defaults.set(id.uuidString, forKey: Keys.selectedID)
        } else {
            defaults.removeObject(forKey: Keys.selectedID)
        }
    }

    @discardableResult
    func selectMatching(coordinatePair: CoordinatePair) -> FavoriteLocation? {
        let matchingFavorite = favorites.first {
            $0.coordinatePair.matchesWGS84(
                latitude: coordinatePair.wgs84.latitude,
                longitude: coordinatePair.wgs84.longitude
            )
        }
        select(matchingFavorite?.id)
        return matchingFavorite
    }

    func incrementUsageCount(id: UUID) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].usageCount += 1
        persistAsync()
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].name = name
        persistAsync()
    }

    func updateAddress(_ id: UUID, address: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].fullAddress = address
        persistAsync()
    }

    func delete(_ favorite: FavoriteLocation) {
        favorites.removeAll { $0.id == favorite.id }
        if selectedFavoriteID == favorite.id {
            selectedFavoriteID = nil
            defaults.removeObject(forKey: Keys.selectedID)
        }
        persistAsync()
    }

    func moveLocations(inGroupId groupId: UUID, from source: IndexSet, to destination: Int) {
        var groupItems = locations(in: groupId)
        groupItems.move(fromOffsets: source, toOffset: destination)
        for (index, item) in groupItems.enumerated() {
            if let idx = favorites.firstIndex(where: { $0.id == item.id }) {
                favorites[idx].sortOrder = index
            }
        }
        persistAsync()
    }

    func moveLocation(id: UUID, toGroupId newGroupId: UUID) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        guard groups.contains(where: { $0.id == newGroupId }) else { return }
        favorites[idx].groupId = newGroupId
        let maxOrder = favorites.filter({ $0.groupId == newGroupId }).map(\.sortOrder).max() ?? 0
        favorites[idx].sortOrder = maxOrder + 1
        persistAsync()
    }

    /// 最近使用收藏列表：按使用次数倒序，再按创建时间倒序
    func recentFavorites(maxCount: Int) -> [FavoriteLocation] {
        let sorted = favorites.sorted { lhs, rhs in
            if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }
            return lhs.createdAt > rhs.createdAt
        }
        return Array(sorted.prefix(max(1, maxCount)))
    }

    func migrateLegacyCoordinates() throws {
        guard favorites.contains(where: \.isLegacyCoordinateRecord) else { return }
        try persist()
    }

    private func persistAsync() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            do {
                try persist()
            } catch {
                RuntimeLogger.error("APP", "收藏", "保存收藏持久化失败", error: error)
            }
        }
    }

    private func persist() throws {
        let gData = try JSONEncoder().encode(groups)
        let fData = try JSONEncoder().encode(favorites)
        defaults.set(gData, forKey: Keys.groups)
        defaults.set(fData, forKey: Keys.favorites)
    }
}