import Network
import Foundation

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isSatisfied = true
    @Published private(set) var isWiFiEnabled = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.isSatisfied = satisfied
                self?.isWiFiEnabled = wifi
            }
        }
        monitor.start(queue: .main)
    }

    var isAirplaneMode: Bool { !isSatisfied }
}
