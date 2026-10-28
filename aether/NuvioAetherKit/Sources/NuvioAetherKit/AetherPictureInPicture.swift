import AVKit
import CoreMedia
import UIKit
internal import AetherEngine

/// Picture in Picture for AetherEngine sessions. The engine swaps the layer it presents on per
/// session: an `AVPlayerLayer` on the native path, an `AVSampleBufferDisplayLayer` on the software
/// path, so the controller is rebuilt around whichever one the current session uses.
@MainActor
final class AetherPictureInPicture: NSObject, AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate {

    private weak var engine: AetherEngine?
    private var controller: AVPictureInPictureController?
    private var presentedLayer: ObjectIdentifier?

    private(set) var isStarting = false
    private(set) var isActive = false
    var keepsPlaybackAlive: Bool { isStarting || isActive }
    var isPossible: Bool { controller?.isPictureInPicturePossible == true }

    /// PiP window state, for the host's "playing in Picture in Picture" placeholder.
    var onActiveChange: ((Bool) -> Void)?
    /// Play / pause / skip from the software-path PiP window, routed like other system controls.
    var onSetPlaying: ((Bool) -> Void)?
    var onSkip: ((Double) -> Void)?
    /// The window was closed while the app is in the background.
    var onStoppedInBackground: (() -> Void)?

    init(engine: AetherEngine) {
        self.engine = engine
        super.init()
    }

    /// Follows the layer of the current session. Never swaps a controller that is presenting.
    func refresh() {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let engine else { return }
        guard !keepsPlaybackAlive else { return }

        if let playerLayer = engine.nativePlayerLayer {
            guard presentedLayer != ObjectIdentifier(playerLayer) else { return }
            install(AVPictureInPictureController(playerLayer: playerLayer), layer: playerLayer)
        } else if let source = engine.softwarePiPSource {
            guard presentedLayer != ObjectIdentifier(source.layer) else { return }
            let contentSource = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: source.layer,
                playbackDelegate: self
            )
            install(AVPictureInPictureController(contentSource: contentSource), layer: source.layer)
        }
    }

    func invalidate() {
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        controller?.delegate = nil
        controller = nil
        presentedLayer = nil
        setActive(false, starting: false)
    }

    private func install(_ newController: AVPictureInPictureController?, layer: CALayer) {
        controller?.delegate = nil
        controller = newController
        presentedLayer = newController == nil ? nil : ObjectIdentifier(layer)
        newController?.delegate = self
        newController?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    private func setActive(_ active: Bool, starting: Bool) {
        let wasPresenting = isActive || isStarting
        isActive = active
        isStarting = starting
        engine?.pictureInPictureActive = active || starting
        if wasPresenting != (active || starting) {
            onActiveChange?(active || starting)
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setActive(false, starting: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setActive(true, starting: false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   failedToStartPictureInPictureWithError error: Error) {
        setActive(false, starting: false)
        if UIApplication.shared.applicationState == .background {
            onStoppedInBackground?()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setActive(false, starting: false)
        if UIApplication.shared.applicationState == .background {
            onStoppedInBackground?()
        }
        refresh()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate (software path)

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        if let onSetPlaying {
            onSetPlaying(playing)
        } else {
            engine?.softwarePiPSource?.setPlaying(playing)
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        engine?.softwarePiPSource?.timeRange()
            ?? CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        engine?.softwarePiPSource?.isPaused ?? true
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        let seconds = CMTimeGetSeconds(skipInterval)
        if let onSkip {
            onSkip(seconds)
        } else {
            engine?.softwarePiPSource?.skip(by: seconds)
        }
        completionHandler()
    }
}
