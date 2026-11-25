import AVFoundation
import CarPlay
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

// MARK: - App 入口

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AudioHub.shared.configureSession()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            return UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

// MARK: - 手机主屏

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: MenuViewController())
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class MenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CarPlayCast"
        view.backgroundColor = .systemBackground

        let carplay = makeButton("车载播放（车机端）") { [weak self] in
            self?.showAlert("插上 CarPlay 后，车机主屏会出现「车载播放」列表。")
        }
        let video = makeButton("视频同步（画面在手机）") { [weak self] in
            self?.navigationController?.pushViewController(VideoSyncViewController(), animated: true)
        }
        let compensate = makeButton("补偿版导出（给 CarMovie 用）") { [weak self] in
            self?.navigationController?.pushViewController(CompensateViewController(), animated: true)
        }

        let stack = UIStackView(arrangedSubviews: [carplay, video, compensate])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func makeButton(_ title: String, _ action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        let b = UIButton(configuration: config)
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private func showAlert(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - 车机端

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        render()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    private func render() {
        let playing = AudioHub.shared.isPlaying

        let play = CPListItem(text: "播放", detailText: playing ? "播放中" : "440Hz 测试音，循环")
        play.handler = { [weak self] _, completion in
            AudioHub.shared.play()
            self?.render()
            completion()
        }

        let stop = CPListItem(text: "停止", detailText: playing ? "点击停止" : nil)
        stop.handler = { [weak self] _, completion in
            AudioHub.shared.stop()
            self?.render()
            completion()
        }

        let template = CPListTemplate(title: "车载播放",
                                      sections: [CPListSection(items: [play, stop])])
        interfaceController?.setRootTemplate(template, animated: false)
    }
}

// MARK: - 音频

/// 运行时合成一段 440Hz 测试音，省掉二进制资源，工程全是文本文件
enum ToneFile {

    static func url() -> URL? {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("tone.wav")
        if FileManager.default.fileExists(atPath: dst.path) { return dst }

        let sampleRate = 44100
        let count = sampleRate * 2          // 2 秒
        let dataLen = count * 2             // 16-bit mono
        var data = Data()

        func put<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        func putAscii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }

        putAscii("RIFF"); put(UInt32(36 + dataLen)); putAscii("WAVE")
        putAscii("fmt "); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2))
        put(UInt16(2)); put(UInt16(16))
        putAscii("data"); put(UInt32(dataLen))

        let fade = sampleRate / 50
        for i in 0..<count {
            var amp = 0.35
            if i < fade { amp *= Double(i) / Double(fade) }
            if i > count - fade { amp *= Double(count - i) / Double(fade) }
            let value = sin(2 * .pi * 440 * Double(i) / Double(sampleRate)) * amp
            put(Int16(max(-32767, min(32767, value * 32767))))
        }

        do {
            try data.write(to: dst)
            return dst
        } catch {
            NSLog("CarPlayCast: tone write failed \(error)")
            return nil
        }
    }
}

final class AudioHub {

    static let shared = AudioHub()
    private var player: AVAudioPlayer?
    private var sessionConfigured = false

    private init() {}

    var isPlaying: Bool { player?.isPlaying ?? false }

    func configureSession() {
        guard !sessionConfigured else { return }
        sessionConfigured = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            NSLog("CarPlayCast session error: \(error)")
        }
        installRemoteCommands()
        refreshNowPlaying()
    }

    func toggle() { isPlaying ? stop() : play() }

    func play() {
        if player == nil { player = makePlayer() }
        player?.numberOfLoops = -1
        player?.play()
        refreshNowPlaying()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        refreshNowPlaying()
    }

    private func makePlayer() -> AVAudioPlayer? {
        guard let url = ToneFile.url() else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in AudioHub.shared.play(); return .success }
        center.pauseCommand.addTarget { _ in AudioHub.shared.stop(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in AudioHub.shared.toggle(); return .success }
    }

    private func refreshNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "CarPlayCast",
            MPMediaItemPropertyArtist: isPlaying ? "播放中" : "已停止",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}

// MARK: - 视频同步（画面在手机，声音走车机）

final class VideoSyncViewController: UIViewController {

    private let playerLayer = AVPlayerLayer()
    private let panel = UIStackView()

    private let infoLabel = UILabel()
    private let offsetLabel = UILabel()
    private let statusLabel = UILabel()
    private let slider = UISlider()

    private var videoPlayer: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var pending: DispatchWorkItem?
    private var watchdog: Timer?

    private var offsetMs: Double {
        get { UserDefaults.standard.double(forKey: "syncOffsetMs") }
        set { UserDefaults.standard.set(newValue, forKey: "syncOffsetMs") }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        buildPanel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAll()
    }

    private func buildPanel() {
        infoLabel.text = "① 选视频  ② 播放  ③ 用滑杆把声音对齐画面"
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .white
        infoLabel.numberOfLines = 0

        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        offsetLabel.textColor = .systemYellow

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .systemGray
        statusLabel.numberOfLines = 0

        slider.minimumValue = 0
        slider.maximumValue = 600
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [
            makeButton("选视频", #selector(pickVideo)),
            makeButton("播放", #selector(playTapped)),
            makeButton("暂停", #selector(pauseTapped))
        ])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8

        let fine = UIStackView(arrangedSubviews: [
            makeButton("−10ms", #selector(minusTapped)),
            makeButton("+10ms", #selector(plusTapped))
        ])
        fine.axis = .horizontal
        fine.distribution = .fillEqually
        fine.spacing = 8

        panel.axis = .vertical
        panel.spacing = 10
        panel.translatesAutoresizingMaskIntoConstraints = false
        [infoLabel, offsetLabel, slider, fine, row, statusLabel].forEach { panel.addArrangedSubview($0) }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(panel)
        view.addSubview(blur)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            panel.topAnchor.constraint(equalTo: blur.topAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])

        refreshLabel()
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return b
    }

    private func refreshLabel() {
        offsetLabel.text = String(format: "补偿 %.0f ms", offsetMs)
    }

    @objc private func sliderChanged() {
        offsetMs = Double(slider.value).rounded()
        refreshLabel()
    }

    @objc private func minusTapped() { nudge(-10) }
    @objc private func plusTapped() { nudge(10) }

    private func nudge(_ delta: Double) {
        offsetMs = min(600, max(0, offsetMs + delta))
        slider.value = Float(offsetMs)
        refreshLabel()
    }

    @objc private func pickVideo() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func load(original url: URL) {
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("source.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)")
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: url, to: dst)

        let asset = AVURLAsset(url: dst)
        let player = AVPlayer(url: dst)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        videoPlayer = player
        playerLayer.player = player

        statusLabel.text = "正在分离音轨…"
        extractAudio(from: asset, presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A])
        slider.value = Float(offsetMs)
        refreshLabel()
    }

    private func extractAudio(from asset: AVAsset, presets: [String]) {
        guard asset.tracks(withMediaType: .audio).first != nil else {
            statusLabel.text = "这个文件没有音轨"
            return
        }
        guard let preset = presets.first else {
            statusLabel.text = "音轨分离失败：这个格式不支持"
            videoPlayer?.isMuted = false
            return
        }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("audio.m4a")
        try? FileManager.default.removeItem(at: out)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { return }
        exporter.outputURL = out
        exporter.outputFileType = .m4a

        exporter.exportAsynchronously { [weak self] in
            guard exporter.status == .completed else {
                DispatchQueue.main.async {
                    self?.extractAudio(from: asset, presets: Array(presets.dropFirst()))
                }
                return
            }
            DispatchQueue.main.async {
                guard let p = try? AVAudioPlayer(contentsOf: out) else { return }
                p.prepareToPlay()
                self?.audioPlayer = p
                self?.statusLabel.text = "音轨已分离，可以调同步了"
            }
        }
    }

    @objc private func playTapped() {
        guard let videoPlayer, let audioPlayer else {
            statusLabel.text = "还没选视频，或者音轨分离没完成"
            return
        }
        pending?.cancel()

        audioPlayer.currentTime = 0
        videoPlayer.seek(to: .zero)
        audioPlayer.play()

        let delay = max(0, offsetMs) / 1000.0
        let work = DispatchWorkItem { [weak self] in
            self?.videoPlayer?.play()
            self?.startWatchdog()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @objc private func pauseTapped() { stopAll() }

    private func stopAll() {
        pending?.cancel()
        watchdog?.invalidate()
        watchdog = nil
        audioPlayer?.pause()
        videoPlayer?.pause()
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDrift()
        }
    }

    private func checkDrift() {
        guard let audio = audioPlayer, let video = videoPlayer, audio.isPlaying else { return }
        let audioTimeline = audio.currentTime - offsetMs / 1000
        let videoTime = video.currentTime().seconds
        guard videoTime.isFinite else { return }
        if abs(audioTimeline - videoTime) > 0.12 {
            let target = CMTime(seconds: max(0, audioTimeline), preferredTimescale: 600)
            video.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
}

extension VideoSyncViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        load(original: url)
    }
}

// MARK: - 补偿版导出（给 CarMovie 这类车机播放器用）

enum CompensateError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "这个文件没有视频轨"
        case .exportFailed(let m): return "导出失败：\(m)"
        }
    }
}

enum CompensateExporter {

    /// offsetMs > 0：音频后移（声音偏早）；offsetMs < 0：画面后移（声音偏晚）
    static func export(source: URL, offsetMs: Double, completion: @escaping (Result<URL, Error>) -> Void) {
        let asset = AVURLAsset(url: source)

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(CompensateError.noVideoTrack))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        let duration = asset.duration
        let shift = CMTime(seconds: abs(offsetMs) / 1000.0, preferredTimescale: 600)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(CompensateError.noVideoTrack))
            return
        }
        let compAudio = audioTrack == nil
            ? nil
            : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let videoStart = offsetMs < 0 ? shift : .zero
        let audioStart = offsetMs > 0 ? shift : .zero

        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                          of: videoTrack, at: videoStart)
            if let audioTrack, let compAudio {
                try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                              of: audioTrack, at: audioStart)
            }
        } catch {
            completion(.failure(CompensateError.exportFailed(error.localizedDescription)))
            return
        }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let out = dir.appendingPathComponent("synced_\(Int(offsetMs))ms.mp4")
        try? FileManager.default.removeItem(at: out)

        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(CompensateError.exportFailed("无法创建导出会话")))
            return
        }
        exporter.outputURL = out
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    completion(.success(out))
                default:
                    completion(.failure(CompensateError.exportFailed(
                        exporter.error?.localizedDescription ?? "未知错误")))
                }
            }
        }
    }
}

final class CompensateViewController: UIViewController {

    private let stack = UIStackView()
    private let valueLabel = UILabel()
    private let statusLabel = UILabel()
    private let slider = UISlider()

    private var source: URL?
    private var offsetMs: Double = 120

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "补偿版导出"
        view.backgroundColor = .systemBackground
        buildUI()
    }

    private func buildUI() {
        let help = UILabel()
        help.numberOfLines = 0
        help.font = .systemFont(ofSize: 13)
        help.textColor = .secondaryLabel
        help.text = """
        先判断方向：
        · 看到手拍下去，才听到啪 → 声音偏晚，用负值
        · 先听到啪，才看到手拍下去 → 声音偏早，用正值

        导出后文件在「文件」App → 我的 iPhone → CarPlayCast。
        """

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textAlignment = .center

        slider.minimumValue = -400
        slider.maximumValue = 400
        slider.value = Float(offsetMs)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        [help, valueLabel, slider,
         makeButton("选择视频", #selector(pickVideo)),
         makeButton("导出补偿版", #selector(runExport)),
         statusLabel].forEach { stack.addArrangedSubview($0) }
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])

        refresh()
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        let b = UIButton(configuration: config)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func refresh() {
        let direction = offsetMs > 0 ? "音频后移" : (offsetMs < 0 ? "画面后移" : "不偏移")
        valueLabel.text = String(format: "%+.0f ms · %@", offsetMs, direction)
    }

    @objc private func sliderChanged() {
        offsetMs = Double(slider.value).rounded()
        refresh()
    }

    @objc private func pickVideo() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func runExport() {
        guard let source else {
            statusLabel.text = "先选一个视频"
            return
        }
        guard abs(offsetMs) >= 1 else {
            statusLabel.text = "偏移是 0，不用导出"
            return
        }

        statusLabel.text = "导出中…长视频要等一会儿"
        CompensateExporter.export(source: source, offsetMs: offsetMs) { [weak self] result in
            switch result {
            case .success(let url):
                self?.statusLabel.text = "完成：\(url.lastPathComponent)\n位置：文件 App → CarPlayCast"
            case .failure(let error):
                self?.statusLabel.text = error.localizedDescription
            }
        }
    }
}

extension CompensateViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("source.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)")
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: url, to: dst)
        source = dst
        statusLabel.text = "已选择：\(url.lastPathComponent)"
    }
}
