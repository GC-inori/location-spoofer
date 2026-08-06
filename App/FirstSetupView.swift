import SwiftUI

enum SetupStep: Int, CaseIterable {
    case proxy
    case cert

    var title: String {
        switch self {
        case .proxy: return "配置 Wi-Fi 代理"
        case .cert: return "初始化 CA 证书"
        }
    }
}

struct FirstSetupView: View {
    @ObservedObject var setup: SetupCoordinator
    let onComplete: () -> Void

    @State private var step: SetupStep
    @State private var downloadedDone = false
    @State private var installedDone = false
    @State private var trustedDone = false
    @State private var result: VerificationResult?
    @State private var isVerifying = false
    @State private var manualHint = ""
    @State private var showDiagnostics = false
    @StateObject private var diagnosticActions = LocationActionCoordinator()

    init(setup: SetupCoordinator, onComplete: @escaping () -> Void) {
        self.setup = setup
        self.onComplete = onComplete
        _step = State(initialValue: setup.setupStep)
    }

    private var certificateStepsComplete: Bool { downloadedDone && installedDone && trustedDone }
    private var diagnosticFavorite: FavoriteLocation {
        FavoriteLocation(name: "诊断位置", latitude: 22.544577, longitude: 113.94114, accuracy: 25)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case .proxy: proxyStep
                        case .cert: certificateStep
                        }
                        if let result { resultView(result) }
                    }
                    .padding(20)
                }
                Divider()
                primaryAction
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .navigationTitle("开始使用")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDiagnostics) {
                NavigationView {
                    RuntimeLogsView(
                        setup: setup,
                        actions: diagnosticActions,
                        testFavorite: diagnosticFavorite
                    )
                }
            }
            .alert("无法直接跳转", isPresented: Binding(
                get: { !manualHint.isEmpty },
                set: { if !$0 { manualHint = "" } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: { Text(manualHint) }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.rawValue) { value in
                HStack(spacing: 6) {
                    Circle()
                        .fill(value.rawValue <= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(value.title).font(.caption).foregroundStyle(.secondary)
                }
                if value != SetupStep.allCases.last {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 28, height: 2)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var proxyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("先配置 Wi-Fi 系统代理", systemImage: "wifi")) {
                Text("在当前 Wi-Fi 的详情页，将「HTTP 代理」设为「手动」：服务器填 127.0.0.1，端口填 8888。完成后点击下方「我已配置，开始检测」。检测会自动判断是 Wi-Fi 代理还是证书信任有问题。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            HStack(spacing: 12) {
                Button { UIPasteboard.general.string = "127.0.0.1:8888" } label: {
                    Label("复制地址", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { openSettings(.wifi) } label: {
                    Label("打开 Wi-Fi 设置", systemImage: "gearshape").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var certificateStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            certificateCard(
                title: "第 1 步：下载证书",
                icon: "arrow.down.circle",
                description: "下载本机随机生成的 CA 根证书。私钥仅保存在此设备的钥匙串中，不会随证书文件导出。Safari 出现配置描述文件下载提示时，选择「允许」。",
                actionTitle: "去下载",
                actionIcon: "arrow.down.circle.fill",
                complete: downloadedDone,
                action: { Task { await setup.proxy.openCertificateDownload() } },
                markComplete: { downloadedDone = true }
            )
            certificateCard(
                title: "第 2 步：安装证书",
                icon: "square.and.arrow.down",
                description: "下载完成后打开系统「设置」。如果顶部显示「已下载描述文件」，点进去安装；否则进入「通用 → VPN 与设备管理」，找到 WLOC CA 并完成安装。",
                actionTitle: "去安装",
                actionIcon: "gearshape",
                complete: installedDone,
                action: { openSettings(.general) },
                markComplete: { installedDone = true }
            )
            certificateCard(
                title: "第 3 步：信任证书",
                icon: "shield.checkered",
                description: "安装后进入「设置 → 通用 → 关于本机 → 证书信任设置」，找到 WLOC CA 并开启完全信任。iOS 保留钥匙串数据时，重装 App 会继续复用同一证书。",
                actionTitle: "去信任",
                actionIcon: "shield.checkered",
                complete: trustedDone,
                action: { openSettings(.general) },
                markComplete: { trustedDone = true }
            )
        }
    }

    private func certificateCard(
        title: String,
        icon: String,
        description: String,
        actionTitle: String,
        actionIcon: String,
        complete: Bool,
        action: @escaping () -> Void,
        markComplete: @escaping () -> Void
    ) -> some View {
        GroupBox(label: Label(title, systemImage: icon)) {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.frame(height: 0).padding(.top, 2)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    Button(action: markComplete) {
                        Label(
                            complete ? "已完成 ✓" : "已完成",
                            systemImage: complete ? "checkmark.circle.fill" : "circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(complete ? .green : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultView(_ result: VerificationResult) -> some View {
        let success = result.isSuccess
        VStack(alignment: .leading, spacing: 10) {
            Label(success ? "环境检测通过" : failureSummary(result), systemImage: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(success ? .green : .red)
                .font(.subheadline.weight(.semibold))
            if !success {
                Text(setup.testLog).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(8)
                Button {
                    showDiagnostics = true
                } label: {
                    Label("查看诊断日志", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background((success ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if step == .proxy {
            Button {
                verifyAfterProxyConfirmation()
            } label: {
                actionLabel("我已配置，开始检测")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isVerifying)
        } else {
            Button {
                verifyAfterCertificateConfirmation()
            } label: {
                actionLabel("确认完成，重新检测")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!certificateStepsComplete || isVerifying)
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            if isVerifying { ProgressView().tint(.white).controlSize(.small) }
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func verifyAfterProxyConfirmation() {
        runVerification { result in
            if result.isSuccess {
                onComplete()
            } else if result == .certNotTrusted {
                step = .cert
            } else {
                step = .proxy
            }
        }
    }

    private func verifyAfterCertificateConfirmation() {
        runVerification { result in
            if result.isSuccess {
                onComplete()
            } else if result != .certNotTrusted {
                step = .proxy
            }
        }
    }

    private func runVerification(completion: @escaping (VerificationResult) -> Void) {
        guard !isVerifying else { return }
        isVerifying = true
        result = nil
        Task {
            let verification = await setup.runVerificationTest()
            setup.applyVerificationResult(verification)
            guard !Task.isCancelled else { return }
            result = verification
            isVerifying = false
            completion(verification)
        }
    }

    private func failureSummary(_ result: VerificationResult) -> String {
        switch result {
        case .certNotTrusted: return "证书尚未安装或信任"
        case .wifiProxyNotConfigured: return "Wi-Fi 代理未正确设置"
        case .proxyNotRunning: return "本地代理未能启动"
        case .verificationInProgress: return "检测仍在进行"
        case .verificationSuperseded: return "检测结果已过期"
        case .coordinateWriteFailed: return "坐标写入失败"
        case .patchFailed: return "定位改写检测失败"
        case .success: return "环境检测通过"
        }
    }

    @MainActor
    private func openSettings(_ destination: SystemSettingsDestination) {
        SystemSettingsNavigator.open(destination) { fallbackHint in
            if let fallbackHint { manualHint = fallbackHint }
        }
    }
}
