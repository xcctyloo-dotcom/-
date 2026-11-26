import AVFoundation
import CarPlay
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
         makeButton("选择视频（可多选）", #selector(pickVideo)),
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

        if let lastExport {
            shareButton.isHidden = false
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
        guard let lastExport else { return }
        let controller = UIActivityViewController(activityItems: [lastExport], applicationActivities: nil)
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

        sources = urls
        sourceSizes = urls.map { url in
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        lastExport = nil
        shareButton.isHidden = true

        let total = sourceSizes.reduce(0, +)
        if urls.count > 1 {
            statusLabel.text = "已选 \(urls.count) 个 · 共 \(Format.bytes(total))"
        } else {
            statusLabel.text = "已选：\(urls[0].lastPathComponent) · \(Format.bytes(total))"
        }
        refresh()
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

    /// 返回录音里第一次超过阈值的时间点（秒）
    static func firstOnset(fileURL: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        guard (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }

        let count = Int(buffer.frameLength)
        var run = 0
        for i in 0..<count {
            if abs(channel[i]) > 0.06 {
                run += 1
                if run >= 3 {
                    return Double(i - 2) / format.sampleRate
                }
            } else {
                run = 0
            }
        }
        return nil
    }
}

// MARK: - 自动测量

final class Calibrator {

    static let shared = Calibrator()

    enum MeasureError: LocalizedError {
        case noPermission
        case busy
        case noSignal
        case outOfRange(Double)

        var errorDescription: String? {
            switch self {
            case .noPermission: return "没有麦克风权限，去设置里允许"
            case .busy: return "录音启动失败，可能被别的 App 占用"
            case .noSignal: return "没听到咔哒声，检查车机音量或换个安静环境"
            case .outOfRange(let ms): return String(format: "测到 %.0f ms，明显不对，建议手动调", ms)
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var startedAt: Date?
    private var clickAt: Date?
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
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            finish(.failure(error))
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cal.m4a")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.clickAt = Date()
            if let clickURL = ClickFile.url() {
                self.player = try? AVAudioPlayer(contentsOf: clickURL)
                self.player?.play()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.stopAndAnalyze()
            }
        }
    }

    private func stopAndAnalyze() {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil

        guard let url,
              let clickAt,
              let startedAt,
              let onset = AudioAnalysis.firstOnset(fileURL: url) else {
            finish(.failure(MeasureError.noSignal))
            return
        }

        let clickOffset = clickAt.timeIntervalSince(startedAt)
        // 麦克风采集和播放启动有约 10ms 固定开销，扣掉
        let ms = ((onset - clickOffset) - 0.01) * 1000

        if ms < 15 || ms > 800 {
            finish(.failure(MeasureError.outOfRange(ms)))
        } else {
            finish(.success(ms.rounded()))
        }
    }

    private func finish(_ result: Result<Double, Error>) {
        player?.stop()
        player = nil
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

        statusLabel.text = "测量中：保持安静，车里会响一声"
        Calibrator.shared.measure { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let ms):
                self.offsetMs = ms
                self.slider.value = Float(ms)
                self.refresh()
                OffsetStore.current = ms
                Log.write("calibrated \(Int(ms))ms on \(OffsetStore.routeName)")
                self.statusLabel.text = String(format: "测量完成：%.0f ms · 已保存到「%@」", ms, OffsetStore.routeName)
            case .failure(let error):
                Log.write("calibration failed: \(error.localizedDescription)")
                self.statusLabel.text = "测量失败：\(error.localizedDescription)"
            }
        }
    }
}
