import Foundation

@MainActor
final class WebhookService: ObservableObject {
    @Published private(set) var lastWebhookStatus: String = ""
    @Published private(set) var sentCount: Int = 0

    private struct WebhookState {
        var artist: String
        var track: String
        var startTime: Date
        var duration: TimeInterval
        var webhookSent: Bool
        var originUrl: String
        var trackArt: String
        var isPaused: Bool
        var pausedTime: TimeInterval
    }

    private var currentState: WebhookState?
    private var pauseStartTime: Date?
    private var scheduledTask: Task<Void, Never>?

    func updateTrackInfo(_ trackInfo: TrackInfo, settings: AppSettings) async {
        // Optional Desktop Discord RPC Relay (real-time playback state)
        if settings.discordRichPresence, !settings.rpcRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await sendRpcRelay(trackInfo: trackInfo, settings: settings)
        }

        guard settings.webhookEnabled else { return }
        guard !trackInfo.title.isEmpty, !trackInfo.author.isEmpty else { return }

        let normalized = TrackParser.normalizeTrackInfo(
            titleFromPage: trackInfo.title,
            authorFromPage: trackInfo.author,
            useTrackParser: settings.trackParserEnabled
        )

        if var state = currentState {
            if !trackInfo.isPlaying && !state.isPaused {
                state.isPaused = true
                pauseStartTime = Date()
                scheduledTask?.cancel()
                scheduledTask = nil
            } else if trackInfo.isPlaying && state.isPaused {
                state.isPaused = false
                if let pStart = pauseStartTime {
                    state.pausedTime += Date().timeIntervalSince(pStart)
                }
                pauseStartTime = nil
                currentState = state
                scheduleWebhook(settings: settings)
            }
            currentState = state
        }

        let elapsed = trackInfo.elapsedSeconds
        let isLoop: Bool = {
            guard let state = currentState else { return false }
            return state.artist == normalized.artist && state.track == normalized.track && elapsed <= 3
        }()

        if currentState == nil ||
            currentState?.artist != normalized.artist ||
            currentState?.track != normalized.track ||
            isLoop {
            if let old = currentState, !old.isPaused, !old.webhookSent,
               shouldSendWebhook(old, triggerPercentage: settings.webhookTriggerPercentage) {
                await sendWebhook(
                    artist: old.artist,
                    track: old.track,
                    duration: Int(old.duration),
                    originUrl: old.originUrl,
                    trackArt: old.trackArt,
                    settings: settings
                )
            }

            scheduledTask?.cancel()
            currentState = WebhookState(
                artist: normalized.artist,
                track: normalized.track,
                startTime: Date(),
                duration: max(1, trackInfo.durationSeconds),
                webhookSent: false,
                originUrl: trackInfo.url,
                trackArt: trackInfo.highResArtwork,
                isPaused: !trackInfo.isPlaying,
                pausedTime: 0
            )

            if !trackInfo.isPlaying {
                pauseStartTime = Date()
            } else {
                scheduleWebhook(settings: settings)
            }
        }
    }

    func sendTestWebhook(settings: AppSettings) async {
        await sendWebhook(
            artist: "Daft Punk",
            track: "Instant Crush (Test Track)",
            duration: 337,
            originUrl: "https://soundcloud.com",
            trackArt: "https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8fe7.png",
            settings: settings,
            ignoreEnabledCheck: true
        )
    }

    private func shouldSendWebhook(_ state: WebhookState, triggerPercentage: Double) -> Bool {
        let totalElapsed = Date().timeIntervalSince(state.startTime)
        let played = totalElapsed - state.pausedTime
        let required = state.duration * (max(0, min(100, triggerPercentage)) / 100.0)
        return !state.webhookSent && played >= required
    }

    private func scheduleWebhook(settings: AppSettings) {
        scheduledTask?.cancel()
        guard let state = currentState, !state.webhookSent, !state.isPaused else { return }

        let required = state.duration * (max(0, min(100, settings.webhookTriggerPercentage)) / 100.0)
        let alreadyPlayed = Date().timeIntervalSince(state.startTime) - state.pausedTime
        let remaining = max(0.5, required - alreadyPlayed)

        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled, let self = self else { return }
            guard var active = self.currentState, !active.isPaused, !active.webhookSent else { return }
            active.webhookSent = true
            self.currentState = active
            await self.sendWebhook(
                artist: active.artist,
                track: active.track,
                duration: Int(active.duration),
                originUrl: active.originUrl,
                trackArt: active.trackArt,
                settings: settings
            )
        }
    }

    private func sendWebhook(
        artist: String,
        track: String,
        duration: Int,
        originUrl: String,
        trackArt: String,
        settings: AppSettings,
        ignoreEnabledCheck: Bool = false
    ) async {
        guard ignoreEnabledCheck || settings.webhookEnabled else { return }
        let urlString = settings.webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            lastWebhookStatus = "Invalid webhook URL"
            return
        }

        let isoTimestamp = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any]

        let isDiscordWebhook = settings.webhookDiscordFormat || urlString.contains("discord.com/api/webhooks")
        if isDiscordWebhook {
            payload = [
                "username": "SoundCloud RPC",
                "embeds": [[
                    "title": track,
                    "description": "by **\(artist)**",
                    "url": originUrl.isEmpty ? "https://soundcloud.com" : originUrl,
                    "color": 16733440, // SoundCloud Orange #FF5500
                    "thumbnail": ["url": trackArt],
                    "footer": ["text": "SoundCloud RPC for iOS • \(TrackTimeParser.format(TimeInterval(duration)))"],
                    "timestamp": isoTimestamp
                ]]
            ]
        } else {
            // Exact payload format from richardhbtz/soundcloud-rpc
            payload = [
                "timestamp": isoTimestamp,
                "artist": artist,
                "track": track,
                "duration": duration,
                "originUrl": originUrl,
                "trackArt": trackArt
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                sentCount += 1
                lastWebhookStatus = "Sent (\(http.statusCode)): \(artist) – \(track)"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                lastWebhookStatus = "Webhook failed (HTTP \(code))"
            }
        } catch {
            lastWebhookStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func sendRpcRelay(trackInfo: TrackInfo, settings: AppSettings) async {
        let urlString = settings.rpcRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return }

        let normalized = TrackParser.normalizeTrackInfo(
            titleFromPage: trackInfo.title,
            authorFromPage: trackInfo.author,
            useTrackParser: settings.trackParserEnabled
        )

        let body: [String: Any] = [
            "isPlaying": trackInfo.isPlaying,
            "title": normalized.track,
            "author": normalized.artist,
            "artwork": trackInfo.highResArtwork,
            "elapsed": trackInfo.elapsed,
            "duration": trackInfo.duration,
            "url": trackInfo.url,
            "displayWhenPaused": settings.displayWhenPaused,
            "displaySmallIcon": settings.displaySmallIcon,
            "displayButtons": settings.displayButtons,
            "useArtistInStatusLine": settings.useArtistInStatusLine
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }
}
