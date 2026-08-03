import Foundation

struct FavoriteLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var accuracy: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, accuracy: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.createdAt = createdAt
    }
}

struct MapConfiguration: Equatable {
    let showsUserLocation: Bool
    let allowsCurrentLocationRequest: Bool

    static let `default` = MapConfiguration(showsUserLocation: false, allowsCurrentLocationRequest: false)
}

final class FavoriteLocationStore: ObservableObject {
    private enum Keys {
        static let favorites = "favorite_locations"
        static let selectedID = "favorite_locations_selected_id"
    }

    @Published private(set) var favorites: [FavoriteLocation]
    @Published private(set) var selectedFavoriteID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.favorites),
           let decoded = try? JSONDecoder().decode([FavoriteLocation].self, from: data) {
            self.favorites = decoded
        } else {
            self.favorites = []
        }
        self.selectedFavoriteID = defaults.string(forKey: Keys.selectedID).flatMap(UUID.init(uuidString:))
    }

    var selectedFavorite: FavoriteLocation? {
        guard let selectedFavoriteID else { return nil }
        return favorites.first(where: { $0.id == selectedFavoriteID })
    }

    @discardableResult
    func save(name: String, latitude: Double, longitude: Double, accuracy: Int) -> FavoriteLocation {
        let favorite = FavoriteLocation(name: name, latitude: latitude, longitude: longitude, accuracy: accuracy)
        // 去重：相同坐标删除旧数据，新数据插入顶部
        favorites.removeAll {
            abs($0.latitude - favorite.latitude) < 0.000001 && abs($0.longitude - favorite.longitude) < 0.000001
        }
        favorites.insert(favorite, at: 0)
        select(favorite.id)
        persist()
        return favorite
    }

    func select(_ id: UUID?) {
        selectedFavoriteID = id
        defaults.set(id?.uuidString, forKey: Keys.selectedID)
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[idx].name = name
        persist()
    }

    func delete(_ favorite: FavoriteLocation) {
        favorites.removeAll { $0.id == favorite.id }
        if selectedFavoriteID == favorite.id {
            select(favorites.first?.id)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: Keys.favorites)
    }
}
