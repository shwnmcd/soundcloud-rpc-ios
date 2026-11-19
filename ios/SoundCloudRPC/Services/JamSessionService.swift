import Foundation
import CryptoKit
import SwiftUI
import UIKit

// MARK: - Cross-Platform Jam Wire Models (Identical JSON Protocol on iOS, iPadOS & Android!)

enum JamConnectionState: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

struct JamParticipant: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var avatarUrl: String?
    var isHost: Bool
    var lastSeen: TimeInterval
}

struct JamTrackRef: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let artworkUrl: String?
    let durationMs: Int?
    let permalinkUrl: String?

    init(from track: SCTrack) {
        self.id = track.id
        self.title = track.displayTitle
        self.artist = track.artistName
        self.artworkUrl = track.rawArtwork
        self.durationMs = track.duration
        self.permalinkUrl = track.permalinkUrl
    }

    func toSCTrack() -> SCTrack {
        SCTrack(
            id: id,
            title: title,
            duration: durationMs,
            artworkUrl: artworkUrl,
            permalinkUrl: permalinkUrl,
            playbackCount: nil,
            likesCount: nil,
            user: SCUser(
                id: 0,
                username: artist,
                fullName: artist,
                avatarUrl: nil,
                permalinkUrl: nil,
                followersCount: nil,
                followingsCount: nil,
                trackCount: nil,
                visuals: nil
            ),
            media: nil,
            trackAuthorization: nil,
            createdAt: nil
        )
    }
}

struct JamReactionBurst: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let senderName: String
    let xFraction: CGFloat
}

private struct JamEvent: Codable {
    let v: Int
    let type: String // state, join, leave, heartbeat, sync_request, queue_add, control, reaction, ended
    let senderId: String
    let senderName: String
    let senderAvatar: String?
    let isHost: Bool
    let sentAt: TimeInterval
    let allowGuestControl: Bool?
    let track: JamTrackRef?
    let isPlaying: Bool?
    let positionSec: Double?
    let queue: [JamTrackRef]?
    let action: String? // play, pause, next, prev, seek, track
    let seekSec: Double?
    let emoji: String?
}

private struct NtfyEnvelope: Decodable {
    let id: String?
    let event: String?
    let message: String?
}

// MARK: - Worldwide Real-Time Group Listening Engine ("Jam")
@MainActor
final class JamSessionService: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isHost: Bool = false
    @Published private(set) var roomCode: String = ""
    @Published private(set) var connectionState: JamConnectionState = .disconnected
    @Published private(set) var participants: [JamParticipant] = []
    @Published private(set) var sharedQueue: [JamTrackRef] = []
    @Published private(set) var activeReactions: [JamReactionBurst] = []
    @Published var allowGuestControl: Bool = true
    @Published var statusNote: String = ""

    weak var player: AudioPlayerService?
    weak var api: SoundCloudAPI?
    weak var settings: AppSettings?

    private let clientId: String
    private var wsTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var lastNtfyEventId: String?
    private var reconnectAttempt: Int = 0
    private var lastStateBroadcastTime: TimeInterval = 0

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var inviteLink: String {
        guard !roomCode.isEmpty else { return "" }
        return "soundcloudrpc://jam/\(roomCode)"
    }

    var shareMessage: String {
        "Join my SoundCloud Jam! Open SoundCloud RPC and enter code \(roomCode) or tap: \(inviteLink)"
    }

    var listenerCount: Int {
        max(1, participants.count)
    }

    private var myDisplayName: String {
        api?.currentUser?.displayName ?? UIDevice.current.name
    }

    private var myAvatarUrl: String? {
        api?.currentUser?.avatarUrl
    }

    private var relayBaseURL: String {
        let raw = settings?.jamRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "https://ntfy.sh" }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    init() {
        let key = "scrpc_jam_client_uuid"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            self.clientId = existing
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: key)
            self.clientId = fresh
        }
    }

    func bind(player: AudioPlayerService, api: SoundCloudAPI, settings: AppSettings) {
        self.player = player
        self.api = api
        self.settings = settings

        player.onLocalPlaybackEvent = { [weak self] action, seekSec in
            Task { @MainActor in
                self?.handleLocalPlayerChange(action: action, seekSec: seekSec)
            }
        }
    }

    // MARK: - Room Code Helpers & Privacy-Safe Topic Hashing
    static func normalizeCode(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: "jam/", options: .caseInsensitive) {
            cleaned = String(cleaned[range.upperBound...])
        }
        cleaned = cleaned
            .uppercased()
            .replacingOccurrences(of: "JAM-", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return String(cleaned.prefix(8))
    }

    static func generateRoomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    static func topicName(for code: String) -> String {
        let salted = "scrpc-jam-v1:\(code.uppercased())"
        let digest = SHA256.hash(data: Data(salted.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "scrpc-jam-\(hex.prefix(20))"
    }

    // MARK: - Start / Join / Leave Jam
    func startJam() {
        leaveJam(silent: true)
        let code = Self.generateRoomCode()
        self.roomCode = code
        self.isHost = true
        self.isActive = true
        self.allowGuestControl = true
        self.lastNtfyEventId = nil
        self.reconnectAttempt = 0
        self.statusNote = "Hosting live Jam"
        self.participants = [
            JamParticipant(
                id: clientId,
                name: myDisplayName,
                avatarUrl: myAvatarUrl,
                isHost: true,
                lastSeen: Date().timeIntervalSince1970
            )
        ]
        refreshSharedQueueFromPlayer()
        connectWebSocket()
        startHeartbeatLoop()

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await broadcastHostState()
            api?.showToast("Jam started · Code \(code)")
        }
    }

    func joinJam(codeOrUrl: String) {
        let code = Self.normalizeCode(codeOrUrl)
        guard code.count >= 4 else {
            statusNote = "Enter a valid 6-character Jam code"
            return
        }

        leaveJam(silent: true)
        self.roomCode = code
        self.isHost = false
        self.isActive = true
        self.lastNtfyEventId = nil
        self.reconnectAttempt = 0
        self.statusNote = "Connecting to Jam \(code)..."
        self.participants = [
            JamParticipant(
                id: clientId,
                name: myDisplayName,
                avatarUrl: myAvatarUrl,
                isHost: false,
                lastSeen: Date().timeIntervalSince1970
            )
        ]
        connectWebSocket()
        startHeartbeatLoop()

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await publishEvent(type: "join")
            try? await Task.sleep(nanoseconds: 350_000_000)
            await publishEvent(type: "sync_request")
            api?.showToast("Joined Jam \(code)")
        }
    }

    func leaveJam(silent: Bool = false) {
        let wasActive = isActive
        let wasHost = isHost
        let oldCode = roomCode

        if wasActive && !oldCode.isEmpty {
            let finalType = wasHost ? "ended" : "leave"
            Task {
                await publishEvent(type: finalType, explicitCode: oldCode)
            }
        }

        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil

        isActive = false
        isHost = false
        roomCode = ""
        connectionState = .disconnected
        participants = []
        sharedQueue = []
        lastNtfyEventId = nil
        statusNote = ""

        if wasActive && !silent {
            api?.showToast(wasHost ? "Ended Jam session" : "Left Jam session")
        }
    }

    // MARK: - Interactive Jam Actions
    func setAllowGuestControl(_ enabled: Bool) {
        allowGuestControl = enabled
        guard isActive && isHost else { return }
        Task { await broadcastHostState() }
    }

    func requestResync() {
        guard isActive else { return }
        statusNote = "Syncing with Host..."
        Task { await publishEvent(type: "sync_request") }
    }

    func addTrackToJam(_ track: SCTrack) {
        guard isActive else {
            player?.appendToQueue(track)
            return
        }

        let ref = JamTrackRef(from: track)
        if isHost {
            player?.appendToQueue(track)
            refreshSharedQueueFromPlayer()
            Task { await broadcastHostState() }
            api?.showToast("Queued \"\(track.displayTitle)\" for Jam")
        } else {
            Task {
                await publishEvent(type: "queue_add", track: ref)
                api?.showToast("Sent \"\(track.displayTitle)\" to Jam queue")
            }
        }
    }

    func sendReaction(_ emoji: String) {
        guard isActive else { return }
        spawnLocalReaction(emoji: emoji, senderName: myDisplayName)
        Task {
            await publishEvent(type: "reaction", emoji: emoji)
        }
    }

    private func spawnLocalReaction(emoji: String, senderName: String) {
        let burst = JamReactionBurst(
            emoji: emoji,
            senderName: senderName,
            xFraction: CGFloat.random(in: 0.18...0.82)
        )
        activeReactions.append(burst)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            activeReactions.removeAll { $0.id == burst.id }
        }
    }

    // MARK: - Local Player Event Bridge
    private func handleLocalPlayerChange(action: String, seekSec: Double?) {
        guard isActive, let player else { return }

        if isHost {
            refreshSharedQueueFromPlayer()
            Task { await broadcastHostState() }
        } else if allowGuestControl {
            // Forward guest control command to Host so everyone stays tightly in sync!
            let currentRef = player.currentTrack.map { JamTrackRef(from: $0) }
            Task {
                await publishEvent(
                    type: "control",
                    track: action == "track" ? currentRef : nil,
                    action: action,
                    seekSec: seekSec
                )
            }
        }
    }

    private func refreshSharedQueueFromPlayer() {
        guard let player else { return }
        sharedQueue = Array(player.queue.prefix(25)).map { JamTrackRef(from: $0) }
    }

    // MARK: - WebSocket Connection & Auto-Reconnect
    private func connectWebSocket() {
        guard isActive, !roomCode.isEmpty else { return }

        receiveLoopTask?.cancel()
        wsTask?.cancel(with: .goingAway, reason: nil)

        connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting

        let topic = Self.topicName(for: roomCode)
        let wsBase = relayBaseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let sinceParam = lastNtfyEventId ?? "latest"
        guard let url = URL(string: "\(wsBase)/\(topic)/ws?since=\(sinceParam)") else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let task = URLSession.shared.webSocketTask(with: req)
        self.wsTask = task
        task.resume()

        receiveLoopTask = Task { [weak self] in
            await self?.listenLoop(task: task)
        }
    }

    private func listenLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled && isActive {
            do {
                let msg = try await task.receive()
                if connectionState != .connected {
                    connectionState = .connected
                    reconnectAttempt = 0
                    statusNote = isHost ? "Live · Sharing with friends" : "Synced live with Host"
                }

                switch msg {
                case .string(let text):
                    await handleRawSocketFrame(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleRawSocketFrame(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled && isActive else { return }
                scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        connectionState = .reconnecting
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        let delaySec = min(15, Int(pow(2.0, Double(reconnectAttempt))))
        statusNote = "Reconnecting in \(delaySec)s..."

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySec) * 1_000_000_000)
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.connectWebSocket()
        }
    }

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 22_000_000_000)
                guard !Task.isCancelled, let self, self.isActive else { return }
                self.pruneStaleParticipants()
                await self.publishEvent(type: "heartbeat")
                if self.isHost {
                    let now = Date().timeIntervalSince1970
                    if now - self.lastStateBroadcastTime > 20 {
                        await self.broadcastHostState()
                    }
                }
            }
        }
    }

    private func pruneStaleParticipants() {
        let now = Date().timeIntervalSince1970
        participants.removeAll { p in
            p.id != clientId && (now - p.lastSeen) > 70
        }
    }

    // MARK: - Publish & Handle Incoming Jam Events
    private func broadcastHostState() async {
        guard isActive, isHost, let player else { return }
        lastStateBroadcastTime = Date().timeIntervalSince1970
        refreshSharedQueueFromPlayer()

        let currentRef = player.currentTrack.map { JamTrackRef(from: $0) }
        await publishEvent(
            type: "state",
            allowGuestControl: allowGuestControl,
            track: currentRef,
            isPlaying: player.isPlaying,
            positionSec: player.elapsedSeconds,
            queue: sharedQueue
        )
    }

    private func publishEvent(
        type: String,
        explicitCode: String? = nil,
        allowGuestControl: Bool? = nil,
        track: JamTrackRef? = nil,
        isPlaying: Bool? = nil,
        positionSec: Double? = nil,
        queue: [JamTrackRef]? = nil,
        action: String? = nil,
        seekSec: Double? = nil,
        emoji: String? = nil
    ) async {
        let code = explicitCode ?? roomCode
        guard !code.isEmpty else { return }

        let event = JamEvent(
            v: 1,
            type: type,
            senderId: clientId,
            senderName: myDisplayName,
            senderAvatar: myAvatarUrl,
            isHost: isHost,
            sentAt: Date().timeIntervalSince1970,
            allowGuestControl: allowGuestControl,
            track: track,
            isPlaying: isPlaying,
            positionSec: positionSec,
            queue: queue,
            action: action,
            seekSec: seekSec,
            emoji: emoji
        )

        guard let payload = try? encoder.encode(event),
              let url = URL(string: "\(relayBaseURL)/\(Self.topicName(for: code))") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("no", forHTTPHeaderField: "Firebase")
        req.setValue("1", forHTTPHeaderField: "Priority")

        _ = try? await URLSession.shared.data(for: req)
    }

    private func handleRawSocketFrame(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let env = try? decoder.decode(NtfyEnvelope.self, from: data) else { return }

        if let id = env.id, !id.isEmpty {
            lastNtfyEventId = id
        }

        guard env.event == "message",
              let msgStr = env.message,
              let msgData = msgStr.data(using: .utf8),
              let event = try? decoder.decode(JamEvent.self, from: msgData) else { return }

        // Ignore our own echoed messages
        if event.senderId == clientId { return }

        // Track sender presence
        if event.type != "leave" && event.type != "ended" {
            upsertParticipant(
                id: event.senderId,
                name: event.senderName,
                avatarUrl: event.senderAvatar,
                isHost: event.isHost
            )
        }

        switch event.type {
        case "join":
            api?.showToast("\(event.senderName) joined the Jam")
            if isHost {
                await broadcastHostState()
            }

        case "leave":
            participants.removeAll { $0.id == event.senderId }
            api?.showToast("\(event.senderName) left the Jam")

        case "ended":
            if !isHost {
                api?.showToast("\(event.senderName) ended the Jam")
                leaveJam(silent: true)
            }

        case "sync_request":
            if isHost {
                await broadcastHostState()
            }

        case "heartbeat":
            break

        case "reaction":
            if let emoji = event.emoji, !emoji.isEmpty {
                spawnLocalReaction(emoji: emoji, senderName: event.senderName)
            }

        case "queue_add":
            if isHost, let ref = event.track {
                player?.appendToQueue(ref.toSCTrack())
                refreshSharedQueueFromPlayer()
                api?.showToast("\(event.senderName) queued \"\(ref.title)\"")
                await broadcastHostState()
            }

        case "control":
            guard isHost && allowGuestControl, let player else { return }
            switch event.action {
            case "play":
                if !player.isPlaying { player.togglePlayPause() }
            case "pause":
                if player.isPlaying { player.togglePlayPause() }
            case "next":
                player.nextTrack()
            case "prev":
                player.previousTrack(forcePrevious: true)
            case "seek":
                if let sec = event.seekSec {
                    player.seek(toSeconds: sec, notifyJam: true)
                }
            case "track":
                if let ref = event.track {
                    let scTrack = ref.toSCTrack()
                    var nextQueue = player.queue
                    if !nextQueue.contains(where: { $0.id == scTrack.id }) {
                        nextQueue.insert(scTrack, at: 0)
                    }
                    player.play(track: scTrack, in: nextQueue)
                }
            default:
                break
            }

        case "state":
            guard !isHost else { return }
            if let guestCtrl = event.allowGuestControl {
                self.allowGuestControl = guestCtrl
            }
            if let q = event.queue {
                self.sharedQueue = q
            }
            if let trackRef = event.track, let player {
                let now = Date().timeIntervalSince1970
                let networkLag = max(0, min(15, now - event.sentAt))
                let shouldPlay = event.isPlaying ?? true
                let basePos = event.positionSec ?? 0
                let compensatedPos = shouldPlay ? (basePos + networkLag) : basePos

                let scTrack = trackRef.toSCTrack()
                let scQueue = (event.queue ?? [trackRef]).map { $0.toSCTrack() }
                statusNote = "Synced with \(event.senderName)"

                await player.applyRemoteJamState(
                    track: scTrack,
                    queueTracks: scQueue,
                    shouldPlay: shouldPlay,
                    targetPositionSec: compensatedPos
                )
            }

        default:
            break
        }
    }

    private func upsertParticipant(id: String, name: String, avatarUrl: String?, isHost: Bool) {
        let now = Date().timeIntervalSince1970
        if let idx = participants.firstIndex(where: { $0.id == id }) {
            participants[idx].name = name
            participants[idx].avatarUrl = avatarUrl
            participants[idx].isHost = isHost
            participants[idx].lastSeen = now
        } else {
            participants.append(
                JamParticipant(
                    id: id,
                    name: name,
                    avatarUrl: avatarUrl,
                    isHost: isHost,
                    lastSeen: now
                )
            )
        }
    }
}
