import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingService: ObservableObject {
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?

    private var lastArtworkURL: String = ""
    private var cachedArtwork: MPMediaItemArtwork?

    init() {
        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextTrack?() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousTrack?() }
            return .success
        }
    }

    func update(with track: TrackInfo, useTrackParser: Bool) {
        guard !track.isEmpty else { return }

        let normalized = TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: useTrackParser
        )

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: normalized.track,
            MPMediaItemPropertyArtist: normalized.artist,
            MPMediaItemPropertyPlaybackDuration: track.durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: track.elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: track.isPlaying ? 1.0 : 0.0
        ]

        if let artwork = cachedArtwork, lastArtworkURL == track.highResArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if !track.highResArtwork.isEmpty, track.highResArtwork != lastArtworkURL {
            lastArtworkURL = track.highResArtwork
            Task {
                await fetchArtwork(from: track.highResArtwork, baseInfo: info)
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func fetchArtwork(from urlString: String, baseInfo: [String: Any]) async {
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.cachedArtwork = artwork
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        } catch {
            // Non-fatal: keep text metadata without artwork
        }
    }
}
