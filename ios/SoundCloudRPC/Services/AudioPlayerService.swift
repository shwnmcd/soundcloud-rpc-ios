import Foundation
import AVFoundation
import MediaPlayer

enum RepeatMode: String, CaseIterable {
    case none
    case all
    case one
}

/// 100% Native AVPlayer Audio Engine — zero ads, instant tap-to-play, millisecond seeking, full background queue!
@MainActor
final class AudioPlayerService: ObservableObject {
    @Published private(set) var currentTrack: SCTrack?
    @Published private(set) var queue: [SCTrack] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoadingTrack: Bool = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var durationSeconds: TimeInterval = 0
    @Published var isShuffling: Bool = false
    @Published var repeatMode: RepeatMode = .none
    /// Tracks last directional skip (-1 = previous, +1 = next) for silky UI transitions
    @Published private(set) var lastSkipDirection: Int = 1

    private var player: AVPlayer = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var originalQueue: [SCTrack] = []

    weak var api: SoundCloudAPI?
    weak var settings: AppSettings?
    weak var nowPlaying: NowPlayingService?
    weak var lastFm: LastFmService?
    weak var webhooks: WebhookService?

    /// Prevents infinite ping-pong loops when applying incoming Jam sync state
    var isApplyingRemoteJamSync: Bool = false
    /// Invoked whenever local playback changes (action, optional seekSeconds) so JamSessionService broadcasts instantly
    var onLocalPlaybackEvent: ((String, Double?) -> Void)?

    var progressFraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, elapsedSeconds / durationSeconds))
    }

    var currentTrackInfo: TrackInfo {
        guard let track = currentTrack else { return TrackInfo() }
        let liked = api?.likedTrackIds.contains(track.id) ?? false
        return track.toTrackInfo(
            elapsed: elapsedSeconds,
            isPlaying: isPlaying,
            isLiked: liked,
            isShuffling: isShuffling,
            repeatMode: repeatMode.rawValue
        )
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        setupPeriodicTimeObserver()
    }

    func bindServices(
        api: SoundCloudAPI,
        settings: AppSettings,
        nowPlaying: NowPlayingService,
        lastFm: LastFmService,
        webhooks: WebhookService
    ) {
        self.api = api
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.lastFm = lastFm
        self.webhooks = webhooks

        nowPlaying.onPlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNextTrack = { [weak self] in self?.nextTrack() }
        nowPlaying.onPreviousTrack = { [weak self] in self?.previousTrack() }
        nowPlaying.onSeekFraction = { [weak self] frac in self?.seek(toFraction: frac) }
    }

    func play(track: SCTrack, in list: [SCTrack]? = nil, shuffle: Bool = false) {
        let tracks = (list?.isEmpty == false) ? list! : [track]
        originalQueue = tracks

        if shuffle {
            isShuffling = true
            var rest = tracks.filter { $0.id != track.id }
            rest.shuffle()
            queue = [track] + rest
            currentIndex = 0
        } else {
            isShuffling = false
            queue = tracks
            currentIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        }

        Task {
            await loadAndPlayTrack(at: currentIndex)
        }
    }

    func playShuffled(list: [SCTrack]) {
        guard !list.isEmpty else { return }
        originalQueue = list
        isShuffling = true
        queue = list.shuffled()
        currentIndex = 0
        Task {
            await loadAndPlayTrack(at: 0)
        }
    }

    private func loadAndPlayTrack(
        at index: Int,
        initialSeekSeconds: TimeInterval? = nil,
        shouldAutoPlay: Bool = true,
        notifyJam: Bool = true
    ) async {
        guard queue.indices.contains(index) else { return }
        let track = queue[index]
        currentIndex = index
        currentTrack = track
        elapsedSeconds = initialSeekSeconds ?? 0
        durationSeconds = max(1, track.durationSeconds)
        isLoadingTrack = true

        guard let streamURL = await api?.resolveStreamURL(for: track) else {
            isLoadingTrack = false
            // Auto-skip unplayable snippet/geoblocked tracks if more exist
            if !isApplyingRemoteJamSync && index + 1 < queue.count {
                await loadAndPlayTrack(at: index + 1)
            }
            return
        }

        // Remove previous end observer
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }

        let item = AVPlayerItem(url: streamURL)
        player.replaceCurrentItem(with: item)

        // Ensure AVAudioSession is active so remote Jam audio plays immediately out loud!
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        if shouldAutoPlay {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }

        // Non-blocking seek after playback starts so HLS items never deadlock a continuation!
        if let targetSec = initialSeekSeconds, targetSec > 0.5 {
            elapsedSeconds = targetSec
            let cmTime = CMTime(seconds: targetSec, preferredTimescale: 600)
            let tol = CMTime(seconds: 0.6, preferredTimescale: 600)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.player.currentItem === item else { return }
                self.player.seek(to: cmTime, toleranceBefore: tol, toleranceAfter: tol) { _ in
                    if shouldAutoPlay {
                        self.player.play()
                    }
                }
            }
        }
        isLoadingTrack = false

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleTrackFinished()
            }
        }

        syncExternalServices(forceLockScreen: true)
        if notifyJam && !isApplyingRemoteJamSync {
            onLocalPlaybackEvent?("track", elapsedSeconds)
        }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        syncExternalServices(forceLockScreen: true)
        if !isApplyingRemoteJamSync {
            onLocalPlaybackEvent?(isPlaying ? "play" : "pause", elapsedSeconds)
        }
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        lastSkipDirection = 1
        if currentIndex + 1 < queue.count {
            Task { await loadAndPlayTrack(at: currentIndex + 1) }
        } else if repeatMode == .all {
            Task { await loadAndPlayTrack(at: 0) }
        }
    }

    func previousTrack(forcePrevious: Bool = false) {
        guard !queue.isEmpty else { return }
        lastSkipDirection = -1
        // On button tap: if > 3s into song, restart song; on explicit swipe-left: always go back a song!
        if !forcePrevious && elapsedSeconds > 3.0 {
            seek(toFraction: 0)
            return
        }
        if currentIndex > 0 {
            Task { await loadAndPlayTrack(at: currentIndex - 1) }
        } else if repeatMode == .all {
            Task { await loadAndPlayTrack(at: queue.count - 1) }
        } else {
            seek(toFraction: 0)
        }
    }

    func seek(toFraction fraction: Double) {
        let clamped = min(1.0, max(0.0, fraction))
        guard durationSeconds > 0 else { return }
        seek(toSeconds: durationSeconds * clamped, notifyJam: true)
    }

    func seek(toSeconds targetSec: TimeInterval, notifyJam: Bool = true) {
        let clampedSec = max(0, min(durationSeconds > 0 ? durationSeconds : targetSec, targetSec))
        elapsedSeconds = clampedSec
        let cmTime = CMTime(seconds: clampedSec, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.syncExternalServices(forceLockScreen: true)
            }
        }
        if notifyJam && !isApplyingRemoteJamSync {
            onLocalPlaybackEvent?("seek", clampedSec)
        }
    }

    /// Appends a track to the live queue (used by Jam collaborative queue & Up Next)
    func appendToQueue(_ track: SCTrack) {
        if queue.isEmpty {
            play(track: track, in: [track])
            return
        }
        if !queue.contains(where: { $0.id == track.id }) {
            queue.append(track)
            originalQueue.append(track)
        }
    }

    /// Applies an authoritative Jam playback snapshot from a remote Host with millisecond drift sync!
    func applyRemoteJamState(
        track: SCTrack,
        queueTracks: [SCTrack],
        shouldPlay: Bool,
        targetPositionSec: TimeInterval
    ) async {
        isApplyingRemoteJamSync = true
        defer { isApplyingRemoteJamSync = false }

        let mergedQueue = queueTracks.isEmpty ? [track] : queueTracks
        self.queue = mergedQueue
        self.originalQueue = mergedQueue
        let idx = mergedQueue.firstIndex(where: { $0.id == track.id }) ?? 0

        if currentTrack?.id != track.id {
            await loadAndPlayTrack(
                at: idx,
                initialSeekSeconds: targetPositionSec,
                shouldAutoPlay: shouldPlay,
                notifyJam: false
            )
        } else {
            currentIndex = idx
            if abs(elapsedSeconds - targetPositionSec) > 1.8 {
                seek(toSeconds: targetPositionSec, notifyJam: false)
            }
            if shouldPlay && (!isPlaying || player.timeControlStatus != .playing) {
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
                isPlaying = true
                syncExternalServices(forceLockScreen: true)
            } else if !shouldPlay && isPlaying {
                player.pause()
                isPlaying = false
                syncExternalServices(forceLockScreen: true)
            }
        }
    }

    func toggleShuffle() {
        isShuffling.toggle()
        guard let current = currentTrack else { return }
        if isShuffling {
            var rest = originalQueue.filter { $0.id != current.id }
            rest.shuffle()
            queue = [current] + rest
            currentIndex = 0
        } else {
            queue = originalQueue
            currentIndex = originalQueue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .none: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .none
        }
    }

    func toggleLikeCurrent() {
        guard let track = currentTrack else { return }
        Task {
            _ = await api?.toggleLike(track: track)
        }
    }

    private func handleTrackFinished() {
        if repeatMode == .one {
            seek(toFraction: 0)
            player.play()
            isPlaying = true
            return
        }
        if currentIndex + 1 < queue.count {
            Task { await loadAndPlayTrack(at: currentIndex + 1) }
        } else if repeatMode == .all, !queue.isEmpty {
            Task { await loadAndPlayTrack(at: 0) }
        } else {
            isPlaying = false
            syncExternalServices(forceLockScreen: true)
        }
    }

    private func setupPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.35, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && sec >= 0 {
                    self.elapsedSeconds = sec
                }
                if let itemDur = self.player.currentItem?.duration {
                    let durSec = CMTimeGetSeconds(itemDur)
                    if durSec.isFinite && durSec > 0 {
                        self.durationSeconds = durSec
                    }
                }
                self.syncExternalServices(forceLockScreen: false)
            }
        }
    }

    private func syncExternalServices(forceLockScreen: Bool) {
        guard let settings = settings else { return }
        let info = currentTrackInfo
        guard !info.isEmpty else { return }

        nowPlaying?.update(with: info, useTrackParser: settings.trackParserEnabled)
        if forceLockScreen || Int(elapsedSeconds) % 3 == 0 {
            Task {
                await lastFm?.updateTrackInfo(info, settings: settings)
                await webhooks?.updateTrackInfo(info, settings: settings)
            }
        }
    }
}
