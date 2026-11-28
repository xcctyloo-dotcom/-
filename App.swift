import AVFoundation
import CarPlay
import PhotosUI
import Network
import MediaPlayer
import UIKit
import UniformTypeIdentifiers

// MARK: - 版本

enum BuildInfo {
    /// 每次发新包改这里，主菜单底部和日志里都能看到
    static let version = "6.1"
    static let note = "safety"
    static var display: String { "v\(version) · \(note)" }
}

// MARK: - 视觉

enum Theme {
    static let accent = UIColor.systemTeal
    static let card = UIColor.secondarySystemGroupedBackground
    static let corner: CGFloat = 16
    static let padding: CGFloat = 16
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

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
            if name.hasPrefix("source.") || name.hasPrefix("相机_") || name == "audio.m4a" || name == "cal.wav" || name == "cal.m4a" {
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
        Log.write("launch \(BuildInfo.display) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) \(UIDevice.current.model)")
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
        addCard("车载播放", "车机主屏出现「车载播放」列表，播放测试音", "car.fill") { [weak self] in
            self?.showAlert("插上 CarPlay 后，车机主屏会出现「车载播放」。\n\n如果没出现，是 CarPlay 权限没被系统认，和代码无关。")
        }

        addSection("手机播放 · 声音走车机")
        addCard("视频同步", "画面在手机，声音走车机，可调音画偏移", "rectangle.on.rectangle") { [weak self] in
            self?.navigationController?.pushViewController(VideoSyncViewController(), animated: true)
        }

        addSection("给车机播放器用（CarMovie 等）")
        addCard("补偿版导出", "可批量：同一偏移排队导出多个视频", "wand.and.stars") { [weak self] in
            self?.navigationController?.pushViewController(CompensateViewController(), animated: true)
        }
        addCard("本地播放（免导入）", "起本地链接，CarMovie 按 URL 直接播", "antenna.radiowaves.left.and.right") { [weak self] in
            self?.navigationController?.pushViewController(LocalServerViewController(), animated: true)
        }
        addCard("已导出文件", "批量选择、分享、删除导出的视频", "folder.fill") { [weak self] in
            self?.navigationController?.pushViewController(ExportedFilesViewController(), animated: true)
        }

        addSection("说明")
        addCard("这个 App 能做什么", "三种模式的区别与各自的上限", "questionmark.circle") { [weak self] in
            self?.navigationController?.pushViewController(AboutViewController(), animated: true)
        }

        let footer = UILabel()
        footer.numberOfLines = 0
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .tertiaryLabel
        footer.text = "CarPlay 没有公开的视频通道。车机上放视频只能靠私有接口（CarMovie 那种），本 App 不做。\n\(BuildInfo.display)"
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

    private func addCard(_ title: String,
                         _ subtitle: String,
                         _ symbol: String,
                         _ action: @escaping () -> Void) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.subtitle = subtitle
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        config.image = UIImage(systemName: symbol)?
            .withConfiguration(symbolConfig)
            .withTintColor(Theme.accent, renderingMode: .alwaysOriginal)
        config.imagePadding = 12
        config.imagePlacement = .leading
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.card
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        config.titleAlignment = .leading

        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.tintColor = Theme.accent
        button.layer.cornerRadius = Theme.corner
        button.addAction(UIAction { _ in
            Haptics.tap()
            action()
        }, for: .touchUpInside)
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
    private let emptyStack = UIStackView()

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
        buildEmptyState()
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

    private func buildEmptyState() {
        let icon = UIImageView(image: UIImage(systemName: "play.rectangle.on.rectangle"))
        icon.tintColor = Theme.accent
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = UILabel()
        title.text = "还没有选视频"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white

        let hint = UILabel()
        hint.text = "选一个视频，画面在手机、声音走车机\n再拖滑杆把音画对齐"
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .systemGray2

        emptyStack.axis = .vertical
        emptyStack.alignment = .center
        emptyStack.spacing = 12
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        [icon, title, hint].forEach { emptyStack.addArrangedSubview($0) }
        view.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -100),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func buildPanel() {
        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        offsetLabel.textColor = Theme.accent

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
            makeButton("从相册", #selector(pickFromPhotos)),
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
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

        let b = UIButton(configuration: config)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
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

    private func load(original url: URL, alreadyCopied: Bool = false) {
        let dst: URL
        if alreadyCopied {
            dst = url
        } else {
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("source.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)")
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
            dst = target
        }

        let asset = AVURLAsset(url: dst)
        let player = AVPlayer(url: dst)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        videoPlayer = player
        playerLayer.player = player
        emptyStack.isHidden = true

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

extension VideoSyncViewController: PHPickerViewControllerDelegate {

    @objc fileprivate func pickFromPhotos() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }

        statusLabel.text = "正在从相册取视频…"
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            guard let url else {
                DispatchQueue.main.async {
                    self?.statusLabel.text = "取视频失败：可能还在 iCloud，先在相册里播放一遍"
                }
                return
            }

            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("syncs_src.\(ext)")
            try? FileManager.default.removeItem(at: dst)
            let copied = (try? FileManager.default.copyItem(at: url, to: dst)) != nil

            DispatchQueue.main.async {
                guard let self else { return }
                if copied {
                    self.load(original: dst, alreadyCopied: true)
                } else {
                    self.statusLabel.text = "拷贝失败：空间可能不足"
                }
            }
        }
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

    static var cancelled = false

    static func cancel() {
        cancelled = true
        Remuxer.cancel()
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
        return documentsDir().appendingPathComponent("\(base)_\(sign)\(Int(abs(offsetMs)))ms.mp4")
    }

    /// 先试免转码重封装，失败再退回转码
    static func export(source: URL,
                       offsetMs: Double,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        cancelled = false
        var settled = false
        let done: (Result<URL, Error>) -> Void = { result in
            guard !settled else { return }
            settled = true
            completion(result)
        }

        let out = outputURL(source: source, offsetMs: offsetMs)
        Remuxer.shift(source: source, offsetMs: offsetMs, to: out, progress: progress) { result in
            switch result {
            case .success:
                // 校验：能读、时长大于 0，才算成功
                let check = AVURLAsset(url: out)
                if CMTimeGetSeconds(check.duration) > 0.2 {
                    done(.success(out))
                } else {
                    Log.write("remux invalid output, fallback")
                    exportByComposition(source: source, offsetMs: offsetMs,
                                        progress: progress, completion: done)
                }
            case .failure(let error):
                if cancelled {
                    done(.failure(CompensateError.exportFailed("已取消")))
                    return
                }
                Log.write("remux fallback: \(error.localizedDescription)")
                exportByComposition(source: source, offsetMs: offsetMs,
                                    progress: progress, completion: done)
            }
        }
    }

    /// offsetMs > 0：音频后移；offsetMs < 0：画面后移
    private static func exportByComposition(source: URL,
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
    private let directionLabel = UILabel()
    private let statusLabel = UILabel()
    private let carLabel = UILabel()
    private let learnLabel = UILabel()
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
    private var fileTimeout: DispatchWorkItem?
    private var fileStartedAt: Date?
    private var importFailures = 0
    private var importTimeout: DispatchWorkItem?
    private var importAborted = false
    private var pendingQueue: [([URL], Double)] = []
    private var leftoverPlan: [PlanItem] = []
    private var importFailureNames: [String] = []
    private var presetButtons: [(button: UIButton, value: Double)] = []
    private var measureButton: UIButton?
    private var photosButton: UIButton?
    private var filesButton: UIButton?
    private var overwriteCount = 0

    private lazy var shareButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "分享最后一份"
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.presentShare() }, for: .touchUpInside)
        return button
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshLearnLabel()
        refreshCarLabel()
    }

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

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 40, weight: .bold)
        valueLabel.textColor = Theme.accent
        valueLabel.textAlignment = .center

        directionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        directionLabel.textColor = .secondaryLabel
        directionLabel.textAlignment = .center

        slider.minimumValue = -400
        slider.maximumValue = 400
        slider.value = Float(offsetMs)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderFinished), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        progressBar.progress = 0
        progressBar.isHidden = true

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        carLabel.font = .systemFont(ofSize: 12, weight: .medium)
        carLabel.textColor = .secondaryLabel
        carLabel.numberOfLines = 0

        learnLabel.font = .systemFont(ofSize: 11)
        learnLabel.textColor = .tertiaryLabel
        learnLabel.numberOfLines = 0
        learnLabel.isUserInteractionEnabled = true
        learnLabel.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self, action: #selector(clearSamplesTapped)))

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

        let exportButton = makeButton("导出补偿版", #selector(runExport), primary: true)
        actionButton = exportButton
        shareButton.isHidden = true

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 20, right: 20)

        let measureButton = makeButton("自动测量延迟", #selector(measureTapped))
        let photosButton = makeButton("从相册选择（可多选）", #selector(pickFromPhotos))
        let filesButton = makeButton("从文件选择（可多选）", #selector(pickVideo))
        self.measureButton = measureButton
        self.photosButton = photosButton
        self.filesButton = filesButton

        [help, valueLabel, directionLabel, slider, presetRow,
         measureButton, photosButton, filesButton,
         exportButton, progressBar, statusLabel, shareButton, carLabel, learnLabel]
            .forEach { stack.addArrangedSubview($0) }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetOffset))
        doubleTap.numberOfTapsRequired = 2
        slider.addGestureRecognizer(doubleTap)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        refresh()
    }

    /// primary = true 用实心，其余用浅底，形成主次
    private func makeButton(_ title: String, _ action: Selector, primary: Bool = false) -> UIButton {
        var config = primary ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        config.title = title
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = primary ? .white : Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func presentPlan(_ items: [PlanItem], attempt: Int = 0) {
        guard !items.isEmpty else { return }

        // 相册/文件选择器刚 dismiss 时直接 present 会失败，等一下再试
        if presentedViewController != nil {
            guard attempt < 5 else {
                Log.write("presentPlan aborted: something still presented")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.presentPlan(items, attempt: attempt + 1)
            }
            return
        }

        let plan = BatchPlanViewController(items: items)
        plan.onExport = { [weak self] groups, remaining in
            self?.startBatches(groups, remaining: remaining)
        }
        plan.onCancel = { [weak self] in
            self?.statusLabel.text = "已取消分批，可以手动选片再导"
        }
        let nav = UINavigationController(rootViewController: plan)
        present(nav, animated: true)
    }

    private func startBatches(_ groups: [([URL], Double)], remaining: [PlanItem]) {
        pendingQueue = groups
        leftoverPlan = remaining
        Log.write("plan export \(groups.count) groups, left \(remaining.count)")
        runNextBatch()
    }

    private func runNextBatch() {
        guard !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()

        sources = next.0
        sourceSizes = next.0.map {
            Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        offsetMs = next.1
        slider.value = Float(next.1)
        refresh()

        let remaining = pendingQueue.count
        statusLabel.text = remaining > 0
            ? "本批 \(sources.count) 个 · 后面还有 \(remaining) 批"
            : "本批 \(sources.count) 个"

        // 面板可能还在关闭动画里，稍等再弹确认
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.confirmOverwrite { [weak self] in
                self?.startQueue()
            }
        }
    }

    private func makePresetButton(_ title: String, _ value: Double) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.applyPreset(value)
        }, for: .touchUpInside)
        presetButtons.append((button, value))
        return button
    }

    private func refreshCarLabel() {
        let name = OffsetStore.routeName
        if let stored = OffsetStore.routeStored {
            carLabel.text = String(format: "当前车机：%@ · 已存 %.0f ms", name, stored)
        } else {
            carLabel.text = "当前车机：\(name) · 还没为它存过偏移"
        }
    }

    @objc private func clearSamplesTapped() {
        guard OffsetStore.sampleCount > 0 else { return }
        let alert = UIAlertController(title: "清除学习样本？",
                                      message: "会删掉已记录的 \(OffsetStore.sampleCount) 组「码率 → 偏移」，规律重新开始积累。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            OffsetStore.clearSamples()
            self?.refreshLearnLabel()
        })
        present(alert, animated: true)
    }

    private func refreshLearnLabel() {
        if let fit = OffsetStore.fit() {
            learnLabel.text = String(format: "已学 %d 组样本：码率每 +1 Mbps，补偿多 %+.1f ms", fit.count, fit.slope)
        } else if OffsetStore.sampleCount > 0 {
            learnLabel.text = "已记录 \(OffsetStore.sampleCount) 组样本（≥3 组且码率跨度 ≥2 Mbps 才会形成规律）"
        } else {
            learnLabel.text = "还没有样本：导出一两次后开始学习"
        }
    }

    private func setActionTitle(_ title: String) {
        actionButton?.configuration?.title = title
        actionButton?.setTitle(title, for: .normal)
    }

    private func refresh() {
        let direction = offsetMs > 0 ? "音频后移" : (offsetMs < 0 ? "画面后移" : "不偏移")
        valueLabel.text = String(format: "%+.0f ms", offsetMs)
        valueLabel.accessibilityLabel = String(format: "%.0f 毫秒，%@", offsetMs, direction)
        directionLabel.text = direction

        for (button, value) in presetButtons {
            var config = button.configuration
            let selected = abs(value - offsetMs) < 0.5
            config?.baseBackgroundColor = selected ? Theme.accent : UIColor.tertiarySystemFill
            config?.baseForegroundColor = selected ? .white : .label
            button.configuration = config
        }

        if !exporting {
            setActionTitle(sources.count > 1 ? "导出补偿版（\(sources.count) 个）" : "导出补偿版")
        }
    }

    @objc private func sliderChanged() {
        offsetMs = Double(slider.value).rounded()
        refresh()
    }

    @objc private func resetOffset() {
        offsetMs = 0
        slider.value = 0
        refresh()
        OffsetStore.current = 0
        Haptics.tap()
    }

    @objc private func sliderFinished() {
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
        guard !exporting else {
            statusLabel.text = "导出中，先等这一批跑完"
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    // MARK: 导出

    @objc private func runExport() {
        if exporting {
            cancelling = true
            pendingQueue.removeAll()
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
                self?.confirmOverwrite { [weak self] in self?.startQueue() }
            })
            present(alert, animated: true)
            return
        }

        confirmOverwrite { [weak self] in self?.startQueue() }
    }

    private func confirmOverwrite(_ completion: @escaping () -> Void) {
        let existing = sources.filter {
            FileManager.default.fileExists(atPath: CompensateExporter.outputURL(source: $0, offsetMs: offsetMs).path)
        }
        guard !existing.isEmpty else {
            overwriteCount = 0
            completion()
            return
        }

        let names = existing.prefix(6).map {
            CompensateExporter.outputURL(source: $0, offsetMs: offsetMs).lastPathComponent
        }
        var message = names.joined(separator: "\n")
        if existing.count > names.count {
            message += "\n……等 \(existing.count) 个"
        }

        let alert = UIAlertController(title: "会覆盖 \(existing.count) 个已有文件",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.pendingQueue.removeAll()
            self?.statusLabel.text = "已取消，未导出"
        })
        alert.addAction(UIAlertAction(title: "覆盖", style: .default) { [weak self] _ in
            self?.overwriteCount = existing.count
            completion()
        })
        present(alert, animated: true)
    }

    private func startQueue() {
        exporting = true
        cancelling = false
        completed = 0
        failed = 0
        currentIndex = 0
        lastExport = nil
        outputs = []
        overwriteCount = 0
        startedAt = Date()
        shareButton.isHidden = true
        progressBar.isHidden = false
        progressBar.progress = 0
        setActionTitle("取消")
        setEntryButtons(enabled: false)
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
        let startedAt = Date()
        fileStartedAt = Date()

        // 5 分钟内没有任何新进展才放弃，避免长片被误杀
        armFileWatchdog(for: url)

        CompensateExporter.export(source: url, offsetMs: offsetMs, progress: { [weak self] p in
            guard let self else { return }
            self.armFileWatchdog(for: url)
            let overall = (Double(self.completed + self.failed) + p) / Double(max(1, self.sources.count))
            self.updateProgress(overall: overall, current: p)
        }, completion: { [weak self] result in
            guard let self else { return }
            self.fileTimeout?.cancel()

            if self.cancelling {
                self.finishQueue()
                return
            }

            switch result {
            case .success(let output):
                self.completed += 1
                self.lastExport = output
                self.outputs.append(output)
                let seconds = Int(Date().timeIntervalSince(startedAt))
                let mbps = VideoInfo.load(url).map { String(format: "%.1fMbps", $0.megabitsPerSecond) } ?? "?"
                Log.write("export ok \(url.lastPathComponent) \(mbps) \(seconds)s")
            case .failure(let error):
                self.failed += 1
                Log.write("export failed \(url.lastPathComponent): \(error.localizedDescription)")
            }

            // 导完就删临时拷贝，避免 12 部 4K 同时占满空间
            self.cleanupSource(url)

            self.currentIndex += 1
            self.runNext()
        })
    }

    private func setEntryButtons(enabled: Bool) {
        measureButton?.isEnabled = enabled
        photosButton?.isEnabled = enabled
        filesButton?.isEnabled = enabled
        slider.isEnabled = enabled
    }

    private func armFileWatchdog(for url: URL) {
        fileTimeout?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.exporting else { return }
            Log.write("export stalled \(url.lastPathComponent)")
            CompensateExporter.cancel()
        }
        fileTimeout = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: watchdog)
    }

    /// 只删临时目录里的拷贝，别碰用户原文件
    private func cleanupSource(_ url: URL) {
        let tmp = FileManager.default.temporaryDirectory.path
        guard url.path.hasPrefix(tmp) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func finishQueue() {
        exporting = false
        let wasCancelled = cancelling
        cancelling = false

        if !wasCancelled {
            if completed > 0 && failed == 0 {
                Haptics.success()
            } else if completed == 0 {
                Haptics.failure()
            } else {
                Haptics.tap()
            }
        }
        setActionTitle("导出补偿版")
        setEntryButtons(enabled: true)
        progressBar.isHidden = true
        UIApplication.shared.isIdleTimerDisabled = false
        endBackground()

        if sources.count == 1 {
            OffsetStore.saveOffset(offsetMs, forSize: sourceSizes.first ?? 0)
            refreshLearnLabel()
            if let first = sources.first, let info = VideoInfo.load(first) {
                OffsetStore.recordSample(size: sourceSizes.first ?? 0,
                                         mbps: info.megabitsPerSecond,
                                         offset: offsetMs)
            }
        }

        Log.write("queue done ok=\(completed) fail=\(failed) overwrite=\(overwriteCount) offset=\(Int(offsetMs))")

        if !pendingQueue.isEmpty {
            Log.write("continue next batch, remaining \(pendingQueue.count)")
            runNextBatch()
            return
        }

        // 这一轮导完，把没导的重新摆到面板上，方便继续调偏移
        if !leftoverPlan.isEmpty {
            let rest = leftoverPlan
            leftoverPlan = []
            Log.write("reopen plan with \(rest.count) left")
            presentPlan(rest)
            return
        }

        if let lastExport {
            shareButton.isHidden = false
            var config = shareButton.configuration
            config?.title = outputs.count > 1 ? "一次性交给 CarMovie（\(outputs.count) 个）" : "分享这份文件"
            shareButton.configuration = config
            let size = Int64((try? lastExport.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if sources.count > 1 {
                let extra = overwriteCount > 0 ? "，覆盖 \(overwriteCount) 个旧文件" : ""
                statusLabel.text = "完成 \(completed) 个，失败 \(failed) 个\(extra)\(wasCancelled ? "（已取消）" : "")\n最后一份 \(Format.bytes(size)) · 文件 App → CarPlayCast"
            } else {
                let extra = overwriteCount > 0 ? "（覆盖了旧文件）" : ""
                statusLabel.text = "完成\(extra) · \(Format.bytes(size))\n\(lastExport.lastPathComponent)\n位置：文件 App → CarPlayCast"
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
        } else if let fileStartedAt {
            // 准备阶段进度是 0，显示“已经跑了多久”，至少知道它活着
            text += " · 已用 " + Format.duration(Date().timeIntervalSince(fileStartedAt))
        } else {
            text += " · 准备中"
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
        importFailures = 0
        importAborted = false
        importFailureNames = []
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
    private var sortBySize = false
    private var sortByName = false
    private var sortButton: UIBarButtonItem?
    private var selectItem: UIBarButtonItem?
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "已导出"
        view.backgroundColor = .systemGroupedBackground
        let selectItem = UIBarButtonItem(title: "选择", style: .plain,
                                         target: self,
                                         action: #selector(toggleSelecting))
        self.selectItem = selectItem

        let sort = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"),
                                     menu: makeSortMenu())
        sortButton = sort
        // 放右侧，左侧留给系统返回键
        navigationItem.rightBarButtonItems = [selectItem, sort]

        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelectionDuringEditing = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        emptyLabel.text = "还没有导出的文件\n去「补偿版导出」选几个视频"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        table.backgroundView = emptyLabel

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
        selectItem?.title = selecting ? "完成" : "选择"
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
            urls.forEach {
                TitleStore.set("", for: $0)
                try? FileManager.default.removeItem(at: $0)
            }
            self.selecting = false
            self.table.setEditing(false, animated: true)
            self.selectItem?.title = "选择"
            self.reload()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = bar
        present(alert, animated: true)
    }

    // MARK: 数据

    private func makeSortMenu() -> UIMenu {
        let time = UIAction(title: "按时间", state: (!sortBySize && !sortByName) ? .on : .off) { [weak self] _ in
            self?.sortBySize = false
            self?.sortByName = false
            self?.updateSortMenu()
            self?.reload()
        }
        let size = UIAction(title: "按大小", state: sortBySize ? .on : .off) { [weak self] _ in
            self?.sortBySize = true
            self?.sortByName = false
            self?.updateSortMenu()
            self?.reload()
        }
        let name = UIAction(title: "按名称", state: sortByName ? .on : .off) { [weak self] _ in
            self?.sortByName = true
            self?.sortBySize = false
            self?.updateSortMenu()
            self?.reload()
        }
        return UIMenu(title: "排序", children: [time, size, name])
    }

    private func updateSortMenu() {
        sortButton?.menu = makeSortMenu()
    }

    private func reload() {
        let dir = CompensateExporter.documentsDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { a, b in
                if sortByName {
                    let na = TitleStore.title(for: a) ?? a.lastPathComponent
                    let nb = TitleStore.title(for: b) ?? b.lastPathComponent
                    return na.localizedStandardCompare(nb) == .orderedAscending
                }
                if sortBySize {
                    let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return sa > sb
                }
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        table.reloadData()
        updateBar()
        emptyLabel.isHidden = !files.isEmpty

        let total = files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        navigationItem.prompt = files.isEmpty ? nil : "\(files.count) 个 · \(Format.bytes(total))"
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let url = files[indexPath.row]
        var content = cell.defaultContentConfiguration()
        let custom = TitleStore.title(for: url)
        content.text = custom ?? url.lastPathComponent
        content.textProperties.numberOfLines = 1
        content.textProperties.lineBreakMode = .byTruncatingMiddle
        content.image = UIImage(systemName: "film")
        content.imageProperties.tintColor = Theme.accent
        content.imageProperties.maximumSize = CGSize(width: 22, height: 22)
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        if custom != nil {
            content.secondaryText = url.lastPathComponent + " · " + Format.bytes(size)
            content.secondaryTextProperties.numberOfLines = 1
        } else if let info = VideoInfoCache.cached(url) {
            content.secondaryText = info.shortSummary + " · " + Format.bytes(size)
            content.secondaryTextProperties.numberOfLines = 1
        } else {
            content.secondaryText = Format.bytes(size)
            let row = indexPath.row
            let path = url
            VideoInfoCache.loadAsync(for: path) { [weak self] info in
                guard let self, info != nil else { return }
                guard row < self.files.count, self.files[row] == path else { return }
                let target = IndexPath(row: row, section: 0)
                guard let visible = self.table.indexPathsForVisibleRows,
                      visible.contains(target) else { return }
                self.table.reloadRows(at: [target], with: .none)
            }
        }
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
        let rename = UIContextualAction(style: .normal, title: "改名") { [weak self] _, _, done in
            guard let self else { return done(false) }
            let url = self.files[indexPath.row]
            let alert = UIAlertController(title: "设置显示标题",
                                          message: url.lastPathComponent,
                                          preferredStyle: .alert)
            alert.addTextField { field in
                field.text = TitleStore.title(for: url)
                field.placeholder = "例如：星晴"
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
                TitleStore.set(alert.textFields?.first?.text ?? "", for: url)
                self.reload()
                done(true)
            })
            self.present(alert, animated: true)
        }
        rename.backgroundColor = Theme.accent

        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { return done(false) }
            let url = self.files[indexPath.row]

            let alert = UIAlertController(title: "删除这个文件？",
                                          message: "\(url.lastPathComponent)\n删了就找不回来了。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
                TitleStore.set("", for: url)
                try? FileManager.default.removeItem(at: url)
                self.reload()
                done(true)
            })
            self.present(alert, animated: true)
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
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

        本地播放

        导出后在本机起一个 HTTP 服务，CarMovie 按 URL 播放，不用导入。
        端口固定 8080，链接可长期复用；播放时手机停在本 App，服务才不会被挂起。

        学习与分档

        每次导出记录「码率 → 偏移」，累积 3 部以上且码率跨度够，就会拟合出规律，
        选新片时自动给出参考值。码率分四档：低 <4、中 4-10、高 10-20、超高 >20 Mbps。
        """
        // 短行当标题，其余当正文，避免整页同字号
        if let raw = text.text {
            let result = NSMutableAttributedString()
            let bodyColor = UIColor.label
            let headColor = Theme.accent
            for line in raw.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isHeading = !trimmed.isEmpty
                    && trimmed.count <= 8
                    && !trimmed.hasPrefix("·")
                    && trimmed.first?.isNumber != true

                let attributes: [NSAttributedString.Key: Any] = isHeading
                    ? [.font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                       .foregroundColor: headColor]
                    : [.font: UIFont.systemFont(ofSize: 15),
                       .foregroundColor: bodyColor]

                result.append(NSAttributedString(string: line + "\n", attributes: attributes))
            }
            text.textStorage.setAttributedString(result)
        }

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
        if let value = map["\(size)"] as? Double { return value }   // 旧格式兼容
        if let dict = map["\(size)"] as? [String: Any],
           let value = dict["o"] as? Double {
            return value
        }
        return nil
    }

    static func saveOffset(_ value: Double, forSize size: Int64) {
        guard size > 0 else { return }
        var map = UserDefaults.standard.dictionary(forKey: fileKey) ?? [:]
        map["\(size)"] = ["o": value, "t": Date().timeIntervalSince1970]

        // 只留最近 300 部，避免 UserDefaults 越积越大
        if map.count > 300 {
            let sorted = map.sorted {
                let l = (($0.value as? [String: Any])?["t"] as? Double) ?? 0
                let r = (($1.value as? [String: Any])?["t"] as? Double) ?? 0
                return l < r
            }
            for (key, _) in sorted.prefix(map.count - 300) {
                map.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(map, forKey: fileKey)
    }

    private static let samplesKey = "offsetSamples"

    private static func rawMap() -> [String: Any] {
        UserDefaults.standard.dictionary(forKey: samplesKey) ?? [:]
    }

    /// (码率 Mbps, 偏移 ms) 样本列表；同一部片子只保留最后一次
    private static func samples() -> [(Double, Double)] {
        rawMap().values.compactMap { value in
            guard let dict = value as? [String: Any],
                  let mbps = dict["m"] as? Double,
                  let offset = dict["o"] as? Double else { return nil }
            return (mbps, offset)
        }
    }

    /// 用文件体积做指纹：反复试调同一部片子，只留最后一次
    static func recordSample(size: Int64, mbps: Double, offset: Double) {
        guard mbps > 0, size > 0 else { return }
        var map = rawMap()
        map["\(size)"] = [
            "m": mbps,
            "o": offset,
            "t": Date().timeIntervalSince1970
        ]

        if map.count > 120 {
            let sorted = map.sorted {
                let l = (($0.value as? [String: Any])?["t"] as? Double) ?? 0
                let r = (($1.value as? [String: Any])?["t"] as? Double) ?? 0
                return l < r
            }
            for (key, _) in sorted.prefix(map.count - 120) {
                map.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(map, forKey: samplesKey)
    }

    struct Fit {
        let slope: Double
        let intercept: Double
        let count: Int
    }

    static var sampleCount: Int { rawMap().count }

    /// 最小二乘：偏移 ≈ slope × 码率 + intercept
    static func fit() -> Fit? {
        let points = samples()
        guard points.count >= 3 else { return nil }

        let xs = points.map { $0.0 }
        guard let minX = xs.min(), let maxX = xs.max(), maxX - minX >= 2 else { return nil }

        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = points.reduce(0) { $0 + $1.1 }
        let sumXY = points.reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = points.reduce(0) { $0 + $1.0 * $1.0 }

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 0.0001 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        return Fit(slope: slope, intercept: intercept, count: points.count)
    }

    static func predict(mbps: Double) -> Double? {
        guard mbps > 0, let fit = fit() else { return nil }
        let value = fit.slope * mbps + fit.intercept
        return min(-20, max(-400, value)).rounded()
    }

    /// 按码率相近的历史样本推测偏移
    static func suggestion(forMbps mbps: Double) -> Double? {
        guard mbps > 0 else { return nil }
        let tolerance = max(1.0, mbps * 0.4)
        let values = samples().compactMap { sample -> Double? in
            abs(sample.0 - mbps) <= tolerance ? sample.1 : nil
        }.sorted()

        if values.count >= 2 {
            return values[values.count / 2]
        }
        return predict(mbps: mbps)
    }

    /// 只查当前车机自己的记录，不做回退
    static var routeStored: Double? {
        let map = UserDefaults.standard.dictionary(forKey: mapKey) ?? [:]
        return map[routeName] as? Double
    }

    static func clearSamples() {
        UserDefaults.standard.removeObject(forKey: samplesKey)
    }

    static var summary: String {
        let map = UserDefaults.standard.dictionary(forKey: mapKey) ?? [:]
        guard !map.isEmpty else { return "还没有保存过任何车的偏移" }
        return map.map { "\($0.key)：\(Int(($0.value as? Double) ?? 0)) ms" }
            .sorted()
            .joined(separator: "\n")
    }
}

// MARK: - 显示标题

/// 只改列表里显示的名字，不动真实文件名，避免破坏本地播放链接
enum TitleStore {
    private static let key = "displayTitles"

    static func title(for url: URL) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        return map[url.lastPathComponent] as? String
    }

    static func set(_ title: String, for url: URL) {
        var map = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: url.lastPathComponent)
        } else {
            map[url.lastPathComponent] = trimmed
        }
        UserDefaults.standard.set(map, forKey: key)
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
        // 超过 300KB 清空，避免长期使用后日志无限膨胀
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 300_000 {
            try? FileManager.default.removeItem(at: url)
        }
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

        let free = CompensateExporter.freeSpace()
        if free > 0 && free < 2_000_000_000 {
            let alert = UIAlertController(title: "空间可能不够",
                                          message: "可用空间只有 \(Format.bytes(free))。从相册导入会先复制一份，大文件可能失败。建议先导出几部、清掉缓存再继续。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self] _ in
                self?.startPhotoImport(providers)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            present(alert, animated: true)
            return
        }

        startPhotoImport(providers)
        importProviders(providers, index: 0, collected: [])
    }

    private func startPhotoImport(_ providers: [NSItemProvider]) {
        statusLabel.text = "正在从相册导入 \(providers.count) 个…"
        importFailures = 0
        importAborted = false
        importFailureNames = []
        importProviders(providers, index: 0, collected: [])
    }

    private func importProviders(_ providers: [NSItemProvider], index: Int, collected: [URL]) {
        guard !importAborted else { return }

        guard index < providers.count else {
            applySelection(collected)
            return
        }

        // 剩不到 800MB 就不再往下拷，避免后面的全变成失败
        if CompensateExporter.freeSpace() < 800_000_000 {
            let skipped = providers.count - index
            importFailures += skipped
            for i in index..<providers.count {
                importFailureNames.append(providers[i].suggestedName ?? "第 \(i + 1) 个")
            }
            Log.write("import stopped: low disk, skipped \(skipped)")
            applySelection(collected)
            return
        }

        statusLabel.text = "正在从相册导入 \(index + 1)/\(providers.count)…"

        importTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.write("import timeout at index \(index)")
            self.importAborted = true
            self.importFailures += providers.count - index
            for i in index..<providers.count {
                self.importFailureNames.append(providers[i].suggestedName ?? "第 \(i + 1) 个")
            }
            self.applySelection(collected)
        }
        importTimeout = timeout
        // 单个文件最多等 3 分钟：还在 iCloud 上的片子会卡在这里
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)

        let provider = providers[index]
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            var copied: URL?
            if let url {
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let formatter = DateFormatter()
                formatter.dateFormat = "MMdd_HHmmss"
                let stamp = formatter.string(from: Date())
                // 两位编号：\(01, 02 … 11)，按字符串排序也不会乱
                let seq = String(format: "%02d", index + 1)
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("相机_\(stamp)_\(seq).\(ext)")
                try? FileManager.default.removeItem(at: dst)
                if (try? FileManager.default.copyItem(at: url, to: dst)) != nil {
                    copied = dst
                } else {
                    let name = provider.suggestedName ?? "第 \(index + 1) 个"
                    Log.write("import failed: \(name)")
                    DispatchQueue.main.async { self?.importFailureNames.append(name) }
                }
            }
            DispatchQueue.main.async {
                guard let self, !self.importAborted else { return }
                self.importTimeout?.cancel()
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
            let info = VideoInfo.load(first)
            var note = ""
            if let remembered = OffsetStore.storedOffset(forSize: sourceSizes.first ?? 0) {
                offsetMs = remembered
                slider.value = Float(remembered)
                note = String(format: " · 已载入上次的 %.0f ms", remembered)
            } else if let info, let suggested = OffsetStore.suggestion(forMbps: info.megabitsPerSecond) {
                offsetMs = suggested
                slider.value = Float(suggested)
                note = String(format: " · 按同码率推测 %.0f ms", suggested)
            }

            var lines = ["已选：\(first.lastPathComponent) · \(Format.bytes(total))\(note)"]
            if let info {
                lines.append("画面 \(info.summary)")
            }
            statusLabel.text = lines.joined(separator: "\n")

            // 单个也进分批面板：可以只导这一个，或先放着
            let title = info?.category.rawValue ?? "单个视频"
            presentPlan([PlanItem(url: first, category: title, offset: offsetMs)])
        } else if urls.count > 1 {
            var groups: [VideoInfo.Category: [URL]] = [:]
            var rates: [VideoInfo.Category: [Double]] = [:]
            for url in urls {
                if let info = VideoInfoCache.info(for: url) {
                    groups[info.category, default: []].append(url)
                    rates[info.category, default: []].append(info.megabitsPerSecond)
                }
            }

            var text = "已选 \(urls.count) 个 · 共 \(Format.bytes(total))"
            let order: [VideoInfo.Category] = [.low, .medium, .high, .ultra]
            var lines: [String] = []
            for category in order where groups[category] != nil {
                let list = groups[category] ?? []
                let average = (rates[category] ?? []).reduce(0, +) / Double(max(1, list.count))
                let suggested = OffsetStore.suggestion(forMbps: average) ?? offsetMs
                lines.append("\(category.rawValue) \(list.count) 个 · 建议 \(Int(suggested)) ms")
            }
            if !lines.isEmpty {
                text += "\n" + lines.joined(separator: "\n")
            }
            if importFailures > 0 {
                let shown = importFailureNames.prefix(3).joined(separator: "、")
                let suffix = importFailureNames.count > 3 ? " 等 \(importFailureNames.count) 个" : ""
                text += "\n已跳过：" + (shown.isEmpty ? "\(importFailures) 个（名字未知）" : shown + suffix)
            }
            statusLabel.text = text

            if true {
                var planItems: [PlanItem] = []
                for category in order where groups[category] != nil {
                    let list = groups[category] ?? []
                    let average = (rates[category] ?? []).reduce(0, +) / Double(max(1, list.count))
                    let value = OffsetStore.suggestion(forMbps: average) ?? offsetMs
                    for url in list {
                        planItems.append(PlanItem(url: url, category: category.rawValue, offset: value))
                    }
                }
                if planItems.isEmpty {
                    planItems = urls.map { PlanItem(url: $0, category: "未分类", offset: offsetMs) }
                }
                presentPlan(planItems)
            }
        } else if !importFailureNames.isEmpty {
            statusLabel.text = "全部导入失败，共 \(importFailureNames.count) 个：\n"
                + importFailureNames.prefix(5).joined(separator: "\n")
                + (importFailureNames.count > 5 ? "\n……" : "")
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
    /// 连接回调分散在多个后台队列，字典必须串行访问
    private let lock = NSLock()
    private(set) var port: UInt16 = 0

    var isRunning: Bool { listener != nil }

    private init() {}

    func start(completion: @escaping (UInt16) -> Void) {
        guard listener == nil else {
            completion(port)
            return
        }
        Log.write("server: start requested \(BuildInfo.display)")
        // 端口写死，链接就能长期有效；被占用就顺延
        attempt(ports: [8080, 8081, 8082, 8083, 8084, 8085], completion: completion)
    }

    private func attempt(ports: [UInt16], completion: @escaping (UInt16) -> Void) {
        let candidate = ports.first ?? 0
        let rest = Array(ports.dropFirst())

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: candidate)!) else {
            if rest.isEmpty { failOut(completion) } else { attempt(ports: rest, completion: completion) }
            return
        }

        var reported = false
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue ?? 0
                Log.write("server: ready on \(self.port)")
                guard !reported else { return }
                reported = true
                let value = self.port
                DispatchQueue.main.async { completion(value) }
            case .failed(let error):
                Log.write("server: port \(candidate) failed \(error)")
                guard !reported else { return }
                reported = true
                listener.cancel()
                DispatchQueue.main.async {
                    if rest.isEmpty {
                        self.failOut(completion)
                    } else {
                        self.attempt(ports: rest, completion: completion)
                    }
                }
            case .cancelled:
                guard !reported else { return }
                reported = true
                DispatchQueue.main.async { self.failOut(completion) }
            default:
                break
            }
        }

        self.listener = listener
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func failOut(_ completion: @escaping (UInt16) -> Void) {
        Log.write("server: no port available")
        listener = nil
        port = 0
        DispatchQueue.main.async { completion(0) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        lock.lock()
        let all = connections.values
        connections.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }

    func url(for file: URL) -> String? {
        guard port != 0 else { return nil }
        let name = file.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.lastPathComponent
        return "http://127.0.0.1:\(port)/\(name)"
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        lock.lock()
        let tooMany = connections.count >= 8
        if !tooMany {
            connections[ObjectIdentifier(connection)] = connection
        }
        lock.unlock()

        // 同时最多 8 条连接，防止被本地其它进程刷爆
        if tooMany {
            connection.cancel()
            return
        }
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

    private func playlistFiles() -> [URL] {
        let dir = CompensateExporter.documentsDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                 includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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
        lock.lock()
        connections.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
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
        guard parts.count >= 2 else { close(connection); return }

        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            sendText(connection, status: "405 Method Not Allowed", text: "only GET/HEAD")
            return
        }
        let isHead = (method == "HEAD")

        var path = String(parts[1])
        if let mark = path.firstIndex(of: "?") { path = String(path[..<mark]) }
        path = path.removingPercentEncoding ?? path

        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, !name.contains("..") else { close(connection); return }

        if name == "playlist.m3u" {
            var lines = ["#EXTM3U"]
            for item in playlistFiles() {
                let encoded = item.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.lastPathComponent
                lines.append("#EXTINF:-1,\(item.deletingPathExtension().lastPathComponent)")
                lines.append("http://127.0.0.1:\(port)/\(encoded)")
            }
            sendText(connection, status: "200 OK", text: lines.joined(separator: "\n"))
            return
        }

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
            guard bounds.count == 2 else { continue }
            if let start = Int(bounds[0]) {
                rangeStart = start
                if let end = Int(bounds[1]) { rangeEnd = end }
            } else if let suffix = Int(bounds[1]) {
                // bytes=-N 表示最后 N 字节
                rangeStart = max(0, total - suffix)
                rangeEnd = total - 1
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

        if isHead {
            connection.send(content: Data(head.utf8),
                            contentContext: .finalMessage,
                            isComplete: true,
                            completion: .contentProcessed { [weak self] _ in self?.close(connection) })
            return
        }

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

final class LocalServerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let toggleButton = UIButton(type: .system)
    private let playlistButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    private var files: [URL] = []
    private var baseURL: String = "未启动"
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地播放"
        view.backgroundColor = .systemGroupedBackground

        infoLabel.numberOfLines = 0
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabel
        infoLabel.text = """
        启动后，在 CarMovie 的「添加 URL」里粘贴下面的链接即可播放，不用导入。\n也可以只添加一个「播放列表」链接，一次带出全部视频。

        注意：播放时本 App 会进入后台，服务可能被挂起。
        视频不大时 CarMovie 能先缓冲完，就能继续播。
        """

        var config = UIButton.Configuration.filled()
        config.title = "启动本地服务"
        config.cornerStyle = .large
        config.baseBackgroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        toggleButton.configuration = config
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        var playlistConfig = UIButton.Configuration.tinted()
        playlistConfig.title = "复制播放列表链接（一次添加全部）"
        playlistConfig.cornerStyle = .large
        playlistConfig.baseBackgroundColor = Theme.accent
        playlistConfig.baseForegroundColor = Theme.accent
        playlistConfig.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        playlistButton.configuration = playlistConfig
        playlistButton.addAction(UIAction { [weak self] _ in self?.copyPlaylist() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [infoLabel, toggleButton, playlistButton])
        header.axis = .vertical
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        table.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = "还没有导出的视频\n先去「补偿版导出」处理几部"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        table.backgroundView = emptyLabel

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
        emptyLabel.isHidden = !files.isEmpty
    }

    private func toggle() {
        if LocalFileServer.shared.isRunning {
            LocalFileServer.shared.stop()
            baseURL = "未启动"
            updateButton()
            table.reloadData()
            return
        }

        Log.write("server: toggle tapped, running=\(LocalFileServer.shared.isRunning)")
        LocalFileServer.shared.start { [weak self] port in
            DispatchQueue.main.async {
                guard let self else { return }
                self.baseURL = port == 0 ? "启动失败" : "http://127.0.0.1:\(port)"
                self.updateButton()
                self.table.reloadData()
            }
        }
    }

    private func copyPlaylist() {
        guard LocalFileServer.shared.isRunning else {
            let alert = UIAlertController(title: "服务没启动", message: "先点上面的「启动本地服务」", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        let link = "http://127.0.0.1:\(LocalFileServer.shared.port)/playlist.m3u"
        UIPasteboard.general.string = link
        Haptics.success()
        let alert = UIAlertController(title: "播放列表已复制",
                                      message: "\(link)\n\n在 CarMovie 里添加这一个链接，它会列出全部视频。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
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
        content.image = UIImage(systemName: "link")
        content.imageProperties.tintColor = Theme.accent
        content.imageProperties.maximumSize = CGSize(width: 20, height: 20)
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
            let alert = UIAlertController(title: "服务没启动", message: "先点上面的「启动本地服务」", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        UIPasteboard.general.string = link
        Haptics.success()
        let alert = UIAlertController(title: "已复制", message: link, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - 视频参数

enum VideoInfo {

    struct Info {
        let width: Int
        let height: Int
        let fps: Double
        let megabitsPerSecond: Double
        let codec: String
        let seconds: Double

        var category: Category {
            Category.of(megabitsPerSecond)
        }

        var shortSummary: String {
            let size = width > 0 ? "\(width)×\(height)" : "分辨率未知"
            let rate = megabitsPerSecond > 0 ? String(format: "%.1f Mbps", megabitsPerSecond) : "码率未知"
            return "\(size) · \(rate) · \(codec)"
        }

        var summary: String {
            let size = width > 0 ? "\(width)×\(height)" : "分辨率未知"
            let fpsText = fps > 0 ? String(format: "%.0ffps", fps) : "帧率未知"
            let rateText = megabitsPerSecond > 0
                ? String(format: "%.1f Mbps", megabitsPerSecond)
                : "码率未知"
            return "\(size) · \(fpsText) · \(rateText) · \(codec) · \(Format.time(seconds))"
        }
    }

    static func load(_ url: URL) -> Info? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        let transformed = track.naturalSize.applying(track.preferredTransform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())

        var codec = "编码未知"
        if let list = track.formatDescriptions as? [CMFormatDescription],
           let description = list.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
        }

        return Info(width: width,
                    height: height,
                    fps: Double(track.nominalFrameRate),
                    megabitsPerSecond: Double(track.estimatedDataRate) / 1_000_000,
                    codec: codec,
                    seconds: CMTimeGetSeconds(asset.duration))
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        let text = String(bytes: bytes, encoding: .isoLatin1) ?? ""
        switch text {
        case "hvc1", "hev1": return "HEVC"
        case "avc1": return "H.264"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        default: return text.isEmpty ? "编码未知" : text
        }
    }
}

// MARK: - 码率分档

extension VideoInfo {

    enum Category: String, CaseIterable {
        case low = "低码率"
        case medium = "中码率"
        case high = "高码率"
        case ultra = "超高码率"

        static func of(_ mbps: Double) -> Category {
            guard mbps > 0 else { return .medium }
            if mbps < 4 { return .low }
            if mbps < 10 { return .medium }
            if mbps < 20 { return .high }
            return .ultra
        }

        var hint: String {
            switch self {
            case .low: return "解码压力小，补偿可以少一些"
            case .medium: return "常见 MV 区间"
            case .high: return "解码缓冲明显变大"
            case .ultra: return "4K / 高帧率，补偿往往要到 -300 以下"
            }
        }
    }
}

/// 读一次缓存一次，列表滚动时不会反复解析
enum VideoInfoCache {

    private static var storage: [String: VideoInfo.Info] = [:]
    private static let lock = NSLock()

    private static func key(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(url.lastPathComponent)-\(values?.fileSize ?? 0)-\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func cached(_ url: URL) -> VideoInfo.Info? {
        let k = key(for: url)
        lock.lock(); defer { lock.unlock() }
        return storage[k]
    }

    private static func store(_ info: VideoInfo.Info, for url: URL) {
        let k = key(for: url)
        lock.lock()
        storage[k] = info
        if storage.count > 200 { storage.removeAll() }
        lock.unlock()
    }

    static func info(for url: URL) -> VideoInfo.Info? {
        if let hit = cached(url) { return hit }
        guard let info = VideoInfo.load(url) else { return nil }
        store(info, for: url)
        return info
    }

    /// 后台解析，回调在主线程
    static func loadAsync(for url: URL, completion: @escaping (VideoInfo.Info?) -> Void) {
        if let hit = cached(url) {
            completion(hit)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let info = VideoInfo.load(url)
            if let info { store(info, for: url) }
            DispatchQueue.main.async { completion(info) }
        }
    }
}

// MARK: - 免转码重封装

/// 只搬动压缩后的样本、改时间戳，画面和声音都不重新编码。
/// 4K 一部长片从"几十分钟"降到"几十秒"。
enum Remuxer {

    static var activeWriter: AVAssetWriter?

    static func cancel() {
        activeWriter?.cancelWriting()
        activeWriter = nil
    }

    static func shift(source: URL,
                      offsetMs: Double,
                      to out: URL,
                      progress: @escaping (Double) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {

        var settled = false
        let settle: (Result<URL, Error>) -> Void = { result in
            guard !settled else { return }
            settled = true
            activeWriter = nil
            completion(result)
        }

        let asset = AVURLAsset(url: source)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            settle(.failure(CompensateError.noVideoTrack))
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first
        let duration = CMTimeGetSeconds(asset.duration)
        try? FileManager.default.removeItem(at: out)

        guard let reader = try? AVAssetReader(asset: asset) else {
            settle(.failure(CompensateError.exportFailed("reader 创建失败")))
            return
        }

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            settle(.failure(CompensateError.exportFailed("无法读取视频轨")))
            return
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        guard let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else {
            settle(.failure(CompensateError.exportFailed("writer 创建失败")))
            return
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            settle(.failure(CompensateError.exportFailed("无法写入视频轨")))
            return
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                settle(.failure(CompensateError.exportFailed("音轨无法写入")))
                return
            }
            writer.add(input)
            audioInput = input
        }

        activeWriter = writer
        Log.write("remux start \(source.lastPathComponent)")
        // 免转码 2 分钟不完成就认输，交给转码兜底
        let watchdog = DispatchWorkItem {
            guard !settled else { return }
            Log.write("remux timeout \(source.lastPathComponent)")
            reader.cancelReading()
            writer.cancelWriting()
            settle(.failure(CompensateError.exportFailed("remux timeout")))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: watchdog)

        guard writer.startWriting() else {
            settle(.failure(CompensateError.exportFailed(
                writer.error?.localizedDescription ?? "writer 启动失败")))
            return
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            settle(.failure(CompensateError.exportFailed("reader 启动失败")))
            return
        }

        let magnitude = CMTime(seconds: abs(offsetMs) / 1000.0, preferredTimescale: 600)
        let videoShift: CMTime = offsetMs < 0 ? magnitude : .zero
        let audioShift: CMTime = offsetMs > 0 ? magnitude : .zero

        let group = DispatchGroup()

        group.enter()
        pump(output: videoOutput, input: videoInput, shift: videoShift,
             duration: duration, progress: nil) { group.leave() }

        if let audioOutput, let audioInput {
            group.enter()
            pump(output: audioOutput, input: audioInput, shift: audioShift,
                 duration: duration, progress: progress) { group.leave() }
        } else {
            progress(0.5)
        }

        group.notify(queue: .main) {
            if reader.status == .failed {
                writer.cancelWriting()
                settle(.failure(CompensateError.exportFailed(
                    reader.error?.localizedDescription ?? "读取中断")))
                return
            }

            videoInput.markAsFinished()
            audioInput?.markAsFinished()

            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        Log.write("remux done \(out.lastPathComponent)")
                        progress(1)
                        settle(.success(out))
                    } else {
                        settle(.failure(CompensateError.exportFailed(
                            writer.error?.localizedDescription ?? "写入失败")))
                    }
                }
            }
        }
    }

    private static func pump(output: AVAssetReaderTrackOutput,
                             input: AVAssetWriterInput,
                             shift: CMTime,
                             duration: Double,
                             progress: ((Double) -> Void)?,
                             done: @escaping () -> Void) {
        let queue = DispatchQueue(label: "remux.track")
        var finished = false

        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                guard let sample = output.copyNextSampleBuffer() else {
                    if !finished {
                        finished = true
                        done()
                    }
                    return
                }

                if progress != nil {
                    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                    if duration > 0 {
                        progress?(min(0.99, max(0, pts / duration)))
                    }
                }

                if shift == .zero {
                    input.append(sample)
                } else if let adjusted = shifted(sample, by: shift) {
                    input.append(adjusted)
                }
            }
        }
    }

    private static func shifted(_ sample: CMSampleBuffer, by shift: CMTime) -> CMSampleBuffer? {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0,
                                              arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return sample }

        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count,
                                              arrayToFill: &timing, entriesNeededOut: &count)

        for index in 0..<count {
            timing[index].presentationTimeStamp =
                CMTimeAdd(timing[index].presentationTimeStamp, shift)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp =
                    CMTimeAdd(timing[index].decodeTimeStamp, shift)
            }
        }

        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                          sampleBuffer: sample,
                                                          sampleTimingEntryCount: count,
                                                          sampleTimingArray: &timing,
                                                          sampleBufferOut: &output)
        guard status == noErr else { return nil }
        return output
    }
}


// MARK: - 分批面板

/// 一个待导视频：自己的偏移、自己的分组
struct PlanItem {
    let url: URL
    let category: String
    var offset: Double
}

final class BatchPlanViewController: UIViewController {

    /// 导出的批次（每组：文件 + 统一偏移）
    var onExport: (([([URL], Double)], [PlanItem]) -> Void)?
    var onCancel: (() -> Void)?

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let bar = UIStackView()
    private var exportButton: UIButton?

    private var items: [PlanItem] = []
    private var sections: [(title: String, rows: [Int])] = []

    init(items: [PlanItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        rebuildSections()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "分批导出"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain,
                                                           target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "全部按顺序", style: .done,
                                                            target: self, action: #selector(exportAll))

        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelectionDuringEditing = true
        table.setEditing(true, animated: false)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = "勾选后可「导出选中」；长按某一行可单独改它的偏移。\n没导的文件会留在这里，关掉面板也不会丢。"
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.frame = CGRect(x: 0, y: 0, width: 320, height: 56)
        table.tableHeaderView = hint

        view.addSubview(table)

        let removeButton = UIButton(type: .system)
        removeButton.setTitle("移出清单（不删文件）", for: .normal)
        removeButton.tintColor = .systemRed
        removeButton.addAction(UIAction { [weak self] _ in self?.removeSelected() }, for: .touchUpInside)

        let export = UIButton(type: .system)
        export.setTitle("导出选中", for: .normal)
        export.tintColor = Theme.accent
        export.isEnabled = false
        export.addAction(UIAction { [weak self] _ in self?.exportSelected() }, for: .touchUpInside)
        exportButton = export

        bar.axis = .horizontal
        bar.distribution = .fillEqually
        bar.backgroundColor = .secondarySystemGroupedBackground
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addArrangedSubview(removeButton)
        bar.addArrangedSubview(export)
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    // MARK: 数据

    private func rebuildSections() {
        let order = ["低码率", "中码率", "高码率", "超高码率", "未分类"]
        var groups: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            groups[item.category, default: []].append(index)
        }
        sections = order.compactMap { key in
            guard let rows = groups[key], !rows.isEmpty else { return nil }
            return (key, rows)
        }
    }

    private func item(at indexPath: IndexPath) -> PlanItem? {
        guard indexPath.section < sections.count else { return nil }
        let rows = sections[indexPath.section].rows
        guard indexPath.row < rows.count else { return nil }
        let index = rows[indexPath.row]
        guard index < items.count else { return nil }
        return items[index]
    }

    // MARK: 操作

    @objc private func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func exportAll() {
        guard !items.isEmpty else { return }

        let total = items.reduce(Int64(0)) { sum, item in
            sum + Int64((try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        let alert = UIAlertController(
            title: "导出全部 \(items.count) 个？",
            message: "共 \(Format.bytes(total))，会按当前顺序逐个处理，过程中可以取消。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "先不导", style: .cancel))
        alert.addAction(UIAlertAction(title: "开始导出", style: .default) { [weak self] _ in
            guard let self else { return }
            self.export(items: self.items.map { ($0.url, $0.offset) })
        })
        present(alert, animated: true)
    }

    private func exportSelected() {
        let chosen = selectedItems()
        guard !chosen.isEmpty else { return }
        export(items: chosen.map { ($0.url, $0.offset) })
    }

    private func selectedItems() -> [PlanItem] {
        let paths = (table.indexPathsForSelectedRows ?? []).sorted {
            $0.section == $1.section ? $0.row < $1.row : $0.section < $1.section
        }
        return paths.compactMap { item(at: $0) }
    }

    /// 按偏移值归批：同一偏移的一起导，不同偏移自动拆开
    private func export(items chosen: [(URL, Double)]) {
        guard !chosen.isEmpty else { return }

        var order: [Double] = []
        var buckets: [Double: [URL]] = [:]
        for (url, offset) in chosen {
            if buckets[offset] == nil { order.append(offset) }
            buckets[offset, default: []].append(url)
        }
        let batches = order.map { (buckets[$0] ?? [], $0) }

        let chosenURLs = Set(chosen.map { $0.0 })
        let remaining = items.filter { !chosenURLs.contains($0.url) }

        onExport?(batches, remaining)
        dismiss(animated: true)
    }

    private func removeSelected() {
        let chosenItems = selectedItems()
        let chosen = Set(chosenItems.map { $0.url })
        guard !chosen.isEmpty else { return }

        let alert = UIAlertController(
            title: "从清单移出 \(chosen.count) 个？",
            message: "只是不参与这次导出，文件本身还在「已导出」里，不会删除。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "移出", style: .destructive) { [weak self] _ in
            self?.performRemove(chosen)
        })
        present(alert, animated: true)
    }

    private func performRemove(_ chosen: Set<URL>) {
        items.removeAll { chosen.contains($0.url) }
        rebuildSections()
        table.reloadData()
        updateSelectionButton()

        if items.isEmpty {
            onCancel?()
            dismiss(animated: true)
        }
    }

    private func updateSelectionButton() {
        let count = table.indexPathsForSelectedRows?.count ?? 0
        exportButton?.setTitle(count > 0 ? "导出选中（\(count)）" : "导出选中", for: .normal)
        exportButton?.isEnabled = count > 0
    }

    /// 点一行：单独调这个文件的偏移
    private func editOffset(_ indexPath: IndexPath) {
        guard let item = item(at: indexPath) else { return }
        let alert = UIAlertController(title: "单独设置偏移",
                                      message: item.url.lastPathComponent,
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.text = String(Int(item.offset))
            field.keyboardType = .numbersAndPunctuation
            field.placeholder = "例如 -330"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let self, let text = alert.textFields?.first?.text,
                  let value = Double(text) else { return }
            let clamped = min(400, max(-400, value.rounded()))
            if let index = self.items.firstIndex(where: { $0.url == item.url }) {
                self.items[index].offset = clamped
            }
            self.table.reloadData()
        })
        present(alert, animated: true)
    }
}

extension BatchPlanViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = sections[section].title
        let label = UILabel()
        label.text = "\(title) · \(sections[section].rows.count) 个"
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Theme.accent

        let row = UIStackView(arrangedSubviews: [label, UIView()])
        row.axis = .horizontal
        row.layoutMargins = UIEdgeInsets(top: 6, left: 20, bottom: 6, right: 20)
        row.isLayoutMarginsRelativeArrangement = true
        return row
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        36
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        guard let item = item(at: indexPath) else { return cell }

        var content = cell.defaultContentConfiguration()
        let custom = TitleStore.title(for: item.url)
        content.text = custom ?? item.url.lastPathComponent
        content.textProperties.numberOfLines = 1
        content.textProperties.lineBreakMode = .byTruncatingMiddle
        content.image = UIImage(systemName: "film")
        content.imageProperties.tintColor = Theme.accent

        let size = Int64((try? item.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        content.secondaryText = String(format: "%.0f ms · %@", item.offset, Format.bytes(size))
        content.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        updateSelectionButton()
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        updateSelectionButton()
    }

    /// 轻点右侧 info 区进偏移编辑；这里用长按避免和勾选冲突
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let edit = UIAction(title: "改这个文件的偏移", image: UIImage(systemName: "slider.horizontal.3")) { _ in
                self?.editOffset(indexPath)
            }
            return UIMenu(title: "", children: [edit])
        }
    }
}
