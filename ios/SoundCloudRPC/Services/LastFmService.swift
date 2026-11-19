import Foundation
import CryptoKit

@MainActor
final class LastFmService: ObservableObject {
    @Published private(set) var lastScrobbleStatus: String = ""
    @Published private(set) var scrobbledCount: Int = 0

    private struct ScrobbleState {
        var artist: String
        var title: String
        var startTime: Date
        var duration: TimeInterval
        var scrobbled: Bool
        var isPaused: Bool
        var pausedTime: TimeInterval
        var lastElapsedSeconds: TimeInterval
    }

    private var currentState: ScrobbleState?
    private var pauseStartTime: Date?

    func authURL(apiKey: String) -> URL? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://www.last.fm/api/auth/?api_key=\(trimmed)&cb=https://soundcloud.com/discover")
    }

    func exchangeToken(_ token: String, settings: AppSettings) async -> Bool {
        let apiKey = settings.lastFmApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = settings.lastFmApiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !secret.isEmpty else { return false }

        let params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]
        let sig = generateApiSignature(params: params, secret: secret)
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")
        components?.queryItems = [
            URLQueryItem(name: "method", value: "auth.getSession"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "api_sig", value: sig),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else { return false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let session = json["session"] as? [String: Any],
               let key = session["key"] as? String {
                settings.lastFmSessionKey = key
                settings.lastFmEnabled = true
                lastScrobbleStatus = "Authenticated as \(session["name"] as? String ?? "Last.fm User")"
                return true
            }
        } catch {
            lastScrobbleStatus = "Auth failed: \(error.localizedDescription)"
        }
        return false
    }

    func updateTrackInfo(_ trackInfo: TrackInfo, settings: AppSettings) async {
        guard settings.lastFmEnabled, !settings.lastFmSessionKey.isEmpty else { return }
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
            } else if trackInfo.isPlaying && state.isPaused {
                state.isPaused = false
                if let pStart = pauseStartTime {
                    state.pausedTime += Date().timeIntervalSince(pStart)
                }
                pauseStartTime = nil
            }
            currentState = state
        }

        if trackInfo.isPlaying {
            await updateNowPlaying(artist: normalized.artist, track: normalized.track, settings: settings)
        }

        let elapsed = trackInfo.elapsedSeconds
        let isLoop: Bool = {
            guard let state = currentState else { return false }
            return state.artist == normalized.artist &&
                state.title == normalized.track &&
                elapsed <= state.lastElapsedSeconds - 3
        }()

        if currentState == nil ||
            currentState?.artist != normalized.artist ||
            currentState?.title != normalized.track ||
            isLoop {
            if let old = currentState, !old.isPaused, !old.scrobbled, shouldScrobble(old) {
                await scrobble(artist: old.artist, track: old.title, settings: settings)
            }
            currentState = ScrobbleState(
                artist: normalized.artist,
                title: normalized.track,
                startTime: Date(),
                duration: max(1, trackInfo.durationSeconds),
                scrobbled: false,
                isPaused: !trackInfo.isPlaying,
                pausedTime: 0,
                lastElapsedSeconds: elapsed
            )
            pauseStartTime = trackInfo.isPlaying ? nil : Date()
        } else if var state = currentState, !state.isPaused, !state.scrobbled, shouldScrobble(state) {
            await scrobble(artist: state.artist, track: state.title, settings: settings)
            state.scrobbled = true
            currentState = state
        }

        currentState?.lastElapsedSeconds = elapsed
    }

    func disconnect(settings: AppSettings) {
        settings.lastFmEnabled = false
        settings.lastFmSessionKey = ""
        currentState = nil
        lastScrobbleStatus = "Disconnected"
    }

    private func shouldScrobble(_ state: ScrobbleState) -> Bool {
        let totalElapsed = Date().timeIntervalSince(state.startTime)
        let playedTime = totalElapsed - state.pausedTime
        let threshold = min(state.duration / 2.0, 240.0)
        return !state.scrobbled && playedTime >= max(10, threshold)
    }

    private func updateNowPlaying(artist: String, track: String, settings: AppSettings) async {
        let params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": settings.lastFmApiKey,
            "sk": settings.lastFmSessionKey,
            "artist": artist,
            "track": track
        ]
        _ = await postSigned(params: params, secret: settings.lastFmApiSecret)
    }

    private func scrobble(artist: String, track: String, settings: AppSettings) async {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let params: [String: String] = [
            "method": "track.scrobble",
            "api_key": settings.lastFmApiKey,
            "sk": settings.lastFmSessionKey,
            "artist": artist,
            "track": track,
            "timestamp": timestamp
        ]
        if await postSigned(params: params, secret: settings.lastFmApiSecret) {
            scrobbledCount += 1
            lastScrobbleStatus = "Scrobbled: \(artist) – \(track)"
        }
    }

    private func postSigned(params: [String: String], secret: String) async -> Bool {
        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else { return false }
        let sig = generateApiSignature(params: params, secret: secret)
        var allParams = params
        allParams["api_sig"] = sig
        allParams["format"] = "json"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let bodyString = allParams
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        req.httpBody = Data(bodyString.utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMsg = json["message"] as? String {
                    lastScrobbleStatus = "Last.fm error: \(errorMsg)"
                    return false
                }
                return true
            }
        } catch {
            lastScrobbleStatus = "Network error: \(error.localizedDescription)"
        }
        return false
    }

    private func generateApiSignature(params: [String: String], secret: String) -> String {
        let sorted = params.keys.sorted().map { "\($0)\(params[$0] ?? "")" }.joined() + secret
        let digest = Insecure.MD5.hash(data: Data(sorted.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func urlEncode(_ str: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return str.addingPercentEncoding(withAllowedCharacters: allowed) ?? str
    }
}
