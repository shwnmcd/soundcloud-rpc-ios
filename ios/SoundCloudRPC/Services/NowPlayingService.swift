import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingService: ObservableObject {
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onSeekFraction: ((Double) -> Void)?

    private var lastArtworkURL: String = ""
    private var cachedArtwork: MPMediaItemArtwork?
    private var lastDuration: TimeInterval = 0
    private var lastTrackKey: String = ""
    private var lastIsPlaying: Bool = false
    private var lastReportedElapsed: TimeInterval = 0
    private var lastUpdateTimestamp: Date = .distantPast

    init() {
        setupRemoteCommands()
    }

    func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        // Explicitly DISABLE 10-second skip commands so iOS Lock Screen shows Previous (⏮) and Next (⏭) like Spotify / Apple Music!
        cc.skipBackwardCommand.isEnabled = false
        cc.skipForwardCommand.isEnabled = false
        cc.seekBackwardCommand.isEnabled = false
        cc.seekForwardCommand.isEnabled = false

        cc.playCommand.removeTarget(nil)
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        cc.pauseCommand.removeTarget(nil)
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlayPause?() }
            return .success
        }

        cc.nextTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNextTrack?() }
            return .success
        }

        cc.previousTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPreviousTrack?() }
            return .success
        }

        // Enable interactive Lock Screen timeline scrubbing!
        cc.changePlaybackPositionCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                guard let self = self, self.lastDuration > 0 else { return }
                let targetTime = max(0, min(self.lastDuration, posEvent.positionTime))
                let fraction = targetTime / self.lastDuration
                self.lastReportedElapsed = targetTime
                self.lastUpdateTimestamp = Date()

                // Immediately reflect scrubbed position on Lock Screen for instant feedback
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = targetTime
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
                self.onSeekFraction?(fraction)
            }
            return .success
        }
    }

    /// Re-assert skip/scrub button layout (WKWebView's internal media player can occasionally re-enable skip 10s commands)
    private func enforceLockScreenCommandLayout() {
        let cc = MPRemoteCommandCenter.shared()
        if cc.skipBackwardCommand.isEnabled { cc.skipBackwardCommand.isEnabled = false }
        if cc.skipForwardCommand.isEnabled { cc.skipForwardCommand.isEnabled = false }
        if !cc.nextTrackCommand.isEnabled { cc.nextTrackCommand.isEnabled = true }
        if !cc.previousTrackCommand.isEnabled { cc.previousTrackCommand.isEnabled = true }
        if !cc.changePlaybackPositionCommand.isEnabled { cc.changePlaybackPositionCommand.isEnabled = true }
    }

    func update(with track: TrackInfo, useTrackParser: Bool) {
        guard !track.isEmpty else { return }

        enforceLockScreenCommandLayout()

        let normalized = TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: useTrackParser
        )

        let trackKey = "\(normalized.artist)::\(normalized.track)::\(track.url)"
        let duration = track.durationSeconds
        let elapsed = track.elapsedSeconds
        self.lastDuration = duration

        // Avoid redundant per-second writes that cause Lock Screen scrubber jitter;
        // update when track changes, play/pause changes, duration changes, or elapsed drifts > 2.5s (seek/loop)
        let predictedElapsed = lastIsPlaying
            ? lastReportedElapsed + Date().timeIntervalSince(lastUpdateTimestamp)
            : lastReportedElapsed
        let drift = abs(elapsed - predictedElapsed)
        let needsUpdate = (trackKey != lastTrackKey)
            || (track.isPlaying != lastIsPlaying)
            || (drift > 2.5)
            || (Date().timeIntervalSince(lastUpdateTimestamp) > 12)

        guard needsUpdate else { return }

        lastTrackKey = trackKey
        lastIsPlaying = track.isPlaying
        lastReportedElapsed = elapsed
        lastUpdateTimestamp = Date()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: normalized.track,
            MPMediaItemPropertyArtist: normalized.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: track.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
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
            // Non-fatal
        }
    }
}
