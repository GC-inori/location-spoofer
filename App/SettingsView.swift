import SwiftUI

struct SettingsView: View {
    @ObservedObject var setup: SetupCoordinator
    @ObservedObject var actions: LocationActionCoordinator
    @ObservedObject private var proxy = ProxyManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var activeTip: TipKind?

    var body: some View {
        Form {
            Section("状态") {
                HStack {
                    Label("代理", systemImage: proxy.isRunning ? "play.circle.fill" : "stop.circle")
                    Spacer()
                    Toggle("", isOn: proxyBinding).labelsHidden()
                        .tint(.blue)
                }
                HStack {
                    Label("虚拟定位", systemImage: actions.virtualLocationEnabled ? "location.fill" : "location.slash")
                    Spacer()
                    Text(actions.virtualLocationEnabled ? "已开启" : "已关闭").foregroundStyle(.secondary)
                }
            }

            Section("说明") {
                Button {
                    activeTip = .activation
                } label: {
                    Label("生效说明", systemImage: "checklist")
                }
                Button {
                    activeTip = .deactivation
                } label: {
                    Label("失效说明", systemImage: "arrow.uturn.backward.circle")
                }
                Button {
                    activeTip = .removeProxy
                } label: {
                    Label("关闭 WiFi 代理", systemImage: "wifi.slash")
                }
            }

            Section("工作原理") {
                Text("""
                App 在设备本地运行一个代理服务器（127.0.0.1:8888）。

                通过 WiFi 手动代理配置，让系统的定位请求（gs-loc.apple.com/clls/wloc）经过这个本地代理。代理使用已安装的 CA 证书对 HTTPS 流量做中间人解密，把 Apple 返回的定位坐标改写为你设置的虚拟坐标，再加密返回给系统，从而实现虚拟定位。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("应用") {
                Button {
                    setup.needsSetup = true
                } label: {
                    Label("进入引导页", systemImage: "arrow.clockwise.circle")
                }
                valueRow("版本", value: versionText)
            }

            Section("支持") {
                NavigationLink {
                    BugReportView(setup: setup)
                } label: {
                    Label("报告 Issue", systemImage: "ladybug")
                }
            }

            Section("关于") {
                Button {
                    if let url = URL(string: "https://github.com/xweiba/location-spoofer") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("xweiba/location-spoofer", systemImage: "link")
                }
                Text("如果觉得好用，欢迎去 GitHub 给项目点个 Star")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("致谢") {
                Button {
                    if let url = URL(string: "https://github.com/Yu9191/wloc") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("核心定位改写逻辑移植自 Yu9191/wloc", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
        }
        .sheet(item: $activeTip) { kind in
            TipSheetView(kind: kind)
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).font(.footnote.monospaced()).foregroundStyle(.secondary) }
    }

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var proxyBinding: Binding<Bool> {
        Binding(get: { proxy.isRunning }, set: { on in
            Task {
                if on {
                    do { try await proxy.start() } catch { proxy.error = error.localizedDescription }
                } else {
                    proxy.stop()
                }
            }
        })
    }
}
