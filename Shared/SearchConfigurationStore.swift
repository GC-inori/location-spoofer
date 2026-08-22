import Foundation

final class SearchConfigurationStore: ObservableObject {
    static let shared = SearchConfigurationStore()

    private enum Keys {
        static let visibleCountX = "search_visible_count_x"
        static let maxCountY = "search_max_count_y"
        static let recentVisibleZ = "recent_favorites_visible_z"
        static let recentMaxW = "recent_favorites_max_w"
    }

    @Published var visibleCountX: Int {
        didSet { defaults.set(visibleCountX, forKey: Keys.visibleCountX) }
    }

    @Published var maxCountY: Int {
        didSet { defaults.set(maxCountY, forKey: Keys.maxCountY) }
    }

    @Published var recentVisibleZ: Int {
        didSet { defaults.set(recentVisibleZ, forKey: Keys.recentVisibleZ) }
    }

    @Published var recentMaxW: Int {
        didSet { defaults.set(recentMaxW, forKey: Keys.recentMaxW) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let x = defaults.integer(forKey: Keys.visibleCountX)
        self.visibleCountX = (x >= 2 && x <= 15) ? x : 5

        let y = defaults.integer(forKey: Keys.maxCountY)
        self.maxCountY = (y >= 5 && y <= 50) ? y : 10

        let z = defaults.integer(forKey: Keys.recentVisibleZ)
        self.recentVisibleZ = (z >= 2 && z <= 10) ? z : 4

        let w = defaults.integer(forKey: Keys.recentMaxW)
        self.recentMaxW = (w >= 3 && w <= 30) ? w : 10
    }
}