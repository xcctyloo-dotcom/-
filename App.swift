import AVFoundation
import CarPlay
import PhotosUI
import Network
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

// MARK: - 工具

enum Format {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds).rounded())
        if s >= 3600 { return "\(s / 3600) 小时 \((s % 3600) / 60) 分" }
        if s >= 60 { return "\(s / 60) 分 \(s % 60) 秒" }
        return "\(s) 秒"
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// 每次启动清掉上次留下的临时拷贝，避免越积越多
enum TempCleaner {
    static func clean() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(at: tmp,
                                                                       includingPropertiesForKeys: nil) else { return }
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix("source.") || name == "audio.m4a" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - App 入口

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        TempCleaner.clean()
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

// MARK: - 主菜单

final class MenuViewController: UIViewController {

    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "CarPlayCast"
        view.backgroundColor = .systemGroupedBackground

        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scroll)
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])

        build()
    }

    private func build() {
        addSection("车机")
        addCard("车载播放", "车机主屏出现「车载播放」列表，播放测试音") { [weak self] in
            self?.showAlert("插上 CarPlay 后，车机主屏会出现「车载播放」。\n\n如果没出现，是 CarPlay 权限没被系统认，和代码无关。")
        }

        addSection("手机播放 · 声音走车机")
        addCard("视频同步", "画面在手机，声音走车机，可调音画偏移") { [weak self] in
            self?.navigationController?.pushViewController(VideoSyncViewController(), animated: true)
        }

        addSection("给车机播放器用（CarMovie 等）")
        addCard("补偿版导出", "可批量：同一偏移排队导出多个视频") { [weak self] in
            self?.navigationController?.pushViewController(CompensateViewController(), animated: true)
        }
        addCard("本地播放（免导入）", "起本地链接，CarMovie 按 URL 直接播") { [weak self] in
            self?.navigationController?.pushViewController(LocalServerViewController(), animated: true)
        }
        addCard("已导出文件", "批量选择、分享、删除导出的视频") { [weak self] in
            self?.navigationController?.pushViewController(ExportedFilesViewController(), animated: true)
        }

        addSection("说明")
        addCard("这个 App 能做什么", "三种模式的区别与各自的上限") { [weak self] in
            self?.navigationController?.pushViewController(AboutViewController(), animated: true)
        }

        let footer = UILabel()
        footer.numberOfLines = 0
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .tertiaryLabel
        footer.text = "CarPlay 没有公开的视频通道。车机上放视频只能靠私有接口（CarMovie 那种），本 App 不做。"
        stack.addArrangedSubview(footer)
    }

    private func addSection(_ title: String) {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        let box = UIStackView(arrangedSubviews: [label])
        box.isLayoutMarginsRelativeArrangement = true
        box.layoutMargins = UIEdgeInsets(top: 8, left: 4, bottom: 0, right: 4)
        stack.addArrangedSubview(box)
    }

    private func addCard(_ title: String, _ subtitle: String, _ action: @escaping () -> Void) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.subtitle = subtitle
        config.cornerStyle = .large
        config.baseBackgroundColor = .secondarySystemGroupedBackground
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        config.titleAlignment = .leading

        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
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

/// 运行时合成 440Hz 测试音，省掉二进制资源
enum ToneFile {

    static func url() -> URL? {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("tone.wav")
        if FileManager.default.fileExists(atPath: dst.path) { return dst }

        let sampleRate = 44100
        let count = sampleRate * 2
        let dataLen = count * 2
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
            NSLog("tone write failed: \(error)")
            return nil
        }
    }
}

final class AudioHub {

    static let shared = AudioHub()
    private var player: AVAudioPlayer?
    private var configured = false

    private init() {}

    var isPlaying: Bool { player?.isPlaying ?? false }

    func configureSession() {
        guard !configured else { return }
        configured = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("audio session: \(error)")
        }
        installRemote()
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

    private func installRemote() {
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

    private let offsetLabel = UILabel()
    private let statusLabel = UILabel()
    private let timeLabel = UILabel()
    private let seekBar = UISlider()
    private let offsetSlider = UISlider()

    private var videoPlayer: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var pending: DispatchWorkItem?
    private var ticker: Timer?
    private var lastCorrection = Date.distantPast
    private var playbackOffset: Double = 0
    private var isSeeking = false

    private var offsetMs: Double {
        get { OffsetStore.current }
        set { OffsetStore.current = newValue }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "视频同步"
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

    // MARK: UI

    private func buildPanel() {
        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        offsetLabel.textColor = .systemYellow

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .right

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .systemGray
        statusLabel.numberOfLines = 0

        offsetSlider.minimumValue = 0
        offsetSlider.maximumValue = 600
        offsetSlider.addTarget(self, action: #selector(offsetChanged), for: .valueChanged)

        seekBar.minimumValue = 0
        seekBar.maximumValue = 1
        seekBar.addTarget(self, action: #selector(seekBegan), for: .touchDown)
        seekBar.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        seekBar.addTarget(self, action: #selector(seekEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let row = UIStackView(arrangedSubviews: [
            makeButton("选视频", #selector(pickVideo)),
            makeButton("播放/暂停", #selector(togglePlay)),
            makeButton("回退 10s", #selector(backTen))
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
        [offsetLabel, offsetSlider, fine, seekBar, timeLabel, row, statusLabel]
            .forEach { panel.addArrangedSubview($0) }

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

        refreshOffsetLabel()
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }

    private func refreshOffsetLabel() {
        offsetLabel.text = String(format: "音画补偿 %.0f ms（画面延后）", offsetMs)
    }

    @objc private func offsetChanged() {
        offsetMs = Double(offsetSlider.value).rounded()
        refreshOffsetLabel()
    }

    @objc private func minusTapped() { nudge(-10) }
    @objc private func plusTapped() { nudge(10) }

    private func nudge(_ delta: Double) {
        offsetMs = min(600, max(0, offsetMs + delta))
        offsetSlider.value = Float(offsetMs)
        refreshOffsetLabel()
    }

    // MARK: 载入

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
        offsetSlider.value = Float(offsetMs)
        refreshOffsetLabel()
        extractAudio(from: asset, presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A])
    }

    private func extractAudio(from asset: AVAsset, presets: [String]) {
        guard asset.tracks(withMediaType: .audio).first != nil else {
            statusLabel.text = "这个文件没有音轨"
            return
        }
        guard let preset = presets.first else {
            statusLabel.text = "音轨分离失败：格式不支持，已取消静音（能听但不同步）"
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
                guard let player = try? AVAudioPlayer(contentsOf: out) else { return }
                player.prepareToPlay()
                self?.audioPlayer = player
                self?.seekBar.maximumValue = Float(player.duration)
                self?.statusLabel.text = "就绪 · 拖动上面的进度条可以跳转"
            }
        }
    }

    // MARK: 播放控制

    @objc private func togglePlay() {
        if audioPlayer?.isPlaying == true {
            stopAll()
        } else {
            startPlayback(x: 0)
        }
    }

    private func startPlayback(x: Double) {
        guard let videoPlayer, let audioPlayer else {
            statusLabel.text = "还没选视频，或者音轨还没分离完"
            return
        }
        pending?.cancel()

        audioPlayer.currentTime = max(0, min(x, audioPlayer.duration - 0.05))
        let videoTime = max(0, audioPlayer.currentTime - offsetMs / 1000)
        videoPlayer.seek(to: CMTime(seconds: videoTime, preferredTimescale: 600))

        audioPlayer.play()
        let delay = max(0, offsetMs) / 1000.0
        let work = DispatchWorkItem { [weak self] in
            self?.videoPlayer?.play()
            self?.startTicker()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopAll() {
        pending?.cancel()
        ticker?.invalidate()
        ticker = nil
        audioPlayer?.pause()
        videoPlayer?.pause()
    }

    @objc private func backTen() {
        guard let audio = audioPlayer else { return }
        let target = max(0, audio.currentTime - 10)
        if audio.isPlaying {
            startPlayback(x: target)
        } else {
            audio.currentTime = target
            videoPlayer?.seek(to: CMTime(seconds: max(0, target - offsetMs / 1000), preferredTimescale: 600))
            updateTimeLabel()
        }
    }

    // MARK: 进度条

    @objc private func seekBegan() { isSeeking = true }

    @objc private func seekChanged() {
        timeLabel.text = "\(Format.time(Double(seekBar.value))) / \(Format.time(audioPlayer?.duration ?? 0))"
    }

    @objc private func seekEnded() {
        guard let audio = audioPlayer else { return }
        let wasPlaying = audio.isPlaying
        stopAll()
        let target = Double(seekBar.value)
        if wasPlaying {
            isSeeking = false
            startPlayback(x: target)
        } else {
            audio.currentTime = target
            videoPlayer?.seek(to: CMTime(seconds: max(0, target - offsetMs / 1000), preferredTimescale: 600))
            isSeeking = false
            updateTimeLabel()
        }
    }

    // MARK: 定时器：刷新进度 + 纠偏

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    private func tick() {
        guard let audio = audioPlayer, let video = videoPlayer else { return }

        if !isSeeking {
            seekBar.value = Float(audio.currentTime)
        }
        updateTimeLabel()

        guard audio.isPlaying else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCorrection) > 2 else { return }
        lastCorrection = now

        let audioTimeline = audio.currentTime - offsetMs / 1000
        let videoTime = video.currentTime().seconds
        guard videoTime.isFinite else { return }
        if abs(audioTimeline - videoTime) > 0.12 {
            video.seek(to: CMTime(seconds: max(0, audioTimeline), preferredTimescale: 600),
                       toleranceBefore: .zero, toleranceAfter: .zero)
            statusLabel.text = "已自动纠偏一次"
        }
    }

    private func updateTimeLabel() {
        let current = audioPlayer?.currentTime ?? 0
        let duration = audioPlayer?.duration ?? 0
        timeLabel.text = "\(Format.time(current)) / \(Format.time(duration))"
    }
}

extension VideoSyncViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        load(original: url)
    }
}

// MARK: - 补偿导出

enum CompensateError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "这个文件没有视频轨"
        case .exportFailed(let message): return "导出失败：\(message)"
        }
    }
}

enum CompensateExporter {

    static var timer: Timer?
    static var current: AVAssetExportSession?

    /// 先试直通（只改写时间戳，最快），失败再退回重编码
    private static let presets = [
        AVAssetExportPresetPassthrough,
        AVAssetExportPreset1280x720,
        AVAssetExportPresetHighestQuality
    ]

    static func cancel() {
        current?.cancelExport()
        timer?.invalidate()
        timer = nil
    }

    static func documentsDir() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func freeSpace() -> Int64 {
        let values = try? documentsDir().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    static func outputURL(source: URL, offsetMs: Double) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let sign = offsetMs >= 0 ? "p" : "m"
        let stamp = Int(Date().timeIntervalSince1970)
        return documentsDir().appendingPathComponent("\(base)_\(sign)\(Int(abs(offsetMs)))ms_\(stamp).mp4")
    }

    /// offsetMs > 0：音频后移；offsetMs < 0：画面后移
    static func export(source: URL,
                       offsetMs: Double,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
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

        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                          of: videoTrack,
                                          at: offsetMs < 0 ? shift : .zero)
            if let audioTrack, let compAudio {
                try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                              of: audioTrack,
                                              at: offsetMs > 0 ? shift : .zero)
            }
        } catch {
            completion(.failure(CompensateError.exportFailed(error.localizedDescription)))
            return
        }

        run(composition: composition,
            out: outputURL(source: source, offsetMs: offsetMs),
            presets: presets,
            progress: progress,
            completion: completion)
    }

    private static func run(composition: AVComposition,
                            out: URL,
                            presets: [String],
                            progress: @escaping (Double) -> Void,
                            completion: @escaping (Result<URL, Error>) -> Void) {
        guard let preset = presets.first else {
            completion(.failure(CompensateError.exportFailed("没有可用的导出格式")))
            return
        }
        try? FileManager.default.removeItem(at: out)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            run(composition: composition, out: out, presets: Array(presets.dropFirst()),
                progress: progress, completion: completion)
            return
        }
        exporter.outputURL = out
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        current = exporter

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            progress(Double(exporter.progress))
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                CompensateExporter.timer?.invalidate()
                CompensateExporter.timer = nil
                CompensateExporter.current = nil

                switch exporter.status {
                case .completed:
                    progress(1)
                    completion(.success(out))
                case .cancelled:
                    try? FileManager.default.removeItem(at: out)
                    completion(.failure(CompensateError.exportFailed("已取消")))
                default:
                    let rest = Array(presets.dropFirst())
                    if rest.isEmpty {
                        completion(.failure(CompensateError.exportFailed(
                            exporter.error?.localizedDescription ?? "未知错误")))
                    } else {
                        run(composition: composition, out: out, presets: rest,
                            progress: progress, completion: completion)
                    }
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
    private let progressBar = UIProgressView(progressViewStyle: .default)

    private var sources: [URL] = []
    private var sourceSizes: [Int64] = []
    private var offsetMs: Double = OffsetStore.current
    private var exporting = false
    private var cancelling = false
    private var startedAt: Date?
    private var completed = 0
    private var failed = 0
    private var currentIndex = 0
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var actionButton: UIButton?
    private var lastExport: URL?
    private var outputs: [URL] = []

    private lazy var shareButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "分享最后一份"
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.presentShare() }, for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "补偿版导出"
        view.backgroundColor = .systemGroupedBackground
        buildUI()
    }

    // MARK: UI

    private func buildUI() {
        let help = UILabel()
        help.numberOfLines = 0
        help.font = .systemFont(ofSize: 13)
        help.textColor = .secondaryLabel
        help.text = """
        判断方向：
        · 先听到声、后看到动作 → 声音偏早，用正值（音频后移）
        · 先看到动作、后听到声 → 声音偏晚，用负值（画面后移）

        可以一次选多个视频，用同一个偏移排队导出。
        导出期间请留在本页：iOS 只给约 30 秒后台时间。
        """

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textAlignment = .center

        slider.minimumValue = -400
        slider.maximumValue = 400
        slider.value = Float(offsetMs)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        progressBar.progress = 0
        progressBar.isHidden = true

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        let presetRow = UIStackView(arrangedSubviews: [
            makePresetButton("−100", -100),
            makePresetButton("0", 0),
            makePresetButton("+100", 100),
            makePresetButton("+150", 150),
            makePresetButton("+200", 200)
        ])
        presetRow.axis = .horizontal
        presetRow.distribution = .fillEqually
        presetRow.spacing = 6

        let exportButton = makeButton("导出补偿版", #selector(runExport))
        actionButton = exportButton
        shareButton.isHidden = true

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 20, right: 20)

        [help, valueLabel, slider, presetRow,
         makeButton("自动测量延迟", #selector(measureTapped)),
         makeButton("从相册选择（可多选）", #selector(pickFromPhotos)),
         makeButton("从文件选择（可多选）", #selector(pickVideo)),
         exportButton, progressBar, statusLabel, shareButton].forEach { stack.addArrangedSubview($0) }
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        refresh()
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makePresetButton(_ title: String, _ value: Double) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.addAction(UIAction { [weak self] _ in self?.applyPreset(value) }, for: .touchUpInside)
        return button
    }

    private func setActionTitle(_ title: String) {
        actionButton?.configuration?.title = title
        actionButton?.setTitle(title, for: .normal)
    }

    private func refresh() {
        let direction = offsetMs > 0 ? "音频后移" : (offsetMs < 0 ? "画面后移" : "不偏移")
        valueLabel.text = String(format: "%+.0f ms · %@", offsetMs, direction)

        if !exporting {
            setActionTitle(sources.count > 1 ? "导出补偿版（\(sources.count) 个）" : "导出补偿版")
        }
    }

    @objc private func sliderChanged() {
        offsetMs = Double(slider.value).rounded()
        refresh()
        OffsetStore.current = offsetMs
    }

    private func applyPreset(_ value: Double) {
        offsetMs = value
        slider.value = Float(value)
        refresh()
        OffsetStore.current = value
    }

    // MARK: 选视频

    @objc private func pickVideo() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    // MARK: 导出

    @objc private func runExport() {
        if exporting {
            cancelling = true
            CompensateExporter.cancel()
            statusLabel.text = "正在取消…"
            return
        }
        guard !sources.isEmpty else {
            statusLabel.text = "先选视频"
            return
        }
        guard abs(offsetMs) >= 1 else {
            statusLabel.text = "偏移是 0，不用导出"
            return
        }

        let totalSource = sourceSizes.reduce(0, +)
        let needed = Int64(Double(totalSource) * 1.2)
        let free = CompensateExporter.freeSpace()
        if free > 0 && free < needed {
            statusLabel.text = "空间不足：需要约 \(Format.bytes(needed))，可用 \(Format.bytes(free))"
            return
        }

        OffsetStore.current = offsetMs

        if batteryTooLow() {
            let alert = UIAlertController(title: "电量低于 20%",
                                          message: "导出比较耗电，建议先接电源。现在继续吗？",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "先不导", style: .cancel))
            alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self] _ in
                self?.startQueue()
            })
            present(alert, animated: true)
            return
        }

        startQueue()
    }

    private func startQueue() {
        exporting = true
        cancelling = false
        completed = 0
        failed = 0
        currentIndex = 0
        lastExport = nil
        outputs = []
        startedAt = Date()
        shareButton.isHidden = true
        progressBar.isHidden = false
        progressBar.progress = 0
        setActionTitle("取消")
        statusLabel.text = sources.count > 1 ? "准备中…共 \(sources.count) 个" : "准备中…"

        UIApplication.shared.isIdleTimerDisabled = true
        bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }

        runNext()
    }

    private func runNext() {
        guard currentIndex < sources.count else {
            finishQueue()
            return
        }

        let url = sources[currentIndex]
        CompensateExporter.export(source: url, offsetMs: offsetMs, progress: { [weak self] p in
            guard let self else { return }
            let overall = (Double(self.completed + self.failed) + p) / Double(max(1, self.sources.count))
            self.updateProgress(overall: overall, current: p)
        }, completion: { [weak self] result in
            guard let self else { return }

            if self.cancelling {
                self.finishQueue()
                return
            }

            switch result {
            case .success(let output):
                self.completed += 1
                self.lastExport = output
                self.outputs.append(output)
            case .failure(let error):
                self.failed += 1
                Log.write("export failed \(url.lastPathComponent): \(error.localizedDescription)")
            }

            self.currentIndex += 1
            self.runNext()
        })
    }

    private func finishQueue() {
        exporting = false
        let wasCancelled = cancelling
        cancelling = false
        setActionTitle("导出补偿版")
        progressBar.isHidden = true
        UIApplication.shared.isIdleTimerDisabled = false
        endBackground()

        if sources.count == 1 {
            OffsetStore.saveOffset(offsetMs, forSize: sourceSizes.first ?? 0)
        }

        if let lastExport {
            shareButton.isHidden = false
            var config = shareButton.configuration
            config?.title = outputs.count > 1 ? "一次性交给 CarMovie（\(outputs.count) 个）" : "分享这份文件"
            shareButton.configuration = config
            let size = Int64((try? lastExport.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if sources.count > 1 {
                statusLabel.text = "完成 \(completed) 个，失败 \(failed) 个\(wasCancelled ? "（已取消）" : "")\n最后一份 \(Format.bytes(size)) · 文件 App → CarPlayCast"
            } else {
                statusLabel.text = "完成 · \(Format.bytes(size))\n\(lastExport.lastPathComponent)\n位置：文件 App → CarPlayCast"
            }
        } else if sources.count > 1 {
            statusLabel.text = "完成 \(completed) 个，失败 \(failed) 个\(wasCancelled ? "（已取消）" : "")"
        } else {
            statusLabel.text = wasCancelled ? "已取消" : "导出失败"
        }
    }

    private func updateProgress(overall: Double, current: Double) {
        progressBar.setProgress(Float(min(max(overall, 0), 1)), animated: true)

        var text: String
        if sources.count > 1 {
            text = "第 \(min(currentIndex + 1, sources.count))/\(sources.count) 个 · \(Int(current * 100))%"
        } else {
            text = "\(Int(current * 100))%"
        }

        if overall > 0.03, let startedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            let total = elapsed / overall
            text += " · 预计还需 " + Format.duration(max(0, total - elapsed))
        } else {
            text += " · 估算中…"
        }
        statusLabel.text = text
    }

    private func presentShare() {
        let items = outputs.isEmpty ? (lastExport.map { [$0] } ?? []) : outputs
        guard !items.isEmpty else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        present(controller, animated: true)
    }

    private func batteryTooLow() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return false }
        return level < 0.2 && UIDevice.current.batteryState != .charging
    }

    private func endBackground() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}

extension CompensateViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        applySelection(urls)
    }
}

// MARK: - 已导出文件

final class ExportedFilesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let bar = UIStackView()
    private let selectAllButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var files: [URL] = []
    private var selecting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "已导出"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "选择", style: .plain,
                                                            target: self,
                                                            action: #selector(toggleSelecting))

        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelectionDuringEditing = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        buildBar()

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: 底栏

    private func buildBar() {
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        bar.backgroundColor = .secondarySystemGroupedBackground
        bar.translatesAutoresizingMaskIntoConstraints = false

        let items: [(UIButton, String, Selector)] = [
            (selectAllButton, "全选", #selector(toggleSelectAll)),
            (shareButton, "分享", #selector(shareSelected)),
            (deleteButton, "删除", #selector(deleteSelected))
        ]
        for (button, title, action) in items {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.addTarget(self, action: action, for: .touchUpInside)
            bar.addArrangedSubview(button)
        }
        deleteButton.tintColor = .systemRed

        view.addSubview(bar)
        updateBar()
    }

    private func updateBar() {
        let count = table.indexPathsForSelectedRows?.count ?? 0
        let enabled = selecting && count > 0
        shareButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
        selectAllButton.isEnabled = selecting
        shareButton.setTitle(count > 1 ? "分享 (\(count))" : "分享", for: .normal)
        deleteButton.setTitle(count > 1 ? "删除 (\(count))" : "删除", for: .normal)
    }

    @objc private func toggleSelecting() {
        selecting.toggle()
        table.setEditing(selecting, animated: true)
        navigationItem.rightBarButtonItem?.title = selecting ? "完成" : "选择"
        if !selecting { clearSelection() }
        table.reloadData()
        updateBar()
    }

    @objc private func toggleSelectAll() {
        guard selecting else { return }
        let allSelected = (table.indexPathsForSelectedRows?.count ?? 0) == files.count
        if allSelected {
            clearSelection()
        } else {
            for row in files.indices {
                table.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
        }
        updateBar()
    }

    private func clearSelection() {
        (table.indexPathsForSelectedRows ?? []).forEach {
            table.deselectRow(at: $0, animated: false)
        }
        updateBar()
    }

    private func selectedURLs() -> [URL] {
        let rows = (table.indexPathsForSelectedRows ?? []).sorted { $0.row < $1.row }
        return rows.compactMap { files.indices.contains($0.row) ? files[$0.row] : nil }
    }

    @objc private func shareSelected() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = bar
        present(controller, animated: true)
    }

    @objc private func deleteSelected() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }

        let alert = UIAlertController(title: "删除 \(urls.count) 个文件？",
                                      message: "删了就找不回来了",
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
            self.selecting = false
            self.table.setEditing(false, animated: true)
            self.navigationItem.rightBarButtonItem?.title = "选择"
            self.reload()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = bar
        present(alert, animated: true)
    }

    // MARK: 数据

    private func reload() {
        let dir = CompensateExporter.documentsDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        table.reloadData()
        updateBar()
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let url = files[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = url.lastPathComponent
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        content.secondaryText = Format.bytes(size)
        cell.contentConfiguration = content
        cell.accessoryType = selecting ? .none : .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selecting {
            updateBar()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let url = files[indexPath.row]
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = tableView
        share.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(share, animated: true)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        updateBar()
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !selecting else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { return done(false) }
            try? FileManager.default.removeItem(at: self.files[indexPath.row])
            self.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - 说明

final class AboutViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "说明"
        view.backgroundColor = .systemGroupedBackground

        let text = UITextView()
        text.isEditable = false
        text.backgroundColor = .clear
        text.font = .systemFont(ofSize: 15)
        text.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.text = """
        三种模式

        1. 车载播放
        车机主屏的列表，播的是 440Hz 测试音。它证明 CarPlay 通道是通的。

        2. 视频同步（画面在手机，声音走车机）
        视频在手机上放，声音从车里出。因为声音要过 CarPlay 管道，会比画面晚 80~200ms，
        所以让画面延后同样的时间。滑杆 0~600ms，拖到「听到的啪」和「看到的啪」重合。
        播放时每 2 秒比对一次时间轴，偏差超过 120ms 自动纠偏。

        3. 补偿版导出（给 CarMovie 这类车机播放器用）
        它们内部时序改不了，就把补偿做进文件：导出一份新 MP4，
        音频整体平移 X 毫秒。用 CarMovie 打开新文件，音画就是齐的。

        边界

        · CarPlay 没有公开的视频通道，第三方 App 在车机上放视频只能靠私有接口
        · 补偿值是每台车一个常数，换车、换有线/无线都要重调
        · 导出期间要留在前台，iOS 只给约 30 秒后台时间
        · 流媒体链接（m3u8）没法预先补偿，只能处理本地文件
        """
        view.addSubview(text)

        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - 偏移存储（按车记忆）

/// 每台车、每种连接单独存一个偏移。CarPlay 的音频输出端口名就是车机名。
enum OffsetStore {

    private static let mapKey = "offsetByRoute"
    private static let lastKey = "lastOffsetMs"

    static var routeName: String {
        let name = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName
        if let name, !name.isEmpty { return name }
        return "手机"
    }

    static var isCarPlay: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            $0.portType == .carAudio
        }
    }

    static var current: Double {
        get {
            let map = UserDefaults.standard.dictionary(forKey: mapKey) ?? [:]
            if let value = map[routeName] as? Double { return value }
            if let last = UserDefaults.standard.object(forKey: lastKey) as? Double { return last }
            return 120
        }
        set {
            var map = UserDefaults.standard.dictionary(forKey: mapKey) ?? [:]
            map[routeName] = newValue
            UserDefaults.standard.set(map, forKey: mapKey)
            UserDefaults.standard.set(newValue, forKey: lastKey)
        }
    }

    private static let fileKey = "offsetByFile"

    /// 用文件体积做指纹：同一部片子反复导入，体积不变
    static func storedOffset(forSize size: Int64) -> Double? {
        guard size > 0 else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: fileKey) ?? [:]
        return map["\(size)"] as? Double
    }

    static func saveOffset(_ value: Double, forSize size: Int64) {
        guard size > 0 else { return }
        var map = UserDefaults.standard.dictionary(forKey: fileKey) ?? [:]
        map["\(size)"] = value
        UserDefaults.standard.set(map, forKey: fileKey)
    }

    static var summary: String {
        let map = UserDefaults.standard.dictionary(forKey: mapKey) ?? [:]
        guard !map.isEmpty else { return "还没有保存过任何车的偏移" }
        return map.map { "\($0.key)：\(Int(($0.value as? Double) ?? 0)) ms" }
            .sorted()
            .joined(separator: "\n")
    }
}

// MARK: - 日志

enum Log {

    static func fileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug.log")
    }

    static func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let url = fileURL()
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - 测量用的咔哒声

enum ClickFile {

    static func url() -> URL? {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("click.wav")
        if FileManager.default.fileExists(atPath: dst.path) { return dst }

        let sampleRate = 44100
        let count = sampleRate / 20          // 50ms
        let dataLen = count * 2
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

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let decay = exp(-t * 60)
            let value = sin(2 * .pi * 1000 * t) * decay * 0.9
            put(Int16(max(-32767, min(32767, value * 32767))))
        }

        do {
            try data.write(to: dst)
            return dst
        } catch {
            return nil
        }
    }
}

// MARK: - 波形分析

enum AudioAnalysis {

    /// 返回所有“起音”的时间点（秒），带最小间隔去抖
    static func onsets(fileURL: URL, minGap: Double = 0.2) -> [Double] {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return [] }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return [] }
        guard (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return [] }

        let count = Int(buffer.frameLength)
        var peak: Float = 0
        for i in 0..<count {
            let value = abs(channel[i])
            if value > peak { peak = value }
        }
        guard peak > 0.02 else { return [] }

        let threshold = max(0.05, peak * 0.25)
        var result: [Double] = []
        var run = 0
        var lastTime = -1.0

        for i in 0..<count {
            if abs(channel[i]) > threshold {
                run += 1
                if run >= 3 {
                    let time = Double(i - 2) / format.sampleRate
                    if time - lastTime > minGap {
                        result.append(time)
                        lastTime = time
                    }
                    run = 0
                }
            } else {
                run = 0
            }
        }
        return result
    }
}

// MARK: - 自动测量

final class Calibrator {

    static let shared = Calibrator()

    /// 三次咔哒的起播时间（相对录音开始）
    private static let clickTimes: [Double] = [0.35, 0.85, 1.35]

    enum MeasureError: LocalizedError {
        case noPermission
        case busy
        case noSignal
        case notCarPlay(String)
        case outOfRange(Double)

        var errorDescription: String? {
            switch self {
            case .noPermission: return "没有麦克风权限，去设置里允许"
            case .busy: return "录音启动失败，可能被别的 App 占用"
            case .noSignal: return "没听到咔哒声，检查车机音量，或换个安静环境"
            case .notCarPlay(let name):
                return "当前输出是「\(name)」，不是车机。先连上 CarPlay 再测"
            case .outOfRange(let ms):
                return String(format: "测到 %.0f ms，明显不对，建议手动调", ms)
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var players: [AVAudioPlayer] = []
    private var startedAt: Date?
    private var completion: ((Result<Double, Error>) -> Void)?

    private init() {}

    func measure(completion: @escaping (Result<Double, Error>) -> Void) {
        guard recorder == nil else {
            completion(.failure(MeasureError.busy))
            return
        }
        self.completion = completion

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.finish(.failure(MeasureError.noPermission))
                    return
                }
                self.start()
            }
        }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .measurement 关掉系统输入处理，避免 AGC / 降噪改变时序
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            finish(.failure(error))
            return
        }

        let output = session.currentRoute.outputs.first
        guard output?.portType == .carAudio else {
            finish(.failure(MeasureError.notCarPlay(output?.portName ?? "手机扬声器")))
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cal.wav")
        try? FileManager.default.removeItem(at: url)

        // PCM/WAV：没有编码器延迟，时间点才是准的
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            finish(.failure(MeasureError.busy))
            return
        }
        self.recorder = recorder
        guard recorder.record() else {
            finish(.failure(MeasureError.busy))
            return
        }
        startedAt = Date()

        guard let clickURL = ClickFile.url() else {
            finish(.failure(MeasureError.noSignal))
            return
        }

        for time in Self.clickTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                if let player = try? AVAudioPlayer(contentsOf: clickURL) {
                    player.play()
                    self.players.append(player)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.stopAndAnalyze()
        }
    }

    private func stopAndAnalyze() {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil

        guard let url else {
            finish(.failure(MeasureError.noSignal))
            return
        }

        let onsets = AudioAnalysis.onsets(fileURL: url)
        guard !onsets.isEmpty else {
            finish(.failure(MeasureError.noSignal))
            return
        }

        // 不假设“第几个起音”对应“第几声咔哒”，而是按时间就近配对，
        // 这样漏掉第一声也不会整体错 500ms
        var deltas: [Double] = []
        for onset in onsets {
            guard let nearest = Self.clickTimes.min(by: { abs($0 - onset) < abs($1 - onset) }),
                  abs(onset - nearest) < 0.45 else { continue }
            deltas.append(onset - nearest)
        }
        guard !deltas.isEmpty else {
            finish(.failure(MeasureError.noSignal))
            return
        }

        deltas.sort()
        let median = deltas[deltas.count / 2]

        // 扣掉麦克风输入链路的固定延迟
        let inputLatency = min(AVAudioSession.sharedInstance().inputLatency, 0.1)
        let ms = (median - inputLatency) * 1000

        if ms < 20 || ms > 400 {
            finish(.failure(MeasureError.outOfRange(ms)))
        } else {
            // 测到的是“声音晚到多少”，对应的操作是让画面后移，所以取负
            finish(.success(-ms.rounded()))
        }
    }

    private func finish(_ result: Result<Double, Error>) {
        players.forEach { $0.stop() }
        players.removeAll()
        recorder = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        let callback = completion
        completion = nil
        callback?(result)
    }
}

// MARK: - 自动测量入口

extension CompensateViewController {

    @objc fileprivate func measureTapped() {
        guard !exporting else { return }

        statusLabel.text = "测量中：保持安静，车里会响三声"
        Calibrator.shared.measure { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let ms):
                self.offsetMs = ms
                self.slider.value = Float(ms)
                self.refresh()
                OffsetStore.current = ms
                Log.write("calibrated \(Int(ms))ms on \(OffsetStore.routeName)")
                let direction = ms < 0 ? "画面后移" : "音频后移"
                self.statusLabel.text = String(format: "测量完成：%.0f ms（%@）· 已保存到「%@」", ms, direction, OffsetStore.routeName)
            case .failure(let error):
                Log.write("calibration failed: \(error.localizedDescription)")
                self.statusLabel.text = "测量失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 从相册导入

extension CompensateViewController: PHPickerViewControllerDelegate {

    @objc fileprivate func pickFromPhotos() {
        guard !exporting else { return }
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        let providers = results.map { $0.itemProvider }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
        guard !providers.isEmpty else { return }

        statusLabel.text = "正在从相册导入 \(providers.count) 个…"
        importProviders(providers, index: 0, collected: [])
    }

    private func importProviders(_ providers: [NSItemProvider], index: Int, collected: [URL]) {
        guard index < providers.count else {
            applySelection(collected)
            return
        }

        let provider = providers[index]
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            var copied: URL?
            if let url {
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let formatter = DateFormatter()
                formatter.dateFormat = "MMdd_HHmmss"
                let stamp = formatter.string(from: Date())
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("相机_\(stamp)_\(index + 1).\(ext)")
                try? FileManager.default.removeItem(at: dst)
                if (try? FileManager.default.copyItem(at: url, to: dst)) != nil {
                    copied = dst
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                var next = collected
                if let copied { next.append(copied) }
                self.importProviders(providers, index: index + 1, collected: next)
            }
        }
    }

    fileprivate func applySelection(_ urls: [URL]) {
        sources = urls
        sourceSizes = urls.map { url in
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        lastExport = nil
        shareButton.isHidden = true

        let total = sourceSizes.reduce(0, +)
        if urls.count == 1, let first = urls.first {
            var note = ""
            if let remembered = OffsetStore.storedOffset(forSize: sourceSizes.first ?? 0) {
                offsetMs = remembered
                slider.value = Float(remembered)
                note = String(format: " · 已载入上次的 %.0f ms", remembered)
            }
            statusLabel.text = "已选：\(first.lastPathComponent) · \(Format.bytes(total))\(note)"
        } else if urls.count > 1 {
            statusLabel.text = "已选 \(urls.count) 个 · 共 \(Format.bytes(total))"
        } else {
            statusLabel.text = "没选到视频"
        }
        refresh()
    }
}

// MARK: - 本地 HTTP 服务（给 CarMovie 之类按 URL 播的播放器用）

import Network

final class LocalFileServer {

    static let shared = LocalFileServer()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private(set) var port: UInt16 = 0

    var isRunning: Bool { listener != nil }

    private init() {}

    func start(completion: @escaping (UInt16) -> Void) {
        guard listener == nil else {
            completion(port)
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        // 注意：不能给“监听器”设 requiredLocalEndpoint，会直接崩溃。
        // 只接受本机连接，靠下面的 isLoopback 过滤。
        guard let listener = try? NWListener(using: params, on: .any) else {
            completion(0)
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue ?? 0
                completion(self.port)
            case .failed, .cancelled:
                self.listener = nil
                self.port = 0
            default:
                break
            }
        }

        self.listener = listener
        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    func url(for file: URL) -> String? {
        guard port != 0 else { return nil }
        let name = file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.lastPathComponent
        return "http://127.0.0.1:\(port)/\(name)"
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let self else { return }
                if !self.isLoopback(connection) {
                    self.close(connection)
                }
            case .failed, .cancelled:
                self?.close(connection)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, buffer: Data())
    }

    private func isLoopback(_ connection: NWConnection) -> Bool {
        guard let remote = connection.currentPath?.remoteEndpoint,
              case let .hostPort(host, _) = remote else {
            return false
        }
        let text = "\(host)"
        return text.contains("127.0.0.1") || text.contains("::1")
    }

    private func close(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(on: connection, request: header)
                return
            }

            if isComplete || error != nil || accumulated.count > 64 * 1024 {
                self.close(connection)
                return
            }
            self.receive(on: connection, buffer: accumulated)
        }
    }

    // MARK: 响应

    private func respond(on connection: NWConnection, request: String) {
        let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { close(connection); return }

        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { close(connection); return }

        var path = String(parts[1])
        if let mark = path.firstIndex(of: "?") { path = String(path[..<mark]) }
        path = path.removingPercentEncoding ?? path

        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, !name.contains("..") else { close(connection); return }

        let file = CompensateExporter.documentsDir().appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else {
            sendText(connection, status: "404 Not Found", text: "not found")
            return
        }

        guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
              let total = attributes.fileSize else {
            sendText(connection, status: "500 Internal Server Error", text: "no size")
            return
        }

        var rangeStart = 0
        var rangeEnd = total - 1

        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            let value = String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
            guard let equal = value.firstIndex(of: "=") else { continue }
            let spec = value[value.index(after: equal)...]
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 2 {
                if let start = Int(bounds[0]) { rangeStart = start }
                if let end = Int(bounds[1]) { rangeEnd = end }
            }
        }

        rangeStart = max(0, min(rangeStart, total - 1))
        rangeEnd = max(rangeStart, min(rangeEnd, total - 1))
        let length = rangeEnd - rangeStart + 1
        let isPartial = (rangeStart != 0 || rangeEnd != total - 1)

        var head = "HTTP/1.1 " + (isPartial ? "206 Partial Content" : "200 OK") + "\r\n"
        head += "Content-Type: video/mp4\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += "Content-Length: \(length)\r\n"
        if isPartial {
            head += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(total)\r\n"
        }
        head += "Connection: close\r\n\r\n"

        connection.send(content: Data(head.utf8),
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.close(connection)
                return
            }
            guard let handle = try? FileHandle(forReadingFrom: file) else {
                self.close(connection)
                return
            }
            handle.seek(toFileOffset: UInt64(rangeStart))
            self.pump(handle: handle, remaining: length, connection: connection)
        })
    }

    private func pump(handle: FileHandle, remaining: Int, connection: NWConnection) {
        if remaining <= 0 {
            try? handle.close()
            connection.send(content: nil,
                            contentContext: .finalMessage,
                            isComplete: true,
                            completion: .contentProcessed { [weak self] _ in
                self?.close(connection)
            })
            return
        }

        let chunk = min(256 * 1024, remaining)
        let data = handle.readData(ofLength: chunk)
        guard !data.isEmpty else {
            try? handle.close()
            close(connection)
            return
        }

        connection.send(content: data,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                try? handle.close()
                self.close(connection)
                return
            }
            self.pump(handle: handle, remaining: remaining - data.count, connection: connection)
        })
    }

    private func sendText(_ connection: NWConnection, status: String, text: String) {
        let body = Data(text.utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: text/plain; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload,
                        contentContext: .finalMessage,
                        isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }
}

// MARK: - 本地播放页

final class LocalServerViewController: UIViewController, UITableViewDataSource {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let toggleButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    private var files: [URL] = []
    private var baseURL: String = "未启动"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地播放"
        view.backgroundColor = .systemGroupedBackground

        infoLabel.numberOfLines = 0
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabel
        infoLabel.text = """
        启动后，在 CarMovie 的「添加 URL」里粘贴下面的链接即可播放，不用导入。

        注意：播放时本 App 会进入后台，服务可能被挂起。
        视频不大时 CarMovie 能先缓冲完，就能继续播。
        """

        var config = UIButton.Configuration.filled()
        config.title = "启动本地服务"
        config.cornerStyle = .medium
        toggleButton.configuration = config
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)

        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        let header = UIStackView(arrangedSubviews: [infoLabel, toggleButton])
        header.axis = .vertical
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        table.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(table)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            table.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        let dir = CompensateExporter.documentsDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        files = urls.filter { $0.pathExtension.lowercased() == "mp4" }
        table.reloadData()
    }

    private func toggle() {
        if LocalFileServer.shared.isRunning {
            LocalFileServer.shared.stop()
            baseURL = "未启动"
            updateButton()
            table.reloadData()
            return
        }

        LocalFileServer.shared.start { [weak self] port in
            guard let self else { return }
            self.baseURL = port == 0 ? "启动失败" : "http://127.0.0.1:\(port)"
            self.updateButton()
            self.table.reloadData()
        }
    }

    private func updateButton() {
        var config = toggleButton.configuration
        config?.title = LocalFileServer.shared.isRunning ? "停止本地服务" : "启动本地服务"
        toggleButton.configuration = config
    }

    // MARK: 表格

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "点击复制链接 · 当前 \(baseURL)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let file = files[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = file.lastPathComponent
        if let link = LocalFileServer.shared.url(for: file) {
            content.secondaryText = link
            content.secondaryTextProperties.color = .systemBlue
        } else {
            content.secondaryText = "先启动服务"
            content.secondaryTextProperties.color = .tertiaryLabel
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let link = LocalFileServer.shared.url(for: files[indexPath.row]) else {
            return
        }
        UIPasteboard.general.string = link
        let alert = UIAlertController(title: "已复制", message: link, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
