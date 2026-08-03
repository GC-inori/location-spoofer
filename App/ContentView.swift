import SwiftUI

struct ContentView: View {
    @StateObject private var setup = SetupCoordinator()
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var showSetup = false
    @State private var showEnableTip = false
    @AppStorage("setupCompleted") private var setupCompleted = false

    var body: some View {
        NavigationView {
            MapHomeView(setup: setup)
        }
        .task {
            // 首次打开无标记：必须进引导页
            if !setupCompleted {
                showSetup = true
                return
            }
            await setup.refreshTrust()
        }
        .onChange(of: net.isAirplaneMode) { airplane in
            guard setupCompleted else { return }
            if airplane {
                showEnableTip = true
            } else {
                showEnableTip = false
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
        // 设置页「进入引导页」入口联动
        .onChange(of: setup.needsSetup) { needs in
            if needs { showSetup = true }
        }
        .sheet(isPresented: $showEnableTip) {
            NavigationView {
                VStack(spacing: 20) {
                    Image(systemName: "airplane")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("飞行模式已开启")
                        .font(.title3.weight(.semibold))
                    Text("Wi‑Fi 和蜂窝数据已关闭，虚拟定位无法生效。请关闭飞行模式后重试。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("知道了") {
                        showEnableTip = false
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(30)
                .navigationTitle("提示")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showEnableTip = false }
                    }
                }
            }
        }
    }
}
