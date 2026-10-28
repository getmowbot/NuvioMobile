import Foundation

/// What `PlayerNowPlayingController` needs from a player, so MPV and AetherEngine share it.
protocol PlayerNowPlayingOwner: AnyObject {
    var isPlayerPlaying: Bool { get }
    func requestSystemPlaying(_ playing: Bool)
    func requestSystemSeekTo(_ positionMs: Int64)
    func requestSystemSeekBy(_ offsetMs: Int64, exact: Bool)
}

extension MPVPlayerViewController: PlayerNowPlayingOwner {}
