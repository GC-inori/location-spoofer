import AVFoundation
import UIKit

final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isActive = false

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard isActive, let info = notification.userInfo,
              let type = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.ended.rawValue else { return }
        restartAfterInterruption()
        RuntimeLogger.info("APP", "KeepAlive", "音频中断恢复")
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            RuntimeLogger.error("APP", "KeepAlive", "音频会话失败", error: error)
        }

        let eng = AVAudioEngine()
        let player = AVAudioPlayerNode()
        eng.attach(player)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44100 * 3)!
        buf.frameLength = 44100 * 3
        eng.connect(player, to: eng.mainMixerNode, format: fmt)
        eng.prepare()
        do { try eng.start() } catch {
            RuntimeLogger.error("APP", "KeepAlive", "引擎启动失败", error: error)
            isActive = false; return
        }
        player.scheduleBuffer(buf, at: nil, options: .loops)
        player.play()
        engine = eng; playerNode = player
        UIApplication.shared.isIdleTimerDisabled = true
        RuntimeLogger.info("APP", "KeepAlive", "后台保活已启动（静音音频）")
    }

    private func restartAfterInterruption() {
        guard isActive else { return }
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        isActive = false
        start()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        playerNode?.stop(); engine?.stop()
        playerNode = nil; engine = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        RuntimeLogger.info("APP", "KeepAlive", "后台保活已停止")
    }
}
