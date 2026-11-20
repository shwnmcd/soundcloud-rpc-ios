package com.soundcloudrpc.android

import android.app.Application
import android.content.ComponentName
import android.net.Uri
import android.webkit.CookieManager
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.soundcloudrpc.android.data.AppPrefs
import com.soundcloudrpc.android.data.IntegrationsService
import com.soundcloudrpc.android.data.JamSessionManager
import com.soundcloudrpc.android.data.SoundCloudApi
import com.soundcloudrpc.android.model.*
import com.soundcloudrpc.android.player.PlaybackService
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class RepeatMode { NONE, ALL, ONE }

class AppViewModel(application: Application) : AndroidViewModel(application) {
    val prefs = AppPrefs(application)
    val api = SoundCloudApi(prefs, application)
    val integrations = IntegrationsService(prefs)

    private var mediaController: MediaController? = null

    private val _isLoggedIn = MutableStateFlow(prefs.oauthToken.isNotBlank() && prefs.clientId.isNotBlank())
    val isLoggedIn: StateFlow<Boolean> = _isLoggedIn.asStateFlow()

    private val _currentUser = MutableStateFlow<SCUser?>(null)
    val currentUser: StateFlow<SCUser?> = _currentUser.asStateFlow()

    private val _likedIds = MutableStateFlow<Set<Long>>(emptySet())
    val likedIds: StateFlow<Set<Long>> = _likedIds.asStateFlow()

    // Home, Feed, Library state
    private val _homeShelves = MutableStateFlow<List<SCHomeShelf>>(emptyList())
    val homeShelves: StateFlow<List<SCHomeShelf>> = _homeShelves.asStateFlow()

    private val _quickCards = MutableStateFlow<List<SCQuickCard>>(emptyList())
    val quickCards: StateFlow<List<SCQuickCard>> = _quickCards.asStateFlow()

    private val _likes = MutableStateFlow<List<SCTrack>>(emptyList())
    val likes: StateFlow<List<SCTrack>> = _likes.asStateFlow()

    private val _playlists = MutableStateFlow<List<SCPlaylist>>(emptyList())
    val playlists: StateFlow<List<SCPlaylist>> = _playlists.asStateFlow()

    private val _albums = MutableStateFlow<List<SCPlaylist>>(emptyList())
    val albums: StateFlow<List<SCPlaylist>> = _albums.asStateFlow()

    private val _history = MutableStateFlow<List<SCTrack>>(emptyList())
    val history: StateFlow<List<SCTrack>> = _history.asStateFlow()

    private val _following = MutableStateFlow<List<SCUser>>(emptyList())
    val following: StateFlow<List<SCUser>> = _following.asStateFlow()

    private val _feed = MutableStateFlow<List<SCFeedItem>>(emptyList())
    val feed: StateFlow<List<SCFeedItem>> = _feed.asStateFlow()

    private val _isLoadingHome = MutableStateFlow(false)
    val isLoadingHome: StateFlow<Boolean> = _isLoadingHome.asStateFlow()

    private val _isLoadingFeed = MutableStateFlow(false)
    val isLoadingFeed: StateFlow<Boolean> = _isLoadingFeed.asStateFlow()

    // Player state
    private val _currentTrack = MutableStateFlow<SCTrack?>(null)
    val currentTrack: StateFlow<SCTrack?> = _currentTrack.asStateFlow()

    private val _queue = MutableStateFlow<List<SCTrack>>(emptyList())
    val queue: StateFlow<List<SCTrack>> = _queue.asStateFlow()

    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _isBuffering = MutableStateFlow(false)
    val isBuffering: StateFlow<Boolean> = _isBuffering.asStateFlow()

    private val _elapsedSec = MutableStateFlow(0L)
    val elapsedSec: StateFlow<Long> = _elapsedSec.asStateFlow()

    private val _durationSec = MutableStateFlow(0L)
    val durationSec: StateFlow<Long> = _durationSec.asStateFlow()

    private val _isShuffling = MutableStateFlow(false)
    val isShuffling: StateFlow<Boolean> = _isShuffling.asStateFlow()

    private val _repeatMode = MutableStateFlow(RepeatMode.NONE)
    val repeatMode: StateFlow<RepeatMode> = _repeatMode.asStateFlow()

    private val _toastMessage = MutableStateFlow<String?>(null)
    val toastMessage: StateFlow<String?> = _toastMessage.asStateFlow()

    private var originalQueue: List<SCTrack> = emptyList()
    private var isApplyingRemoteJam = false

    val jam: JamSessionManager = JamSessionManager(
        scope = viewModelScope,
        getDisplayName = { _currentUser.value?.displayName ?: android.os.Build.MODEL },
        getAvatarUrl = { _currentUser.value?.avatarUrl },
        getCurrentTrack = { _currentTrack.value },
        getQueue = { _queue.value },
        getIsPlaying = { _isPlaying.value },
        getElapsedSec = { _elapsedSec.value },
        onApplyRemoteState = { track, queueList, shouldPlay, targetSec ->
            applyRemoteJamState(track, queueList, shouldPlay, targetSec)
        },
        onApplyGuestControl = { action, trackRef, seekSec ->
            when (action) {
                "play" -> if (!_isPlaying.value) togglePlayPause()
                "pause" -> if (_isPlaying.value) togglePlayPause()
                "next" -> nextTrack()
                "prev" -> previousTrack(forcePrevious = true)
                "seek" -> if (seekSec != null) seekToSeconds(seekSec.toLong())
                "track" -> if (trackRef != null) {
                    val t = trackRef.toSCTrack()
                    val merged = (_queue.value.filter { it.id != t.id }).let { listOf(t) + it }
                    playTrack(t, merged)
                }
            }
        },
        onHostAppendQueue = { track ->
            appendToQueue(track)
        },
        onToast = { msg -> showToast(msg) }
    )

    fun showToast(msg: String) {
        _toastMessage.value = msg
        viewModelScope.launch {
            delay(2400)
            if (_toastMessage.value == msg) _toastMessage.value = null
        }
    }

    fun appendToQueue(track: SCTrack) {
        if (_queue.value.isEmpty()) {
            playTrack(track, listOf(track))
            return
        }
        if (_queue.value.none { it.id == track.id }) {
            _queue.value = _queue.value + track
            originalQueue = originalQueue + track
        }
    }

    private suspend fun applyRemoteJamState(
        track: SCTrack,
        queueList: List<SCTrack>,
        shouldPlay: Boolean,
        targetSec: Double
    ) {
        isApplyingRemoteJam = true
        try {
            val merged = if (queueList.isEmpty()) listOf(track) else queueList
            _queue.value = merged
            originalQueue = merged
            val idx = merged.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
            if (_currentTrack.value?.id != track.id) {
                loadAndPlay(idx, initialSeekMs = (targetSec * 1000.0).toLong(), shouldAutoPlay = shouldPlay, notifyJam = false)
            } else {
                _currentIndex.value = idx
                val curSec = _elapsedSec.value.toDouble()
                if (kotlin.math.abs(curSec - targetSec) > 1.8) {
                    mediaController?.seekTo((targetSec * 1000.0).toLong().coerceAtLeast(0L))
                    _elapsedSec.value = targetSec.toLong().coerceAtLeast(0L)
                }
                mediaController?.let { mc ->
                    if (shouldPlay && !mc.isPlaying) mc.play()
                    else if (!shouldPlay && mc.isPlaying) mc.pause()
                }
            }
        } finally {
            isApplyingRemoteJam = false
        }
    }

    init {
        connectMediaController()
        startProgressTicker()
        if (_isLoggedIn.value) {
            refreshAll()
        }
    }

    private fun connectMediaController() {
        val ctx = getApplication<Application>()
        val token = SessionToken(ctx, ComponentName(ctx, PlaybackService::class.java))
        val future = MediaController.Builder(ctx, token).buildAsync()
        future.addListener({
            runCatching {
                val controller = future.get()
                mediaController = controller
                controller.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(playing: Boolean) {
                        _isPlaying.value = playing
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        _isBuffering.value = playbackState == Player.STATE_BUFFERING
                        if (playbackState == Player.STATE_ENDED) {
                            handleTrackEnded()
                        }
                    }
                })
            }
        }, ContextCompat.getMainExecutor(ctx))
    }

    private fun startProgressTicker() {
        viewModelScope.launch {
            var tick = 0
            while (true) {
                delay(400)
                val mc = mediaController
                val track = _currentTrack.value
                if (mc != null && track != null) {
                    val pos = (mc.currentPosition.coerceAtLeast(0L)) / 1000L
                    val dur = if (mc.duration > 0) mc.duration / 1000L else track.durationSec
                    _elapsedSec.value = pos
                    if (dur > 0) _durationSec.value = dur
                    tick++
                    if (tick % 6 == 0) {
                        integrations.onPlaybackProgress(track, pos, dur, _isPlaying.value)
                    }
                }
            }
        }
    }

    fun onSignedIn(token: String, clientId: String) {
        if (token.isNotBlank()) prefs.oauthToken = token
        if (clientId.isNotBlank()) prefs.clientId = clientId
        _isLoggedIn.value = prefs.oauthToken.isNotBlank() && prefs.clientId.isNotBlank()
        if (_isLoggedIn.value) {
            refreshAll()
        }
    }

    fun signOut() {
        prefs.oauthToken = ""
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        mediaController?.stop()
        _currentUser.value = null
        _currentTrack.value = null
        _isLoggedIn.value = false
    }

    private fun rebuildQuickCards(pls: List<SCPlaylist>, fol: List<SCUser>) {
        val cards = mutableListOf<SCQuickCard>()
        pls.firstOrNull()?.let {
            cards.add(SCQuickCard("pl-${it.id}", it.displayTitle, it.creatorName, it.rawArtwork, false, playlist = it))
        }
        fol.firstOrNull()?.let {
            cards.add(SCQuickCard("u-${it.id}", it.displayName, "Artist", it.avatarUrl, true, user = it))
        }
        pls.drop(1).take(4 - cards.size).forEach {
            cards.add(SCQuickCard("pl-${it.id}", it.displayTitle, it.creatorName, it.rawArtwork, false, playlist = it))
        }
        _quickCards.value = cards.take(4)
    }

    fun refreshAll() {
        _isLoadingHome.value = true
        _isLoadingFeed.value = true

        // Launch all independent SoundCloud requests in parallel for near-instant progressive loading!
        viewModelScope.launch {
            val shelves = api.fetchHomeSelections()
            _homeShelves.value = shelves
            _isLoadingHome.value = false
        }

        viewModelScope.launch {
            val (feedItems, _) = api.fetchFeed()
            _feed.value = feedItems
            _isLoadingFeed.value = false
        }

        viewModelScope.launch {
            val (pls, albs) = api.fetchLibraryPlaylistsAndAlbums()
            _playlists.value = pls
            _albums.value = albs
            rebuildQuickCards(pls, _following.value)
        }

        viewModelScope.launch {
            _history.value = api.fetchHistory()
        }

        viewModelScope.launch {
            val me = api.fetchMe()
            _currentUser.value = me
            if (me != null) {
                val likesJob = async { api.fetchLikes(me.id, limit = 80) }
                val folJob = async { api.fetchFollowing(me.id) }
                val libJob = async { api.fetchLibraryPlaylistsAndAlbums(me.id) }

                val (likedTracks, _) = likesJob.await()
                _likes.value = likedTracks
                _likedIds.value = likedTracks.map { it.id }.toSet()

                val (pls, albs) = libJob.await()
                _playlists.value = pls
                _albums.value = albs

                val fol = folJob.await()
                _following.value = fol
                rebuildQuickCards(pls, fol)
            }
        }
    }

    fun playTrack(track: SCTrack, list: List<SCTrack> = listOf(track), shuffle: Boolean = false) {
        val source = if (list.isNotEmpty()) list else listOf(track)
        originalQueue = source
        if (shuffle) {
            _isShuffling.value = true
            val rest = source.filter { it.id != track.id }.shuffled()
            _queue.value = listOf(track) + rest
            _currentIndex.value = 0
        } else {
            _isShuffling.value = false
            _queue.value = source
            _currentIndex.value = source.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        }
        viewModelScope.launch { loadAndPlay(_currentIndex.value) }
    }

    fun playShuffled(list: List<SCTrack>) {
        if (list.isEmpty()) return
        originalQueue = list
        _isShuffling.value = true
        _queue.value = list.shuffled()
        _currentIndex.value = 0
        viewModelScope.launch { loadAndPlay(0) }
    }

    private suspend fun loadAndPlay(
        index: Int,
        initialSeekMs: Long = 0L,
        shouldAutoPlay: Boolean = true,
        notifyJam: Boolean = true
    ) {
        val list = _queue.value
        if (index !in list.indices) return
        val track = list[index]
        _currentIndex.value = index
        _currentTrack.value = track
        _elapsedSec.value = (initialSeekMs / 1000L).coerceAtLeast(0L)
        _durationSec.value = track.durationSec.coerceAtLeast(1L)
        _isBuffering.value = true

        val streamUrl = api.resolveStreamUrl(track)
        if (streamUrl == null) {
            _isBuffering.value = false
            if (!isApplyingRemoteJam && index + 1 < list.size) loadAndPlay(index + 1)
            return
        }

        val (artist, title) = TrackParser.normalize(track.displayTitle, track.artistName, prefs.trackParserEnabled)
        val meta = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setArtworkUri(Uri.parse(SCArtworkUrl.hd(track.rawArtwork)))
            .build()

        val mediaItem = MediaItem.Builder()
            .setUri(streamUrl)
            .setMediaMetadata(meta)
            .build()

        mediaController?.let { mc ->
            mc.setMediaItem(mediaItem)
            mc.prepare()
            if (initialSeekMs > 400L) mc.seekTo(initialSeekMs)
            if (shouldAutoPlay) mc.play() else mc.pause()
        }
        _isBuffering.value = false
        integrations.onPlaybackProgress(track, _elapsedSec.value, track.durationSec, shouldAutoPlay)
        if (notifyJam && !isApplyingRemoteJam) {
            jam.onLocalPlaybackEvent("track", _elapsedSec.value.toDouble())
        }
    }

    fun togglePlayPause() {
        val mc = mediaController ?: return
        val willPlay = !mc.isPlaying
        if (mc.isPlaying) mc.pause() else mc.play()
        if (!isApplyingRemoteJam) {
            jam.onLocalPlaybackEvent(if (willPlay) "play" else "pause", _elapsedSec.value.toDouble())
        }
    }

    fun nextTrack() {
        val list = _queue.value
        if (list.isEmpty()) return
        val next = _currentIndex.value + 1
        if (next < list.size) {
            viewModelScope.launch { loadAndPlay(next) }
        } else if (_repeatMode.value == RepeatMode.ALL) {
            viewModelScope.launch { loadAndPlay(0) }
        }
    }

    fun previousTrack(forcePrevious: Boolean = false) {
        val list = _queue.value
        if (list.isEmpty()) return
        if (!forcePrevious && _elapsedSec.value > 3L) {
            seekToFraction(0f)
            return
        }
        val prev = _currentIndex.value - 1
        if (prev >= 0) {
            viewModelScope.launch { loadAndPlay(prev) }
        } else if (_repeatMode.value == RepeatMode.ALL) {
            viewModelScope.launch { loadAndPlay(list.lastIndex) }
        } else {
            seekToFraction(0f)
        }
    }

    fun seekToFraction(fraction: Float) {
        val clamped = fraction.coerceIn(0f, 1f)
        val durMs = (_durationSec.value * 1000L).coerceAtLeast(1000L)
        val targetMs = (durMs * clamped).toLong()
        _elapsedSec.value = targetMs / 1000L
        mediaController?.seekTo(targetMs)
        if (!isApplyingRemoteJam) {
            jam.onLocalPlaybackEvent("seek", (targetMs / 1000.0))
        }
    }

    fun seekToSeconds(seconds: Long) {
        val targetMs = (seconds.coerceAtLeast(0L)) * 1000L
        _elapsedSec.value = seconds.coerceAtLeast(0L)
        mediaController?.seekTo(targetMs)
        if (!isApplyingRemoteJam) {
            jam.onLocalPlaybackEvent("seek", seconds.toDouble())
        }
    }

    fun toggleShuffle() {
        val newVal = !_isShuffling.value
        _isShuffling.value = newVal
        val cur = _currentTrack.value ?: return
        if (newVal) {
            val rest = originalQueue.filter { it.id != cur.id }.shuffled()
            _queue.value = listOf(cur) + rest
            _currentIndex.value = 0
        } else {
            _queue.value = originalQueue
            _currentIndex.value = originalQueue.indexOfFirst { it.id == cur.id }.coerceAtLeast(0)
        }
    }

    fun cycleRepeat() {
        _repeatMode.value = when (_repeatMode.value) {
            RepeatMode.NONE -> RepeatMode.ALL
            RepeatMode.ALL -> RepeatMode.ONE
            RepeatMode.ONE -> RepeatMode.NONE
        }
    }

    fun toggleLike(trackId: Long, trackObj: SCTrack? = null) {
        val resolvedTrack = trackObj
            ?: _currentTrack.value?.takeIf { it.id == trackId }
            ?: _queue.value.firstOrNull { it.id == trackId }
            ?: _likes.value.firstOrNull { it.id == trackId }

        val currentlyLiked = _likedIds.value.contains(trackId)
        _likedIds.value = if (currentlyLiked) _likedIds.value - trackId else _likedIds.value + trackId
        if (currentlyLiked) {
            _likes.value = _likes.value.filter { it.id != trackId }
        } else if (resolvedTrack != null && _likes.value.none { it.id == trackId }) {
            _likes.value = listOf(resolvedTrack) + _likes.value
        }

        viewModelScope.launch {
            val userId = _currentUser.value?.id ?: api.fetchMe()?.also { _currentUser.value = it }?.id ?: return@launch
            val finalLiked = api.toggleLike(userId, trackId, currentlyLiked)
            _likedIds.value = if (finalLiked) _likedIds.value + trackId else _likedIds.value - trackId
            showToast(if (finalLiked) "Liked & synced to SoundCloud" else "Removed from SoundCloud likes")
        }
    }

    private fun handleTrackEnded() {
        when (_repeatMode.value) {
            RepeatMode.ONE -> {
                seekToFraction(0f)
                mediaController?.play()
            }
            else -> nextTrack()
        }
    }

    override fun onCleared() {
        jam.leaveJam(silent = true)
        mediaController?.release()
        super.onCleared()
    }
}
