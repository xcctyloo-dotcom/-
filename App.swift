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
        addCard("补偿版导出", "把音画偏移焊进文件，导出可直接播的 MP4") { [weak self] in
            self?.navigationController?.pushViewController(CompensateViewController(), animated: true)
        }
        addCard("已导出文件", "查看、分享、删除导出的视频") { [weak self] in
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
        get { UserDefaults.standard.double(forKey: "syncOffsetMs") }
        set { UserDefaults.standard.set(newValue, forKey: "syncOffsetMs") }
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

    private var source: URL?
    private var sourceSize: Int64 = 0
    private var offsetMs: Double = 120
    private var exporting = false
    private var startedAt: Date?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var actionButton: UIButton?
    private var lastExport: URL?

    private lazy var shareButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "分享这份文件"
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.presentShare() }, for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "补偿版导出"
        view.backgroundColor = .systemGroupedBackground
        if let saved = UserDefaults.standard.object(forKey: "exportOffsetMs") as? Double {
            offsetMs = saved
        }
        buildUI()
    }

    private func buildUI() {
        let help = UILabel()
        help.numberOfLines = 0
        help.font = .systemFont(ofSize: 13)
        help.textColor = .secondaryLabel
        help.text = """
        判断方向：
        · 先听到声、后看到动作 → 声音偏早，用正值（音频后移）
        · 先看到动作、后听到声 → 声音偏晚，用负值（画面后移）

        导出后用 CarMovie 打开那份新文件即可。
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

        let exportButton = makeButton("导出补偿版", #selector(runExport))
        actionButton = exportButton

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 20, right: 20)

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

        shareButton.isHidden = true

        [help, valueLabel, slider, presetRow,
         makeButton("选择视频", #selector(pickVideo)),
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
        let b = UIButton(configuration: config)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func setActionTitle(_ title: String) {
        actionButton?.configuration?.title = title
        actionButton?.setTitle(title, for: .normal)
    }

    private func refresh() {
        let direction = offsetMs > 0 ? "音频后移" : (offsetMs < 0 ? "画面后移" : "不偏移")
        valueLabel.text = String(format: "%+.0f ms · %@", offsetMs, direction)
    }

    @objc private func sliderChanged() {
        offsetMs = Double(slider.value).rounded()
        refresh()
        UserDefaults.standard.set(offsetMs, forKey: "exportOffsetMs")
    }

    @objc private func pickVideo() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func runExport() {
        if exporting {
            CompensateExporter.cancel()
            return
        }
        guard let source else {
            statusLabel.text = "先选一个视频"
            return
        }
        guard abs(offsetMs) >= 1 else {
            statusLabel.text = "偏移是 0，不用导出"
            return
        }

        let needed = sourceSize == 0 ? 0 : Int64(Double(sourceSize) * 1.2)
        let free = CompensateExporter.freeSpace()
        if free > 0 && free < needed {
            statusLabel.text = "空间不足：需要约 \(Format.bytes(needed))，可用 \(Format.bytes(free))"
            return
        }

        UserDefaults.standard.set(offsetMs, forKey: "exportOffsetMs")

        if batteryTooLow() {
            let alert = UIAlertController(title: "电量低于 20%",
                                          message: "导出比较耗电，建议先接电源。现在继续吗？",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "先不导", style: .cancel))
            alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self] _ in
                self?.startExport(source: source)
            })
            present(alert, animated: true)
            return
        }

        startExport(source: source)
    }

    private func startExport(source: URL) {
        exporting = true
        startedAt = Date()
        shareButton.isHidden = true
        progressBar.isHidden = false
        progressBar.progress = 0
        setActionTitle("取消")
        statusLabel.text = "准备中…"

        UIApplication.shared.isIdleTimerDisabled = true
        bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }

        CompensateExporter.export(source: source, offsetMs: offsetMs, progress: { [weak self] p in
            self?.updateProgress(p)
        }, completion: { [weak self] result in
            guard let self else { return }
            self.exporting = false
            self.setActionTitle("导出补偿版")
            self.progressBar.isHidden = true
            UIApplication.shared.isIdleTimerDisabled = false
            self.endBackground()

            switch result {
            case .success(let url):
                self.lastExport = url
                self.shareButton.isHidden = false
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                self.statusLabel.text = "完成 · \(Format.bytes(size))\n\(url.lastPathComponent)\n位置：文件 App → CarPlayCast"
            case .failure(let error):
                self.statusLabel.text = error.localizedDescription
            }
        })
    }

    private func makePresetButton(_ title: String, _ value: Double) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.addAction(UIAction { [weak self] _ in self?.applyPreset(value) }, for: .touchUpInside)
        return button
    }

    private func applyPreset(_ value: Double) {
        offsetMs = value
        slider.value = Float(value)
        refresh()
        UserDefaults.standard.set(value, forKey: "exportOffsetMs")
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

    private func updateProgress(_ p: Double) {
        let value = min(max(p, 0), 1)
        progressBar.setProgress(Float(value), animated: true)

        var text = "\(Int(value * 100))%"
        if value > 0.03, let startedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            let total = elapsed / value
            text += " · 预计还需 " + Format.duration(max(0, total - elapsed))
        } else {
            text += " · 估算中…"
        }
        statusLabel.text = text
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
        guard let url = urls.first else { return }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("source.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)")
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.copyItem(at: url, to: dst)
        source = dst

        let size = Int64((try? dst.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        sourceSize = size
        statusLabel.text = "已选择：\(url.lastPathComponent) · \(Format.bytes(size))"
    }
}

// MARK: - 已导出文件

final class ExportedFilesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var files: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "已导出"
        view.backgroundColor = .systemGroupedBackground

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
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
                                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        table.reloadData()
    }

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
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = files[indexPath.row]
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = tableView
        share.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        present(share, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { return done(false) }
            try? FileManager.default.removeItem(at: self.files[indexPath.row])
            self.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        table.setEditing(editing, animated: animated)
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
