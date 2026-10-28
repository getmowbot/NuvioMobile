import AVFoundation
import Combine
import UIKit
internal import AetherEngine

/// AetherEngine behind the small surface Nuvio's player bridge needs: transport, state snapshots,
/// tracks, subtitles (rendered here, the engine leaves that to its host), Picture in Picture and
/// the background policy of Nuvio's MPV player. Main actor only.
@MainActor
public final class NuvioAetherPlayer {
    /// The video surface with its subtitle overlay. Host it full size in the player screen.
    public let view: UIView

    /// Applied from the next load.
    public var options = NuvioAetherOptions()
    public var preferredAudioLanguages: [String] = []
    public var subtitleStyle = NuvioAetherSubtitleStyle() {
        didSet { subtitleOverlay.style = subtitleStyle }
    }

    /// Picture in Picture started (true) or ended (false).
    public var onPictureInPictureChange: ((Bool) -> Void)?
    /// Play / pause and skips coming from the PiP window, for the host's system-control routing.
    public var onSystemSetPlaying: ((Bool) -> Void)? {
        didSet { pictureInPicture?.onSetPlaying = onSystemSetPlaying }
    }
    public var onSystemSkip: ((Double) -> Void)? {
        didSet { pictureInPicture?.onSkip = onSystemSkip }
    }

    private let engine: AetherEngine?
    private let engineInitError: String?
    private let containerView: AetherContainerView
    private let playerView: AetherPlayerView
    private let subtitleOverlay: AetherSubtitleOverlayView
    private var pictureInPicture: AetherPictureInPicture?
    private var cancellables = Set<AnyCancellable>()

    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var isLoadInFlight = false
    private var loadError: String?
    private var currentURL: URL?
    private var currentHeaders: [String: String] = [:]
    private var currentSubtitles: [NuvioAetherExternalSubtitle] = []
    private var pendingSidecarURLs: [String] = []
    private var addedSidecarTrackIDs: [Int] = []

    private var wantsPlayback = true
    private var pausedForBackground = false
    private var backgroundGeneration = 0
    private var desiredRate: Float = 1
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var subtitleDelaySeconds: Double = 0

    private var audioTrackCache: (source: [TrackInfo], active: Int?, tracks: [NuvioAetherTrack])?
    private var subtitleTrackCache: (source: [TrackInfo], active: Int?, tracks: [NuvioAetherTrack])?

    public init() {
        do {
            engine = try AetherEngine()
            engineInitError = nil
        } catch {
            engine = nil
            engineInitError = "AetherEngine could not start: \(error.localizedDescription)"
        }
        let container = AetherContainerView(frame: .zero)
        containerView = container
        playerView = AetherPlayerView(frame: .zero)
        subtitleOverlay = AetherSubtitleOverlayView(frame: .zero)
        view = container

        containerView.backgroundColor = .black
        containerView.clipsToBounds = true
        for subview in [playerView, subtitleOverlay] as [UIView] {
            subview.frame = containerView.bounds
            subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.addSubview(subview)
        }
        containerView.onLayout = { [weak self] in self?.updateVideoRect() }

        guard let engine else { return }
        engine.bind(view: playerView)
        engine.videoGravity = videoGravity

        let pip = AetherPictureInPicture(engine: engine)
        pip.onActiveChange = { [weak self] active in self?.pictureInPictureChanged(active) }
        pip.onStoppedInBackground = { [weak self] in self?.pauseForBackground() }
        pictureInPicture = pip

        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSubtitles() }
            .store(in: &cancellables)
        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSubtitles()
                self?.updateVideoRect()
            }
            .store(in: &cancellables)
        engine.$videoRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionLayerChanged() }
            .store(in: &cancellables)
        engine.$hasFirstFrameReadyForDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sessionLayerChanged() }
            .store(in: &cancellables)
    }

    // MARK: - Loading

    /// Opens `urlString`, replacing any running session. `startPositionMs` > 0 opens there directly.
    public func load(
        url urlString: String,
        headers: [String: String],
        subtitles: [NuvioAetherExternalSubtitle],
        startPositionMs: Int64
    ) {
        currentURL = Self.makeURL(urlString)
        currentHeaders = headers
        currentSubtitles = subtitles
        startLoad(startSeconds: startPositionMs > 0 ? Double(startPositionMs) / 1000 : nil)
    }

    /// Reopens the current stream at the current position (Nuvio's "retry").
    public func retry() {
        guard let engine, currentURL != nil else { return }
        let position = engine.currentTime
        startLoad(startSeconds: position > 1 ? position : nil)
    }

    private func startLoad(startSeconds: Double?) {
        guard let engine else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadError = nil
        addedSidecarTrackIDs.removeAll()
        audioTrackCache = nil
        subtitleTrackCache = nil
        subtitleOverlay.show([])

        guard let url = currentURL else {
            loadError = "AetherEngine: invalid stream URL."
            isLoadInFlight = false
            return
        }
        isLoadInFlight = true

        var loadOptions = LoadOptions()
        loadOptions.httpHeaders = currentHeaders
        options.apply(to: &loadOptions)
        loadOptions.preferredAudioLanguages = preferredAudioLanguages
        loadOptions.externalSubtitles = currentSubtitles.compactMap { subtitle in
            guard let subtitleURL = Self.makeURL(subtitle.url) else { return nil }
            return ExternalSubtitleTrack(
                url: subtitleURL,
                name: subtitle.name,
                language: subtitle.language,
                httpHeaders: subtitle.headers
            )
        }
        loadOptions.autoplay = wantsPlayback

        loadTask = Task { [weak self] in
            do {
                try await engine.load(url: url, startPosition: startSeconds, options: loadOptions)
                guard let self, self.loadGeneration == generation else { return }
                self.isLoadInFlight = false
                self.sessionStarted()
            } catch is CancellationError {
                // Superseded by a newer load or a stop: the successor owns the state.
                guard let self, self.loadGeneration == generation else { return }
                self.isLoadInFlight = false
            } catch {
                guard let self, self.loadGeneration == generation else { return }
                self.isLoadInFlight = false
                self.loadError = error.localizedDescription
            }
        }
    }

    private func sessionStarted() {
        guard let engine else { return }
        engine.videoGravity = videoGravity
        engine.setSoftwareSubtitleDelay(subtitleDelaySeconds)
        if desiredRate != 1 { engine.setRate(desiredRate) }
        if wantsPlayback { engine.play() } else { engine.pause() }
        let sidecars = pendingSidecarURLs
        pendingSidecarURLs.removeAll()
        sidecars.forEach { addSidecarSubtitle(url: $0) }
        sessionLayerChanged()
    }

    // MARK: - Transport

    public func play() {
        wantsPlayback = true
        pausedForBackground = false
        guard let engine, !isLoadInFlight else { return }
        engine.play()
    }

    public func pause() {
        wantsPlayback = false
        guard let engine, !isLoadInFlight else { return }
        engine.pause()
    }

    public func seek(toMs positionMs: Int64) {
        guard let engine else { return }
        let seconds = max(0, Double(positionMs) / 1000)
        // An ended session is terminal in AetherEngine: seeking back reopens the stream there.
        if engine.state == .ended || (engine.state == .idle && !isLoadInFlight && currentURL != nil) {
            startLoad(startSeconds: seconds)
            return
        }
        Task { await engine.seek(to: seconds) }
    }

    public func seek(byMs offsetMs: Int64) {
        guard let engine else { return }
        var target = engine.currentTime + Double(offsetMs) / 1000
        if engine.duration > 0 { target = min(target, engine.duration) }
        seek(toMs: Int64(max(0, target) * 1000))
    }

    public func setPlaybackRate(_ rate: Float) {
        desiredRate = rate > 0 ? rate : 1
        engine?.setRate(desiredRate)
    }

    public func setMuted(_ muted: Bool) {
        engine?.volume = muted ? 0 : 1
    }

    /// 0 = fit, 1 = fill, 2 = zoom (Nuvio's resize modes).
    public func setResizeMode(_ mode: Int) {
        videoGravity = mode == 0 ? .resizeAspect : .resizeAspectFill
        engine?.videoGravity = videoGravity
        updateVideoRect()
    }

    public func stop() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoadInFlight = false
        cancellables.removeAll()
        pictureInPicture?.invalidate()
        pictureInPicture = nil
        subtitleOverlay.show([])
        engine?.stop()
        engine?.unbind(view: playerView)
    }

    // MARK: - State (polled by Kotlin every 250 ms)

    public var isLoading: Bool {
        guard let engine else { return false }
        if isLoadInFlight { return true }
        switch engine.playbackPhase {
        case .loading, .seeking, .rebuffering, .stalled:
            return true
        default:
            return false
        }
    }

    public var isPlaying: Bool { engine?.state == .playing }
    public var isEnded: Bool { engine?.state == .ended }
    public var durationMs: Int64 { Self.milliseconds(engine?.duration) }
    public var positionMs: Int64 { Self.milliseconds(engine?.currentTime) }
    public var bufferedMs: Int64 { max(positionMs, Self.milliseconds(engine?.bufferedPosition)) }

    public var playbackRate: Float {
        guard let engine else { return desiredRate }
        return min(desiredRate, engine.maxSupportedRate)
    }

    public var errorMessage: String? {
        if let engineInitError { return engineInitError }
        if let loadError { return loadError }
        if case .error(let message)? = engine?.state { return message }
        return nil
    }

    public var keepsPlaybackInBackground: Bool { pictureInPicture?.keepsPlaybackAlive == true }

    // MARK: - Tracks

    public var audioTracks: [NuvioAetherTrack] {
        guard let engine else { return [] }
        let source = engine.audioTracks
        let active = engine.activeAudioTrackIndex
        if let cache = audioTrackCache, cache.source == source, cache.active == active { return cache.tracks }
        let tracks = source.enumerated().map { position, track in
            NuvioAetherTrack(
                id: track.id,
                title: AetherTrackLabels.audioTitle(track, position: position),
                language: track.language ?? "",
                isSelected: track.id == active
            )
        }
        audioTrackCache = (source, active, tracks)
        return tracks
    }

    public var subtitleTracks: [NuvioAetherTrack] {
        guard let engine else { return [] }
        let source = engine.subtitleTracks
        let active = engine.isSubtitleActive ? engine.activeSubtitleTrackIndex : nil
        if let cache = subtitleTrackCache, cache.source == source, cache.active == active { return cache.tracks }
        let tracks = source.enumerated().map { position, track in
            NuvioAetherTrack(
                id: track.id,
                title: AetherTrackLabels.subtitleTitle(track, position: position),
                language: track.language ?? "",
                isSelected: track.id == active
            )
        }
        subtitleTrackCache = (source, active, tracks)
        return tracks
    }

    public func selectAudioTrack(id: Int) {
        guard let engine, engine.activeAudioTrackIndex != id else { return }
        guard engine.audioTracks.contains(where: { $0.id == id }) else { return }
        engine.selectAudioTrack(index: id)
    }

    /// Picks the first track matching the ordered `languages`, unless the active track already
    /// speaks that language. Used after load: the initial pick already happened inside `load`.
    public func applyAudioLanguagePreferences(_ languages: [String]) {
        preferredAudioLanguages = languages
        guard let engine, !isLoadInFlight, !engine.audioTracks.isEmpty else { return }
        let targets = languages.compactMap { AetherTrackLabels.normalizedLanguage($0) }
        for target in targets {
            let matching = engine.audioTracks.filter { AetherTrackLabels.normalizedLanguage($0.language) == target }
            guard let best = matching.first(where: { !$0.isCommentary }) ?? matching.first else { continue }
            let active = engine.audioTracks.first { $0.id == engine.activeAudioTrackIndex }
            if AetherTrackLabels.normalizedLanguage(active?.language) != target {
                engine.selectAudioTrack(index: best.id)
            }
            return
        }
    }

    /// `id` < 0 turns subtitles off.
    public func selectSubtitleTrack(id: Int) {
        guard let engine else { return }
        if id < 0 {
            engine.clearSubtitle()
        } else if engine.subtitleTracks.contains(where: { $0.id == id }) {
            engine.selectSubtitleTrack(index: id)
        }
        subtitleOverlay.show([])
    }

    /// Registers an addon subtitle file as a track and selects it.
    public func addSidecarSubtitle(url: String) {
        guard let engine else { return }
        if isLoadInFlight {
            pendingSidecarURLs.append(url)
            return
        }
        guard let subtitleURL = Self.makeURL(url) else { return }
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: subtitleURL))
        addedSidecarTrackIDs.append(track.id)
        engine.selectSubtitleTrack(index: track.id)
        subtitleOverlay.show([])
    }

    /// Unregisters addon subtitles, then selects `id` (< 0: subtitles off).
    public func removeSidecarSubtitles(thenSelect id: Int) {
        guard let engine else { return }
        pendingSidecarURLs.removeAll()
        for trackID in addedSidecarTrackIDs where trackID != id {
            engine.removeExternalSubtitleTrack(id: trackID)
        }
        addedSidecarTrackIDs.removeAll { $0 != id }
        selectSubtitleTrack(id: id)
    }

    public func setSubtitleDelay(milliseconds: Int) {
        subtitleDelaySeconds = Double(max(-60_000, min(60_000, milliseconds))) / 1000
        engine?.setSoftwareSubtitleDelay(subtitleDelaySeconds)
        refreshSubtitles()
    }

    // MARK: - Media info (mpv property names, so Nuvio's media-info panel reads it unchanged)

    public func mpvProperty(_ name: String) -> String? {
        guard let engine else { return nil }
        let audio = engine.audioTracks.first { $0.id == engine.activeAudioTrackIndex }
        switch name {
        case "current-tracks/video/codec":
            return engine.sourceVideoCodecName
        case "video-params/w":
            return engine.sourceVideoWidth > 0 ? String(engine.sourceVideoWidth) : nil
        case "video-params/h":
            return engine.sourceVideoHeight > 0 ? String(engine.sourceVideoHeight) : nil
        case "container-fps":
            return engine.sourceVideoFrameRate.map { String($0) }
        case "video-bitrate":
            return engine.sourceVideoBitrate > 0 ? String(engine.sourceVideoBitrate) : nil
        case "current-tracks/video/dolby-vision-profile":
            return engine.sourceDVProfile.map { String($0) }
        case "video-params/gamma":
            switch engine.sourceVideoFormat {
            case .hdr10, .hdr10Plus: return "pq"
            case .dolbyVision: return engine.sourceDVProfile == 5 ? nil : "pq"
            case .hlg: return "hlg"
            default: return nil
            }
        case "video-params/pixelformat":
            if let format = engine.sourceVideoStreamFormat {
                return format.pixelFormat ?? format.bitDepth.map { "yuv420p\($0)" }
            }
            return nil
        case "current-tracks/audio/codec":
            return audio?.codec
        case "current-tracks/audio/codec-profile":
            if audio?.isAtmos == true { return "Dolby Atmos" }
            if audio?.isDTSX == true { return "DTS:X" }
            return audio?.profile
        case "audio-params/channel-count":
            return audio.flatMap { $0.channels > 0 ? String($0.channels) : nil }
        case "audio-params/samplerate":
            return audio.flatMap { $0.sampleRate > 0 ? String($0.sampleRate) : nil }
        default:
            return nil
        }
    }

    // MARK: - Background (same policy as the MPV player: pause unless PiP takes over)

    public func applicationDidEnterBackground() {
        guard let pictureInPicture else { return pauseForBackground() }
        if pictureInPicture.keepsPlaybackAlive { return }
        guard isPlaying, pictureInPicture.isPossible else { return pauseForBackground() }
        // Automatic PiP can start after didEnterBackground: give it a moment before pausing.
        backgroundGeneration += 1
        let generation = backgroundGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.backgroundGeneration == generation,
                  UIApplication.shared.applicationState == .background,
                  self.pictureInPicture?.keepsPlaybackAlive != true else { return }
            self.pauseForBackground()
        }
    }

    public func applicationWillEnterForeground() {
        backgroundGeneration += 1
        guard let engine else { return }
        let resume = pausedForBackground
        pausedForBackground = false
        if engine.needsForegroundVideoRestore {
            // The background policy released the video item; rebuild it where it stopped.
            Task { [weak self] in
                _ = try? await engine.reloadAtCurrentPosition(applying: { _ in })
                if resume { self?.play() }
            }
        } else if resume {
            play()
        }
    }

    private func pauseForBackground() {
        guard isPlaying || (isLoadInFlight && wantsPlayback) else { return }
        pause()
        pausedForBackground = true
    }

    // MARK: - Subtitles and layout

    private func refreshSubtitles() {
        guard let engine else { return }
        let time = engine.sourceTime - subtitleDelaySeconds
        let active = engine.subtitleCues.filter { $0.startTime <= time && time < $0.endTime }
        subtitleOverlay.show(active)
    }

    private func sessionLayerChanged() {
        pictureInPicture?.refresh()
        updateVideoRect()
    }

    private func pictureInPictureChanged(_ active: Bool) {
        if let engine, options.nativeSubtitles {
            // Subtitles in the PiP window come from the native rendition of the selected track
            // (the software path composites them into the frames by itself).
            if active, let selected = engine.subtitleTracks.first(where: { $0.id == engine.activeSubtitleTrackIndex }) {
                let language = AetherTrackLabels.normalizedLanguage(selected.language)
                let rendition = engine.nativeSubtitleTracks.first {
                    AetherTrackLabels.normalizedLanguage($0.language) == language
                }
                engine.setNativeSubtitleSelected(track: rendition?.ordinal)
            } else {
                engine.setNativeSubtitleSelected(track: nil)
            }
        }
        onPictureInPictureChange?(active)
    }

    private func updateVideoRect() {
        guard let engine else { return }
        let bounds = containerView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        if let layer = engine.nativePlayerLayer, layer.superlayer != nil, layer.videoRect.width > 1 {
            subtitleOverlay.videoRect = layer.videoRect
            return
        }
        let pictureSize: CGSize
        if let displaySize = engine.softwareDisplaySize {
            pictureSize = displaySize
        } else {
            pictureSize = CGSize(
                width: Double(engine.sourceVideoWidth) * engine.sourceVideoPixelAspectRatio,
                height: Double(engine.sourceVideoHeight)
            )
        }
        guard pictureSize.width > 0, pictureSize.height > 0 else {
            subtitleOverlay.videoRect = bounds
            return
        }
        let fitScale = min(bounds.width / pictureSize.width, bounds.height / pictureSize.height)
        let fillScale = max(bounds.width / pictureSize.width, bounds.height / pictureSize.height)
        let scale = videoGravity == .resizeAspectFill ? fillScale : fitScale
        let size = CGSize(width: pictureSize.width * scale, height: pictureSize.height * scale)
        subtitleOverlay.videoRect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Helpers

    private static func milliseconds(_ seconds: Double?) -> Int64 {
        guard let seconds, seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(seconds * 1000)
    }

    private static func makeURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed) }
        return trimmed
            .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            .flatMap(URL.init(string:))
    }
}

/// Reports its layout passes so the subtitle overlay can follow the picture's rectangle.
@MainActor
private final class AetherContainerView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
