import SwiftUI

struct ContentView: View {
    @StateObject private var setup = SetupCoordinator()
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var showSetup = false
    @AppStorage("setupCompleted") private var setupCompleted = false

    var body: some View {
        NavigationView {
            MapHomeView(setup: setup)
        }
        .task {
            if !setupCompleted {
                showSetup = true
                return
            }
            await setup.refreshTrust()
        }
        .onChange(of: net.isAirplaneMode) { airplane in
            guard setupCompleted else { return }
            if !airplane {
                Task { await setup.refreshTrust() }
            }
        }
        .fullScreenCover(isPresented: $showSetup) {
            FirstSetupView(setup: setup, onComplete: {
                setupCompleted = true
                setup.completeSetup()
                showSetup = false
            })
        }
    }
}
