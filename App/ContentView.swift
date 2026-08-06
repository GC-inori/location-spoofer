import SwiftUI

struct ContentView: View {
    @StateObject private var setup = SetupCoordinator()
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var showSetup = false
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
                    Text("正在启动…").font(.subheadline).foregroundStyle(.secondary)
                }
            case .map:
                NavigationView {
                    MapHomeView(setup: setup)
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
        .task {
            if !setup.proxy.isRunning {
                do {
                    try await setup.proxy.start()
                } catch {
                    RuntimeLogger.error("APP", "Startup", "代理启动失败，将在设置检测中重试", error: error)
                }
            }
            phase = .map
            if !setupCompleted { showSetup = true }
            // Tile probing is a best-effort display refinement and must never block first render.
            await CoordinateConverter.detectTileByFixedGeocode(force: true)
        }
    }
}
