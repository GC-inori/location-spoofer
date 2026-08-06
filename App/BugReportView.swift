import SwiftUI

struct BugReportView: View {
    @ObservedObject var setup: SetupCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isReproducible = true
    @State private var isRunning = false
    @State private var showCopiedAlert = false
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var thirdPartyProxy = ThirdPartyProxyManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 说明
                    Text("遇到问题时，在这里生成 Issue 报告。系统会运行一次诊断测试，将测试结果和你的描述一起复制到剪切板，然后跳转到 GitHub 提交。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    // 可复现环境
                    Toggle(isOn: $isReproducible) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("可复现环境").font(.subheadline.weight(.medium))
                            Text("当前设备上问题稳定复现，非偶发性。").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // 问题描述
                    VStack(alignment: .leading, spacing: 6) {
                        Text("问题描述").font(.subheadline.weight(.medium))
                        TextEditor(text: $description)
                            .font(.caption)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }

            Divider()
            // 底部按钮
            VStack(spacing: 8) {
                Button {
                    generateReport()
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView().tint(.white)
                        }
                        Text(isRunning ? "正在生成报告…" : "生成 Issue 报告")
                            .font(.body.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isRunning || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .navigationTitle("报告 Issue")
        .navigationBarTitleDisplayMode(.inline)
        .alert("已生成", isPresented: $showCopiedAlert) {
            Button("跳转到 GitHub") {
                dismiss()
                if let url = URL(string: "https://github.com/xweiba/location-spoofer/issues/new") {
                    UIApplication.shared.open(url)
                }
            }
            Button("稍后再说", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Issue 报告已复制到剪切板。请在 GitHub Issues 页面粘贴并提交。")
        }
    }

    private func generateReport() {
        isRunning = true
        Task {
            let testLog: String
            if runtimeMode.mode == .thirdParty {
                do {
                    let response = try await thirdPartyProxy.query()
                    let active = response.success && response.latitude != nil && response.longitude != nil
                    testLog = "第三方代理测试模式：模块连接成功；已保存坐标=\(active ? "是" : "否")"
                } catch {
                    testLog = "第三方代理测试模式：模块连接失败；\(error.localizedDescription)"
                }
            } else {
                _ = await setup.runVerificationTest()
                testLog = setup.testLog
            }

            // 获取版本信息
            let appVersion: String = {
                let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                return "\(v) (\(b))"
            }()
            let systemVersion = UIDevice.current.systemVersion

            // 拼接报告
            let report = """
            ### 环境信息
            App 版本: \(appVersion)
            系统版本: iOS \(systemVersion)
            运行模式: \(runtimeMode.mode.displayName)
            可复现环境: \(isReproducible ? "是" : "否")

            ### 问题描述
            \(description.trimmingCharacters(in: .whitespacesAndNewlines))

            ### 诊断日志
            ```
            \(testLog.isEmpty ? "（无诊断数据）" : testLog)
            ```
            """

            // 复制到剪切板
            UIPasteboard.general.string = report
            isRunning = false

            // 弹窗
            showCopiedAlert = true
        }
    }
}
