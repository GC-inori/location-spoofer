import Foundation

enum AppGroup {
    static let identifier = "group.com.paopaolabs.location-spoofer"
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isSharedContainerAvailable: Bool { sharedContainerURL != nil }

    static var containerURL: URL {
        if let url = sharedContainerURL { return url }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocationSpoofer", isDirectory: true)
    }
}

enum WlocKeys {
    static let coords = "wloc_settings"
}

struct WlocSettings: Codable {
    var longitude: Double
    var latitude: Double
    var accuracy: Int
    var enabled: Bool
}

enum WlocSettingsStore {
    static func load() -> WlocSettings? {
        guard let data = AppGroup.defaults.data(forKey: WlocKeys.coords) else { return nil }
        return try? JSONDecoder().decode(WlocSettings.self, from: data)
    }

    static func save(_ settings: WlocSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroup.defaults.set(data, forKey: WlocKeys.coords)
    }

    static func clear() {
        save(WlocSettings(longitude: 0, latitude: 0, accuracy: 25, enabled: false))
    }
}
