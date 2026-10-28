import Foundation
import UIKit
import ComposeApp
#if canImport(NuvioAetherKit)
import NuvioAetherKit
#endif

// The AetherEngine player, offered next to MPV by the "Player" setting. NuvioAetherKit is a local
// Swift package (aether/NuvioAetherKit) that aether/scripts/patch-xcode-project.py adds to the
// project; without it this file compiles to a no-op and Nuvio keeps playing through MPV.

enum NuvioAetherRegistration {
    static func register() {
        #if canImport(NuvioAetherKit)
        NuvioAetherPlayerBridgeFactory.shared.registerFactory(creator: AetherPlayerBridgeCreator())
        #endif
    }
}

#if canImport(NuvioAetherKit)

// MARK: - Bridge (Kotlin protocol conformance)

final class AetherPlayerBridgeImpl: NSObject, NuvioAetherPlayerBridge {

    private var playerVC: AetherPlayerViewController?

    private func ensurePlayerViewController() -> AetherPlayerViewController {
        if let playerVC { return playerVC }
        let vc = AetherPlayerViewController()
        playerVC = vc
        return vc
    }

    func createPlayerViewController() -> UIViewController {
        ensurePlayerViewController()
    }

    func configureAether(optionsJson: String) {
        ensurePlayerViewController().aetherOptions = NuvioAetherOptions(json: optionsJson)
    }

    func setStartPositionMs(positionMs: Int64) {
        ensurePlayerViewController().nextStartPositionMs = positionMs
    }

    func loadFile(url: String) {
        ensurePlayerViewController().loadFile(url, requestHeaders: [:], subtitles: [])
    }

    func loadFileWithAudio(videoUrl: String, audioUrl: String?, headersJson: String?, subtitlesJson: String?) {
        // Sources with a separate audio stream stay on MPV (see createIosPlayerBridge).
        ensurePlayerViewController().loadFile(
            videoUrl,
            requestHeaders: parseRequestHeaders(headersJson),
            subtitles: parseSubtitles(subtitlesJson)
        )
    }

    func play() { playerVC?.playPlayback() }
    func pause() { playerVC?.pausePlayback() }
    func seekTo(positionMs: Int64) { playerVC?.seekToMs(positionMs) }
    func seekBy(offsetMs: Int64) { playerVC?.seekByMs(offsetMs) }

    func setSystemControlHandler(handler: PlayerSystemControlHandler?) {
        if let handler {
            ensurePlayerViewController().systemControlHandler = handler
        } else {
            playerVC?.systemControlHandler = nil
        }
    }

    func getKeepsPlaybackInBackground() -> Bool { playerVC?.keepsPlaybackInBackground ?? false }
    func retry() { playerVC?.retryPlayback() }

    func updateNowPlayingMetadata(title: String, subtitle: String?, artworkUrl: String?) {
        ensurePlayerViewController().updateNowPlayingMetadata(title: title, subtitle: subtitle, artworkUrl: artworkUrl)
    }

    func clearNowPlayingInfo() { playerVC?.clearNowPlayingInfo() }

    // MPV's renderer, tone-mapping and audio-output settings: AetherEngine hands decoding,
    // HDR / Dolby Vision presentation and the audio route to the system instead.
    func configureVideoOutput(
        hardwareDecoder: String,
        targetColorspaceHint: Bool,
        toneMapping: String,
        hdrComputePeak: Bool,
        targetPrimaries: String,
        targetTransfer: String,
        extendedDynamicRange: Bool,
        deband: Bool,
        interpolation: Bool,
        brightness: Int32,
        contrast: Int32,
        saturation: Int32,
        gamma: Int32
    ) {}

    func configureAudioOutput(audioOutput: String) {}

    func setPlaybackSpeed(speed: Float) { playerVC?.setSpeed(speed) }
    func setMuted(muted: Bool) { playerVC?.setMuted(muted) }
    func setResizeMode(mode: Int32) { playerVC?.setResize(Int(mode)) }

    func syncVideoSurfaceLayout(width: Double, height: Double) {
        playerVC?.syncVideoSurfaceLayout(size: CGSize(width: width, height: height))
    }

    // Audio tracks
    func getAudioTrackCount() -> Int32 { Int32(playerVC?.audioTracks.count ?? 0) }
    func getAudioTrackIndex(at: Int32) -> Int32 { audioTrack(at) == nil ? 0 : at }
    func getAudioTrackId(at: Int32) -> String { audioTrack(at).map { "\($0.id)" } ?? "0" }
    func getAudioTrackLabel(at: Int32) -> String { audioTrack(at)?.title ?? "" }
    func getAudioTrackLang(at: Int32) -> String { audioTrack(at)?.language ?? "" }
    func isAudioTrackSelected(at: Int32) -> Bool { audioTrack(at)?.isSelected ?? false }

    // Subtitle tracks
    func getSubtitleTrackCount() -> Int32 { Int32(playerVC?.subtitleTracks.count ?? 0) }
    func getSubtitleTrackIndex(at: Int32) -> Int32 { subtitleTrack(at) == nil ? 0 : at }
    func getSubtitleTrackId(at: Int32) -> String { subtitleTrack(at).map { "\($0.id)" } ?? "0" }
    func getSubtitleTrackLabel(at: Int32) -> String { subtitleTrack(at)?.title ?? "" }
    func getSubtitleTrackLang(at: Int32) -> String { subtitleTrack(at)?.language ?? "" }
    func isSubtitleTrackSelected(at: Int32) -> Bool { subtitleTrack(at)?.isSelected ?? false }

    private func audioTrack(_ position: Int32) -> NuvioAetherTrack? {
        guard let tracks = playerVC?.audioTracks, position >= 0, Int(position) < tracks.count else { return nil }
        return tracks[Int(position)]
    }

    private func subtitleTrack(_ position: Int32) -> NuvioAetherTrack? {
        guard let tracks = playerVC?.subtitleTracks, position >= 0, Int(position) < tracks.count else { return nil }
        return tracks[Int(position)]
    }

    func selectAudioTrack(trackId: Int32) { playerVC?.selectAudio(Int(trackId)) }

    func applyAudioLanguagePreferences(languages: [String]) {
        ensurePlayerViewController().applyAudioLanguagePreferences(languages)
    }

    func selectSubtitleTrack(trackId: Int32) { playerVC?.selectSubtitle(Int(trackId)) }
    func setSubtitleUrl(url: String) { playerVC?.addSubtitleUrl(url) }
    func clearExternalSubtitle() { playerVC?.removeExternalSubtitlesAndSelect(-1) }
    func clearExternalSubtitleAndSelect(trackId: Int32) { playerVC?.removeExternalSubtitlesAndSelect(Int(trackId)) }
    func setSubtitleDelayMs(delayMs: Int32) { playerVC?.setSubtitleDelayMs(Int(delayMs)) }

    func applySubtitleStyle(
        textColor: String,
        backgroundColor: String,
        outlineColor: String,
        outlineSize: Float,
        bold: Bool,
        fontSize: Float,
        subPos: Int32,
        stripSdh: Bool
    ) {
        var style = NuvioAetherSubtitleStyle()
        style.textColor = textColor
        style.backgroundColor = backgroundColor
        style.outlineColor = outlineColor
        style.outlineSize = outlineSize
        style.bold = bold
        style.fontSize = fontSize
        style.subPos = Int(subPos)
        style.stripSdh = stripSdh
        ensurePlayerViewController().subtitleStyle = style
    }

    // State, polled from Kotlin every 250 ms.
    func getIsLoading() -> Bool { playerVC?.refreshPlaybackState() ?? true }
    func getIsPlaying() -> Bool { playerVC?.isPlayerPlaying ?? false }
    func getIsEnded() -> Bool { playerVC?.isPlayerEnded ?? false }
    func getDurationMs() -> Int64 { playerVC?.durationMs ?? 0 }
    func getPositionMs() -> Int64 { playerVC?.positionMs ?? 0 }
    func getBufferedMs() -> Int64 { playerVC?.bufferedMs ?? 0 }
    func getPlaybackSpeed() -> Float { playerVC?.currentSpeed ?? 1.0 }
    func getErrorMessage() -> String { playerVC?.currentErrorMessage ?? "" }
    func getProperty(name: String) -> String { playerVC?.mpvProperty(name) ?? "" }

    func destroy() {
        playerVC?.systemControlHandler = nil
        playerVC?.destroyPlayer()
        playerVC = nil
    }

    private func parseSubtitles(_ json: String?) -> [NuvioAetherExternalSubtitle] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return raw.compactMap { dict in
            guard let url = dict["url"] as? String else { return nil }
            return NuvioAetherExternalSubtitle(
                url: url,
                name: dict["name"] as? String,
                language: dict["language"] as? String,
                headers: dict["headers"] as? [String: String]
            )
        }
    }

    private func parseRequestHeaders(_ headersJson: String?) -> [String: String] {
        guard
            let headersJson,
            let data = headersJson.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return raw.compactMapValues { $0 as? String }
    }
}

final class AetherPlayerBridgeCreator: NSObject, NuvioAetherPlayerBridgeCreator {
    func createAetherBridge() -> any NuvioAetherPlayerBridge {
        AetherPlayerBridgeImpl()
    }
}

// MARK: - View controller

/// Hosts the AetherEngine surface inside the Compose player screen. Mirrors what
/// `MPVPlayerViewController` does around MPV: immersive system UI, Now Playing and remote
/// commands, the audio session, and Nuvio's background / Picture in Picture policy.
final class AetherPlayerViewController: UIViewController, PlayerNowPlayingOwner {

    private struct CachedNowPlayingMetadata {
        let title: String
        let subtitle: String?
        let artworkUrl: String?
    }

    private lazy var player = NuvioAetherPlayer()
    private var cachedNowPlayingMetadata: CachedNowPlayingMetadata?
    private lazy var nowPlayingController = PlayerNowPlayingController(owner: self)
    private lazy var audioSessionController: PlayerAudioSessionController = {
        let controller = PlayerAudioSessionController()
        controller.onConfigurationChanged = { [weak self] in
            guard let self else { return }
            self.publishCachedNowPlayingInfoIfNeeded()
            self.syncNowPlayingPlaybackState()
        }
        return controller
    }()

    var systemControlHandler: PlayerSystemControlHandler?
    var nextStartPositionMs: Int64 = 0

    var aetherOptions: NuvioAetherOptions {
        get { player.options }
        set { player.options = newValue }
    }

    var subtitleStyle: NuvioAetherSubtitleStyle {
        get { player.subtitleStyle }
        set { player.subtitleStyle = newValue }
    }

    var keepsPlaybackInBackground: Bool { player.keepsPlaybackInBackground }
    var isPlayerPlaying: Bool { player.isPlaying }
    var isPlayerEnded: Bool { player.isEnded }
    var durationMs: Int64 { player.durationMs }
    var positionMs: Int64 { player.positionMs }
    var bufferedMs: Int64 { player.bufferedMs }
    var currentSpeed: Float { player.playbackRate }
    var currentErrorMessage: String { player.errorMessage ?? "" }
    var audioTracks: [NuvioAetherTrack] { player.audioTracks }
    var subtitleTracks: [NuvioAetherTrack] { player.subtitleTracks }

    override var canBecomeFirstResponder: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom, .left, .right] }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.masksToBounds = true

        player.view.frame = view.bounds
        player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(player.view)

        player.onPictureInPictureChange = { [weak self] active in
            guard let self else { return }
            SystemUI.shared.setPictureInPicturePlaceholder(self, visible: active)
        }
        player.onSystemSetPlaying = { [weak self] playing in
            self?.requestSystemPlaying(playing)
        }
        player.onSystemSkip = { [weak self] seconds in
            self?.requestSystemSeekBy(Int64(seconds * 1000), exact: true)
        }

        audioSessionController.activate()
        NotificationCenter.default.addObserver(
            self, selector: #selector(enterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(enterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        refreshImmersiveSystemUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshImmersiveSystemUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        SystemUI.shared.playerDidBecomeVisible(self)
        refreshImmersiveSystemUI()
        becomeFirstResponder()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        publishCachedNowPlayingInfoIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        SystemUI.shared.playerDidBecomeHidden(self)
        super.viewWillDisappear(animated)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            SystemUI.shared.playerDidBecomeHidden(self)
        }
    }

    /// Compose reports the surface size; apply it the way the MPV player does.
    func syncVideoSurfaceLayout(size: CGSize) {
        guard isViewLoaded, size.width > 1, size.height > 1 else { return }
        let targetBounds = CGRect(origin: .zero, size: size)
        if view.bounds != targetBounds {
            view.bounds = targetBounds
        }
        if view.frame.size != size {
            var frame = view.frame
            frame.size = size
            view.frame = frame
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    @objc private func enterBackground() {
        player.applicationDidEnterBackground()
    }

    @objc private func enterForeground() {
        player.applicationWillEnterForeground()
    }

    // MARK: Playback

    func loadFile(_ url: String, requestHeaders: [String: String], subtitles: [NuvioAetherExternalSubtitle]) {
        let startPositionMs = nextStartPositionMs
        nextStartPositionMs = 0
        player.load(url: url, headers: requestHeaders, subtitles: subtitles, startPositionMs: startPositionMs)
    }

    func playPlayback() {
        publishNowPlayingForPlaybackSession()
        player.play()
        syncNowPlayingPlaybackState(isPlaying: true)
    }

    func pausePlayback() {
        player.pause()
        syncNowPlayingPlaybackState(isPlaying: false)
    }

    func seekToMs(_ positionMs: Int64) { player.seek(toMs: positionMs) }
    func seekByMs(_ offsetMs: Int64) { player.seek(byMs: offsetMs) }
    func retryPlayback() { player.retry() }
    func setSpeed(_ speed: Float) { player.setPlaybackRate(speed) }
    func setMuted(_ muted: Bool) { player.setMuted(muted) }
    func setResize(_ mode: Int) { player.setResizeMode(mode) }
    func selectAudio(_ trackId: Int) { player.selectAudioTrack(id: trackId) }
    func applyAudioLanguagePreferences(_ languages: [String]) { player.applyAudioLanguagePreferences(languages) }
    func selectSubtitle(_ trackId: Int) { player.selectSubtitleTrack(id: trackId) }
    func addSubtitleUrl(_ url: String) { player.addSidecarSubtitle(url: url) }
    func removeExternalSubtitlesAndSelect(_ trackId: Int) { player.removeSidecarSubtitles(thenSelect: trackId) }
    func setSubtitleDelayMs(_ delayMs: Int) { player.setSubtitleDelay(milliseconds: delayMs) }
    func mpvProperty(_ name: String) -> String? { player.mpvProperty(name) }

    /// Returns whether the player is loading, and keeps Now Playing in step with the snapshot.
    func refreshPlaybackState() -> Bool {
        let loading = player.isLoading
        if !loading || player.isPlaying || player.durationMs > 0 || player.positionMs > 0 {
            syncNowPlayingPlaybackState()
        }
        return loading
    }

    func destroyPlayer() {
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
        resignFirstResponder()
        SystemUI.shared.setPictureInPicturePlaceholder(self, visible: false)
        nowPlayingController.invalidate()
        audioSessionController.deactivate()
        player.stop()
    }

    // MARK: System controls (Now Playing, PiP): routed through the session controller first

    func requestSystemPlaying(_ playing: Bool) {
        if systemControlHandler?.handleSetPlaying(playing: playing) == true { return }
        if playing { playPlayback() } else { pausePlayback() }
    }

    func requestSystemSeekTo(_ positionMs: Int64) {
        if systemControlHandler?.handleSeekTo(positionMs: positionMs) == true { return }
        seekToMs(positionMs)
    }

    func requestSystemSeekBy(_ offsetMs: Int64, exact: Bool) {
        if systemControlHandler?.handleSeekBy(offsetMs: offsetMs) == true { return }
        seekByMs(offsetMs)
    }

    // MARK: Now Playing

    func updateNowPlayingMetadata(title: String, subtitle: String?, artworkUrl: String?) {
        cachedNowPlayingMetadata = CachedNowPlayingMetadata(title: title, subtitle: subtitle, artworkUrl: artworkUrl)
        nowPlayingController.updateMetadata(title: title, subtitle: subtitle, artworkUrl: artworkUrl)
        publishNowPlayingForPlaybackSession()
    }

    func clearNowPlayingInfo() {
        cachedNowPlayingMetadata = nil
        nowPlayingController.clear()
    }

    private func publishCachedNowPlayingInfoIfNeeded() {
        guard let metadata = cachedNowPlayingMetadata else { return }
        nowPlayingController.updateMetadata(
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkUrl: metadata.artworkUrl
        )
    }

    private func publishNowPlayingForPlaybackSession() {
        audioSessionController.activate()
        if isViewLoaded, view.window != nil {
            becomeFirstResponder()
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
        publishCachedNowPlayingInfoIfNeeded()
        syncNowPlayingPlaybackState()
    }

    private func syncNowPlayingPlaybackState(isPlaying: Bool? = nil) {
        nowPlayingController.syncPlayback(
            positionMs: player.positionMs,
            durationMs: player.durationMs,
            isPlaying: isPlaying ?? player.isPlaying,
            playbackSpeed: player.playbackRate
        )
    }

    private func refreshImmersiveSystemUI() {
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsStatusBarAppearanceUpdate()

        var currentParent = parent
        while let controller = currentParent {
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            controller.setNeedsStatusBarAppearanceUpdate()
            if let rootController = controller as? RootComposeViewController {
                rootController.refreshImmersiveSystemUI()
            }
            currentParent = controller.parent
        }
    }
}

#endif
