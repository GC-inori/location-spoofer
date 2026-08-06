import SwiftUI

enum SetupStep: Int, CaseIterable {
    case mode
    case proxy
    case cert
    case thirdPartyClient
    case thirdPartyImport
    case thirdPartyTest

    var title: String {
        switch self {
        case .mode: return "选择模式"
        case .proxy: return "配置 Wi-Fi 代理"
        case .cert: return "初始化 CA 证书"
        case .thirdPartyClient: return "选择客户端"
        case .thirdPartyImport: return "导入配置"
        case .thirdPartyTest: return "连接检测"
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
    @State private var isPreparingMode = false
    @State private var manualHint = ""
    @State private var setupActionError = ""
    @State private var showDiagnostics = false
    @StateObject private var diagnosticActions = LocationActionCoordinator()
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var thirdPartyProxy = ThirdPartyProxyManager.shared
    @ObservedObject private var thirdPartyClient = ThirdPartyProxyClientStore.shared
    @State private var copiedSubscriptionURL = false
    @State private var copiedMITMHostname = false

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
                        case .mode: modeStep
                        case .proxy: proxyStep
                        case .cert: certificateStep
                        case .thirdPartyClient: thirdPartyClientStep
                        case .thirdPartyImport: thirdPartyImportStep
                        case .thirdPartyTest: thirdPartyTestStep
                        }
                        if let result { resultView(result) }
                    }
                    .padding(20)
                }
                Divider()
                VStack(spacing: 10) {
                    primaryAction
                    if step != .mode {
                        Button("上一步") { returnToPreviousStep() }
                            .disabled(isVerifying || thirdPartyProxy.isRequesting)
                    }
                }
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
            .alert("操作失败", isPresented: Binding(
                get: { !setupActionError.isEmpty },
                set: { if !$0 { setupActionError = "" } }
            )) {
                Button("查看诊断日志") { showDiagnostics = true }
                Button("知道了", role: .cancel) {}
            } message: {
                Text(setupActionError)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(visibleSteps, id: \.rawValue) { value in
                HStack(spacing: 6) {
                    Circle()
                        .fill(value.rawValue <= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(value.title).font(.caption).foregroundStyle(.secondary)
                }
                if value != visibleSteps.last {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 28, height: 2)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private var visibleSteps: [SetupStep] {
        switch step {
        case .mode:
            return [.mode]
        case .proxy, .cert:
            return [.mode, .proxy, .cert]
        case .thirdPartyClient, .thirdPartyImport, .thirdPartyTest:
            return [.mode, .thirdPartyClient, .thirdPartyImport, .thirdPartyTest]
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择运行模式")
                .font(.title2.bold())
            Text("后续可在“设置 → 运行模式”中切换。两种模式不要同时拦截 WLOC 请求。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            modeCard(
                title: "APP模式",
                icon: "iphone.and.arrow.forward",
                badges: ["仅 Wi-Fi", "无外部依赖"],
                description: "App 在设备本地启动代理，通过当前 Wi-Fi 的手动 HTTP 代理改写定位响应。免费自签应用无法使用系统 VPN 的 Network Extension 能力，因此 APP模式不支持蜂窝网络，需要配置 Wi-Fi 代理并安装 App 生成的 CA。",
                tint: .blue
            ) {
                selectMode(.localWiFi)
            }
            .disabled(isPreparingMode)

            modeCard(
                title: "第三方代理模式",
                icon: "network.badge.shield.half.filled",
                badges: ["Wi-Fi + 4G/5G", "测试模式"],
                description: "App 负责选点，并通过 WLOC 配置接口查询和同步坐标；第三方代理客户端负责网络代理、模块拦截、MITM 和持久化。证书、VPN 与代理连接均由第三方客户端处理。",
                tint: .orange
            ) {
                selectMode(.thirdParty)
            }
            .disabled(isPreparingMode)

            if isPreparingMode {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在准备 APP模式本地服务…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func modeCard(
        title: String,
        icon: String,
        badges: [String],
        description: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.25)))
        }
        .buttonStyle(.plain)
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
                action: {
                    Task {
                        let opened = await setup.proxy.openCertificateDownload()
                        if !opened {
                            setupActionError = setup.proxy.error ?? "无法打开证书下载页面，请查看诊断日志"
                        }
                    }
                },
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

    private var thirdPartyClientStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("选择第三方代理客户端", systemImage: "app.badge.checkmark")) {
                VStack(spacing: 0) {
                    ForEach(ThirdPartyProxyClient.allCases) { client in
                        Button {
                            thirdPartyClient.select(client)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(client.name).foregroundStyle(.primary)
                                    Text(client.verificationText)
                                        .font(.caption2)
                                        .foregroundStyle(client == .shadowrocket ? .green : .orange)
                                }
                                Spacer()
                                Image(systemName: thirdPartyClient.selectedClient == client ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(thirdPartyClient.selectedClient == client ? .blue : .secondary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if client != ThirdPartyProxyClient.allCases.last { Divider() }
                    }
                }
            }

            Text("Egern 直接使用 Surge 模块。Stash 直接订阅 .stoverride，不需要 Script Hub 转换。除 Shadowrocket 外，当前仅提供配置，尚未完成真机验证。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var thirdPartyImportStep: some View {
        let client = thirdPartyClient.selectedClient
        return VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("第 1 步：导入 \(client.name) 模块", systemImage: "square.and.arrow.down")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(importInstructions(for: client))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        UIPasteboard.general.string = client.subscriptionURL.absoluteString
                        copiedSubscriptionURL = true
                    } label: {
                        Label(copiedSubscriptionURL ? "已复制订阅地址" : "复制订阅地址", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        openThirdPartyClient(client)
                    } label: {
                        Label("打开 \(client.name)", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if client == .shadowrocket {
                shadowrocketHTTPSDecryptionGuide
            } else {
                Text("请复制订阅地址，在客户端的模块、重写或覆写订阅入口中添加。证书、MITM、VPN 和代理连接请按第三方客户端自己的流程配置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shadowrocketHTTPSDecryptionGuide: some View {
        GroupBox(label: Label("第 2 步：配置 HTTPS 解密", systemImage: "lock.open")) {
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(1, "进入“配置 → 本地文件”，找到带黄点的配置，点击右侧 i 图标。")
                instructionRow(2, "进入“HTTPS 解密”，开启解密开关。")
                instructionRow(3, "在域名列表中添加 gs-loc.apple.com。")

                Button {
                    UIPasteboard.general.string = ThirdPartyProxyManager.interceptionHostname
                    copiedMITMHostname = true
                } label: {
                    Label(copiedMITMHostname ? "已复制 gs-loc.apple.com" : "复制解密域名", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                instructionRow(4, "按 Shadowrocket 提示生成并完成证书授权。")
                instructionRow(5, "返回 HTTPS 解密页面，点击右上角勾号保存，然后开启代理。")

                Button {
                    openThirdPartyClient(.shadowrocket)
                } label: {
                    Label("打开 Shadowrocket 继续配置", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("App 只能唤起 Shadowrocket，无法通过公开接口直接跳转到“模块”或“HTTPS 解密”页面。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importInstructions(for client: ThirdPartyProxyClient) -> String {
        if client == .shadowrocket {
            return "先复制订阅地址。然后打开 Shadowrocket，进入“配置 → 模块”，点击右上角“+”，粘贴订阅地址并完成导入。导入完成后，模块配置由 Shadowrocket 保存，不依赖本 App 持续运行。"
        }
        return "先复制订阅地址，然后打开 \(client.name)，在模块、重写或覆写订阅入口中粘贴并导入。配置由 \(client.name) 保存，不依赖本 App 持续运行。"
    }

    private func openThirdPartyClient(_ client: ThirdPartyProxyClient) {
        guard let url = client.launchURL else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                manualHint = "无法打开 \(client.name)，请确认客户端已安装后手动打开。"
            }
        }
    }

    private var thirdPartyTestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("检测配置接口", systemImage: "network")) {
                Text("请先在第三方客户端中启用刚导入的配置，并按客户端要求完成 MITM、证书和代理/VPN 连接。App 只调用 WLOC 查询接口确认模块能否正常响应，不检查或管理第三方证书。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func returnToPreviousStep() {
        result = nil
        setupActionError = ""
        switch step {
        case .mode:
            break
        case .proxy, .thirdPartyClient:
            step = .mode
        case .cert:
            step = .proxy
        case .thirdPartyImport:
            step = .thirdPartyClient
        case .thirdPartyTest:
            step = .thirdPartyImport
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
        if step == .mode {
            EmptyView()
        } else if step == .proxy {
            Button {
                verifyAfterProxyConfirmation()
            } label: {
                actionLabel("我已配置，开始检测")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isVerifying)
        } else if step == .cert {
            Button {
                verifyAfterCertificateConfirmation()
            } label: {
                actionLabel("确认完成，重新检测")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!certificateStepsComplete || isVerifying)
        } else if step == .thirdPartyClient {
            Button("下一步：导入配置") { step = .thirdPartyImport }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
        } else if step == .thirdPartyImport {
            Button("我已导入，下一步") { step = .thirdPartyTest }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
        } else {
            Button {
                verifyThirdPartyConnection()
            } label: {
                actionLabel("检测接口连接")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isVerifying || thirdPartyProxy.isRequesting)
        }
    }

    private func selectMode(_ mode: ProxyRuntimeMode) {
        guard !isPreparingMode else { return }
        runtimeMode.setMode(mode)
        result = nil
        switch mode {
        case .localWiFi:
            isPreparingMode = true
            Task { @MainActor in
                await setup.prepareLocalServices()
                isPreparingMode = false
                step = .proxy
            }
        case .thirdParty:
            setup.proxy.stop()
            BackgroundKeepAlive.shared.stop()
            step = .thirdPartyClient
        }
    }

    private func verifyThirdPartyConnection() {
        guard !isVerifying else { return }
        isVerifying = true
        result = nil
        Task { @MainActor in
            defer { isVerifying = false }
            do {
                _ = try await thirdPartyProxy.query()
                onComplete()
            } catch {
                setupActionError = error.localizedDescription
            }
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
