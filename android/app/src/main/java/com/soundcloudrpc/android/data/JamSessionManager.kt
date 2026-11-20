package com.soundcloudrpc.android.data

import com.google.gson.Gson
import com.soundcloudrpc.android.model.SCTrack
import com.soundcloudrpc.android.model.SCUser
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.min

data class JamParticipant(
    val id: String,
    val name: String,
    val avatarUrl: String?,
    val isHost: Boolean,
    val lastSeen: Double
)

data class JamTrackRef(
    val id: Long,
    val title: String,
    val artist: String,
    val artworkUrl: String?,
    val durationMs: Long?,
    val permalinkUrl: String?
) {
    fun toSCTrack(): SCTrack = SCTrack(
        id = id,
        title = title,
        duration = durationMs,
        artworkUrl = artworkUrl,
        permalinkUrl = permalinkUrl,
        user = SCUser(id = 0L, username = artist, fullName = artist)
    )

    companion object {
        fun from(track: SCTrack): JamTrackRef = JamTrackRef(
            id = track.id,
            title = track.displayTitle,
            artist = track.artistName,
            artworkUrl = track.rawArtwork,
            durationMs = track.duration,
            permalinkUrl = track.permalinkUrl
        )
    }
}

data class JamReactionBurst(
    val id: String = UUID.randomUUID().toString(),
    val emoji: String,
    val senderName: String
)

private data class JamEventWire(
    val v: Int = 1,
    val type: String,
    val senderId: String,
    val senderName: String,
    val senderAvatar: String?,
    val isHost: Boolean,
    val sentAt: Double,
    val allowGuestControl: Boolean? = null,
    val track: JamTrackRef? = null,
    val isPlaying: Boolean? = null,
    val positionSec: Double? = null,
    val queue: List<JamTrackRef>? = null,
    val action: String? = null,
    val seekSec: Double? = null,
    val emoji: String? = null
)

private data class NtfyEnvelopeWire(
    val id: String? = null,
    val event: String? = null,
    val message: String? = null
)

/**
 * Worldwide real-time Group Listening ("Jam") engine — 100% wire-compatible with iOS & iPadOS!
 */
class JamSessionManager(
    private val scope: CoroutineScope,
    private val getDisplayName: () -> String,
    private val getAvatarUrl: () -> String?,
    private val getCurrentTrack: () -> SCTrack?,
    private val getQueue: () -> List<SCTrack>,
    private val getIsPlaying: () -> Boolean,
    private val getElapsedSec: () -> Long,
    private val onApplyRemoteState: suspend (SCTrack, List<SCTrack>, Boolean, Double) -> Unit,
    private val onApplyGuestControl: (String, JamTrackRef?, Double?) -> Unit,
    private val onHostAppendQueue: (SCTrack) -> Unit,
    private val onToast: (String) -> Unit
) {
    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .pingInterval(25, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private val clientId = UUID.randomUUID().toString()
    private val relayBase = "https://ntfy.sh"

    private val _isActive = MutableStateFlow(false)
    val isActive: StateFlow<Boolean> = _isActive.asStateFlow()

    private val _isHost = MutableStateFlow(false)
    val isHost: StateFlow<Boolean> = _isHost.asStateFlow()

    private val _roomCode = MutableStateFlow("")
    val roomCode: StateFlow<String> = _roomCode.asStateFlow()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _allowGuestControl = MutableStateFlow(false)
    val allowGuestControl: StateFlow<Boolean> = _allowGuestControl.asStateFlow()

    val isGuestLocked: Boolean
        get() = _isActive.value && !_isHost.value && !_allowGuestControl.value

    private val _participants = MutableStateFlow<List<JamParticipant>>(emptyList())
    val participants: StateFlow<List<JamParticipant>> = _participants.asStateFlow()

    private val _sharedQueue = MutableStateFlow<List<JamTrackRef>>(emptyList())
    val sharedQueue: StateFlow<List<JamTrackRef>> = _sharedQueue.asStateFlow()

    private val _statusNote = MutableStateFlow("")
    val statusNote: StateFlow<String> = _statusNote.asStateFlow()

    private val _recentReaction = MutableStateFlow<JamReactionBurst?>(null)
    val recentReaction: StateFlow<JamReactionBurst?> = _recentReaction.asStateFlow()

    private var webSocket: WebSocket? = null
    private var heartbeatJob: Job? = null
    private var reconnectJob: Job? = null
    private var lastNtfyId: String? = null
    private var reconnectAttempt = 0

    val inviteLink: String
        get() = if (_roomCode.value.isNotEmpty()) "soundcloudrpc://jam/${_roomCode.value}" else ""

    val shareText: String
        get() = "Join my SoundCloud Jam! Open SoundCloud RPC and enter code ${_roomCode.value} or tap: $inviteLink"

    fun startJam() {
        leaveJam(silent = true)
        val code = generateRoomCode()
        _roomCode.value = code
        _isHost.value = true
        _isActive.value = true
        _allowGuestControl.value = false
        lastNtfyId = null
        reconnectAttempt = 0
        _statusNote.value = "Hosting live Jam"
        _participants.value = listOf(
            JamParticipant(clientId, getDisplayName(), getAvatarUrl(), true, nowEpoch())
        )
        _sharedQueue.value = getQueue().take(25).map { JamTrackRef.from(it) }
        connectWebSocket()
        startHeartbeat()

        scope.launch {
            delay(500)
            broadcastHostState()
            onToast("Jam started · Code $code")
        }
    }

    fun joinJam(codeOrUrl: String) {
        val code = normalizeCode(codeOrUrl)
        if (code.length < 4) {
            _statusNote.value = "Enter a valid 6-character Jam code"
            return
        }
        leaveJam(silent = true)
        _roomCode.value = code
        _isHost.value = false
        _isActive.value = true
        lastNtfyId = null
        reconnectAttempt = 0
        _statusNote.value = "Connecting to Jam $code..."
        _participants.value = listOf(
            JamParticipant(clientId, getDisplayName(), getAvatarUrl(), false, nowEpoch())
        )
        connectWebSocket()
        startHeartbeat()

        scope.launch {
            delay(500)
            publishEvent(type = "join")
            delay(350)
            publishEvent(type = "sync_request")
            onToast("Joined Jam $code")
        }
    }

    fun leaveJam(silent: Boolean = false) {
        val wasActive = _isActive.value
        val wasHost = _isHost.value
        val oldCode = _roomCode.value
        if (wasActive && oldCode.isNotEmpty()) {
            scope.launch(Dispatchers.IO) {
                publishEvent(type = if (wasHost) "ended" else "leave", explicitCode = oldCode)
            }
        }
        heartbeatJob?.cancel()
        reconnectJob?.cancel()
        webSocket?.close(1000, "Leave")
        webSocket = null

        _isActive.value = false
        _isHost.value = false
        _roomCode.value = ""
        _isConnected.value = false
        _participants.value = emptyList()
        _sharedQueue.value = emptyList()
        _statusNote.value = ""
        lastNtfyId = null

        if (wasActive && !silent) {
            onToast(if (wasHost) "Ended Jam session" else "Left Jam session")
        }
    }

    fun setAllowGuestControl(enabled: Boolean) {
        _allowGuestControl.value = enabled
        if (_isActive.value && _isHost.value) {
            scope.launch { broadcastHostState() }
        }
    }

    fun requestResync() {
        if (!_isActive.value) return
        _statusNote.value = "Syncing with Host..."
        scope.launch { publishEvent(type = "sync_request") }
    }

    fun addTrackToJam(track: SCTrack) {
        if (!_isActive.value) return
        val ref = JamTrackRef.from(track)
        if (_isHost.value) {
            onHostAppendQueue(track)
            _sharedQueue.value = getQueue().take(25).map { JamTrackRef.from(it) }
            scope.launch { broadcastHostState() }
            onToast("Queued \"${track.displayTitle}\" for Jam")
        } else {
            scope.launch {
                publishEvent(type = "queue_add", track = ref)
                onToast("Sent \"${track.displayTitle}\" to Jam queue")
            }
        }
    }

    fun sendReaction(emoji: String) {
        if (!_isActive.value) return
        _recentReaction.value = JamReactionBurst(emoji = emoji, senderName = getDisplayName())
        scope.launch { publishEvent(type = "reaction", emoji = emoji) }
    }

    fun onLocalPlaybackEvent(action: String, seekSec: Double? = null) {
        if (!_isActive.value) return
        if (_isHost.value) {
            _sharedQueue.value = getQueue().take(25).map { JamTrackRef.from(it) }
            scope.launch { broadcastHostState() }
        } else if (_allowGuestControl.value) {
            val ref = if (action == "track") getCurrentTrack()?.let { JamTrackRef.from(it) } else null
            scope.launch {
                publishEvent(type = "control", track = ref, action = action, seekSec = seekSec)
            }
        }
    }

    private fun connectWebSocket() {
        val code = _roomCode.value
        if (!_isActive.value || code.isEmpty()) return
        webSocket?.cancel()

        val topic = topicName(code)
        val since = lastNtfyId ?: "latest"
        val wsUrl = "${relayBase.replace("https://", "wss://")}/$topic/ws?since=$since"

        val req = Request.Builder().url(wsUrl).build()
        webSocket = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _isConnected.value = true
                reconnectAttempt = 0
                _statusNote.value = if (_isHost.value) "Live · Sharing with friends" else "Synced live with Host"
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                scope.launch { handleSocketFrame(text) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _isConnected.value = false
                if (_isActive.value) scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _isConnected.value = false
                if (_isActive.value) scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectAttempt = min(reconnectAttempt + 1, 4)
        val delaySec = (1 shl reconnectAttempt).coerceAtMost(15)
        _statusNote.value = "Reconnecting in ${delaySec}s..."
        reconnectJob = scope.launch {
            delay(delaySec * 1000L)
            if (_isActive.value) connectWebSocket()
        }
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (_isActive.value) {
                delay(22_000L)
                if (!_isActive.value) break
                val now = nowEpoch()
                _participants.value = _participants.value.filter { it.id == clientId || (now - it.lastSeen) < 70.0 }
                publishEvent(type = "heartbeat")
                if (_isHost.value) broadcastHostState()
            }
        }
    }

    private suspend fun broadcastHostState() {
        if (!_isActive.value || !_isHost.value) return
        val q = getQueue().take(25).map { JamTrackRef.from(it) }
        _sharedQueue.value = q
        publishEvent(
            type = "state",
            allowGuestControl = _allowGuestControl.value,
            track = getCurrentTrack()?.let { JamTrackRef.from(it) },
            isPlaying = getIsPlaying(),
            positionSec = getElapsedSec().toDouble(),
            queue = q
        )
    }

    private suspend fun publishEvent(
        type: String,
        explicitCode: String? = null,
        allowGuestControl: Boolean? = null,
        track: JamTrackRef? = null,
        isPlaying: Boolean? = null,
        positionSec: Double? = null,
        queue: List<JamTrackRef>? = null,
        action: String? = null,
        seekSec: Double? = null,
        emoji: String? = null
    ) = withContext(Dispatchers.IO) {
        val code = explicitCode ?: _roomCode.value
        if (code.isEmpty()) return@withContext
        val ev = JamEventWire(
            type = type,
            senderId = clientId,
            senderName = getDisplayName(),
            senderAvatar = getAvatarUrl(),
            isHost = _isHost.value,
            sentAt = nowEpoch(),
            allowGuestControl = allowGuestControl,
            track = track,
            isPlaying = isPlaying,
            positionSec = positionSec,
            queue = queue,
            action = action,
            seekSec = seekSec,
            emoji = emoji
        )
        val body = gson.toJson(ev).toRequestBody("text/plain; charset=utf-8".toMediaType())
        val req = Request.Builder()
            .url("$relayBase/${topicName(code)}")
            .post(body)
            .header("Firebase", "no")
            .header("Priority", "1")
            .build()
        runCatching { client.newCall(req).execute().close() }
    }

    private suspend fun handleSocketFrame(text: String) {
        val env = runCatching { gson.fromJson(text, NtfyEnvelopeWire::class.java) }.getOrNull() ?: return
        if (!env.id.isNullOrBlank()) lastNtfyId = env.id
        if (env.event != "message" || env.message.isNullOrBlank()) return
        val ev = runCatching { gson.fromJson(env.message, JamEventWire::class.java) }.getOrNull() ?: return
        if (ev.senderId == clientId) return

        if (ev.type != "leave" && ev.type != "ended") {
            val list = _participants.value.toMutableList()
            val idx = list.indexOfFirst { it.id == ev.senderId }
            val updated = JamParticipant(ev.senderId, ev.senderName, ev.senderAvatar, ev.isHost, nowEpoch())
            if (idx >= 0) list[idx] = updated else list.add(updated)
            _participants.value = list
        }

        when (ev.type) {
            "join" -> {
                onToast("${ev.senderName} joined the Jam")
                if (_isHost.value) broadcastHostState()
            }
            "leave" -> {
                _participants.value = _participants.value.filter { it.id != ev.senderId }
                onToast("${ev.senderName} left the Jam")
            }
            "ended" -> {
                if (!_isHost.value) {
                    onToast("${ev.senderName} ended the Jam")
                    leaveJam(silent = true)
                }
            }
            "sync_request" -> {
                if (_isHost.value) broadcastHostState()
            }
            "reaction" -> {
                if (!ev.emoji.isNullOrBlank()) {
                    _recentReaction.value = JamReactionBurst(emoji = ev.emoji, senderName = ev.senderName)
                }
            }
            "queue_add" -> {
                if (_isHost.value && ev.track != null) {
                    onHostAppendQueue(ev.track.toSCTrack())
                    onToast("${ev.senderName} queued \"${ev.track.title}\"")
                    broadcastHostState()
                }
            }
            "control" -> {
                if (_isHost.value && _allowGuestControl.value && ev.action != null) {
                    onApplyGuestControl(ev.action, ev.track, ev.seekSec)
                }
            }
            "state" -> {
                if (_isHost.value) return
                ev.allowGuestControl?.let { _allowGuestControl.value = it }
                ev.queue?.let { _sharedQueue.value = it }
                val ref = ev.track ?: return
                val lag = (nowEpoch() - ev.sentAt).coerceIn(0.0, 15.0)
                val playing = ev.isPlaying ?: true
                val basePos = ev.positionSec ?: 0.0
                val targetPos = if (playing) basePos + lag else basePos
                val scQueue = (ev.queue ?: listOf(ref)).map { it.toSCTrack() }
                _statusNote.value = "Synced with ${ev.senderName}"
                onApplyRemoteState(ref.toSCTrack(), scQueue, playing, targetPos)
            }
        }
    }

    private fun nowEpoch(): Double = System.currentTimeMillis() / 1000.0

    companion object {
        fun normalizeCode(input: String): String {
            var s = input.trim()
            val idx = s.lowercase().indexOf("jam/")
            if (idx >= 0) s = s.substring(idx + 4)
            return s.uppercase().replace("JAM-", "").filter { it.isLetterOrDigit() }.take(8)
        }

        fun generateRoomCode(): String {
            val chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            return (1..6).map { chars.random() }.joinToString("")
        }

        fun topicName(code: String): String {
            val salted = "scrpc-jam-v1:${code.uppercase()}"
            val digest = MessageDigest.getInstance("SHA-256").digest(salted.toByteArray(Charsets.UTF_8))
            val hex = digest.joinToString("") { "%02x".format(it) }
            return "scrpc-jam-${hex.take(20)}"
        }
    }
}
