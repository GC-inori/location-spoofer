import SwiftUI

enum SetupStep: Int, CaseIterable {
    case cert = 0, proxy = 1, verify = 2
    var title: String {
        switch self {
        case .cert: return "初始化 CA 证书"
        case .proxy: return "初始化代理"
        case .verify: return "环境检测"
        }
    }
}

struct FirstSetupView: View {
    @ObservedObject var setup: SetupCoordinator
    let onComplete: () -> Void

    @State private var step: SetupStep = .cert
    @State private var downloadedDone = false
    @State private var installedDone = false
    @State private var trustedDone = false
    @State private var proxyDone = false
    @State private var testPassed: VerificationResult? = nil
    @State private var testMessage = ""
    @State private var isLoading = false
    @State private var manualHint = ""

    private var certDone: Bool { downloadedDone && installedDone && trustedDone }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部大步骤进度
            HStack(spacing: 6) {
                ForEach(SetupStep.allCases, id: \.rawValue) { s in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(s.rawValue < step.rawValue ? Color.green
                                  : s.rawValue == step.rawValue ? Color.blue
                                  : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                        Text(s.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    if s.rawValue < SetupStep.allCases.count - 1 {
                        Rectangle().fill(s.rawValue < step.rawValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(height: 2).frame(maxWidth: 30)
                    }
                }
            }
            .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .cert: certStepView
                    case .proxy: proxyStepView
                    case .verify: verifyStepView
                    }
                }
                .padding(20)
            }

            // 底部导航
            Divider()
            HStack {
                if step.rawValue > 0 {
                    Button("上一步") { step = SetupStep(rawValue: step.rawValue - 1)! }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step == .verify && testPassed?.isSuccess == true {
                    Button("完成，进入主页") { onComplete() }.buttonStyle(.borderedProminent)
                } else if step == .cert && certDone {
                    Button("下一步") { step = .proxy }.buttonStyle(.borderedProminent)
                } else if step == .proxy && proxyDone {
                    Button("下一步") { step = .verify }.buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .alert("无法直接跳转", isPresented: Binding(
            get: { !manualHint.isEmpty },
            set: { if !$0 { manualHint = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: { Text(manualHint) }
    }

    // MARK: - 第 1 步：初始化 CA 证书（三个步骤平铺）

    private var certStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("第 1 步：下载证书", systemImage: "arrow.down.circle")) {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0).padding(.top, 2)
                    Text("虚拟定位需要通过自签 CA 证书来解密和改写定位请求。点击下方按钮，Safari 会打开下载页面。Safari 弹出「此网站正尝试下载一个配置描述文件」时，点「允许」。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            Task { await setup.proxy.openCertificateDownload() }
                        } label: {
                            Label("去下载", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(.blue)
                        Button {
                            downloadedDone = true
                        } label: {
                            Label(downloadedDone ? "已完成 ✓" : "已完成", systemImage: downloadedDone ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(downloadedDone ? .green : .secondary)
                    }
                }
            }

            GroupBox(label: Label("第 2 步：安装证书", systemImage: "square.and.arrow.down")) {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0).padding(.top, 2)
                    Text("下载完成后打开系统「设置」：\n\n1. 如果顶部显示了「已下载描述文件」，点进去安装\n2. 如果没显示：进入「通用 → VPN与设备管理」，找到 WLOC CA 证书点击安装\n\n安装时系统会要求输入锁屏密码，确认后点右上角「安装」即可。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button { openSettings(.general) } label: {
                            Label("去安装", systemImage: "gearshape").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(.blue)
                        Button { installedDone = true } label: {
                            Label(installedDone ? "已完成 ✓" : "已完成", systemImage: installedDone ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(installedDone ? .green : .secondary)
                    }
                }
            }

            GroupBox(label: Label("第 3 步：信任证书", systemImage: "shield.checkered")) {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0).padding(.top, 2)
                    Text("证书安装后还需要开启信任，否则系统会拦截代理的 HTTPS 请求：\n\n1. 打开「设置 → 通用 → 关于本机」\n2. 滑到底部找到「证书信任设置」\n3. 找到 WLOC CA，打开旁边的开关\n4. 弹出的警告中点「继续」\n\n⚠️ 每次重装 App 都需要重新下载安装证书。如果检测时报 TLS 错误，说明证书过期或不匹配，请删除旧证书（设置 → 通用 → VPN与设备管理）后重新安装。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button { openSettings(.general) } label: {
                            Label("去信任", systemImage: "shield.checkered").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(.blue)
                        Button { trustedDone = true } label: {
                            Label(trustedDone ? "已完成 ✓" : "已完成", systemImage: trustedDone ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(trustedDone ? .green : .secondary)
                    }
                }
            }
        }
    }

    // MARK: - 第 2 步：初始化代理

    private var proxyStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("配置 WiFi 系统代理", systemImage: "wifi")) {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0).padding(.top, 2)
                    Text("要让系统定位请求经过本地代理，需要在 WiFi 设置中手动配置：\n\n1. 打开「设置 → 无线局域网」\n2. 点击当前连接的 WiFi 右侧 (i) 图标\n3. 滑到底部找到「HTTP 代理」，选择「手动」\n4. 服务器填入 127.0.0.1，端口填入 8888\n5. 点右上角「存储」\n\n⚠️ 只有连接的这个 WiFi 会走代理，蜂窝数据不受影响。换 WiFi 后需要重新配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = "127.0.0.1:8888"
                } label: {
                    Label("复制地址", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).tint(.blue)
                Button {
                    openSettings(.wifi)
                } label: {
                    Label("去设置", systemImage: "wifi")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.blue)
            }

            Button {
                proxyDone = true
            } label: {
                Label(proxyDone ? "已完成 ✓" : "已完成", systemImage: proxyDone ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(proxyDone ? .green : .secondary)
        }
    }

    // MARK: - 第 3 步：环境检测

    private var verifyStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("检测整个流程", systemImage: "checklist")) {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 0).padding(.top, 2)
                    Text("点击「开始检测」后依次检查代理运行、证书信任与 WiFi 代理配置、坐标写入、数据改写。全部通过后「完成，进入主页」按钮才会亮起。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let result = testPassed, result.isSuccess {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                    Text("全部检测通过").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }.padding(12).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else if let result = testPassed {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("测试未通过").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                            Text(failureSummary(result)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let step = failureRemedyStep(result) {
                        Button {
                            withAnimation(.none) { self.step = step }
                            testPassed = nil
                            testMessage = ""
                        } label: {
                            Label("去处理", systemImage: "arrow.right.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if !testMessage.isEmpty {
                ScrollView {
                    Text(testMessage)
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }.frame(maxHeight: 280)
            }

            Button {
                isLoading = true; testMessage = ""
                Task {
                    testPassed = await setup.runVerificationTest()
                    testMessage = setup.testLog
                    isLoading = false
                }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white).controlSize(.small) }
                    Text(buttonText).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(buttonTint)
            .disabled(isLoading)

            Button {
                UIPasteboard.general.string = testMessage
            } label: {
                Label("复制检测日志", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).disabled(testMessage.isEmpty)
        }
    }

    private var buttonText: String {
        guard let result = testPassed else { return "开始检测" }
        return result.isSuccess ? "重新检测" : "⚠️ 重新测试"
    }

    private var buttonTint: Color {
        guard let result = testPassed else { return .blue }
        return result.isSuccess ? .blue : .red
    }

    private func failureSummary(_ result: VerificationResult) -> String {
        switch result {
        case .proxyNotRunning: return "代理未能启动，请检查代理状态"
        case .verificationInProgress: return "已有检测正在进行，请稍候"
        case .verificationSuperseded: return "检测期间位置已更新，本次结果已取消，请重新检测"
        case .certNotTrusted: return "CA 证书未安装或未信任，请重新安装证书并开启信任"
        case .wifiProxyNotConfigured: return "WiFi 代理未配置，请在系统设置中配置 127.0.0.1:8888"
        case .coordinateWriteFailed: return "坐标写入失败，请重试"
        case .patchFailed: return "坐标改写验证失败，可能是证书过期或不匹配"
        case .success: return ""
        }
    }

    private func failureRemedyStep(_ result: VerificationResult) -> SetupStep? {
        switch result {
        case .certNotTrusted: return .cert
        case .wifiProxyNotConfigured: return .proxy
        case .proxyNotRunning, .verificationInProgress, .verificationSuperseded,
             .coordinateWriteFailed, .patchFailed: return nil
        case .success: return nil
        }
    }


    @MainActor
    private func openSettings(_ destination: SystemSettingsDestination) {
        SystemSettingsNavigator.open(destination) { fallbackHint in
            if let fallbackHint { manualHint = fallbackHint }
        }
    }
}
