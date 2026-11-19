package com.soundcloudrpc.android.data

import com.google.gson.Gson
import com.soundcloudrpc.android.model.SCArtworkUrl
import com.soundcloudrpc.android.model.SCTrack
import com.soundcloudrpc.android.model.TrackParser
import com.soundcloudrpc.android.model.formatSeconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class IntegrationsService(private val prefs: AppPrefs) {
    private val http = OkHttpClient()
    private val gson = Gson()
    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    private var lastNowPlayingId: Long = -1
    private var scrobbledTrackId: Long = -1
    private var webhookTrackId: Long = -1

    suspend fun onPlaybackProgress(track: SCTrack, elapsedSec: Long, durationSec: Long, isPlaying: Boolean) {
        val (artist, title) = TrackParser.normalize(track.displayTitle, track.artistName, prefs.trackParserEnabled)

        // Optional PC Discord RPC Relay
        if (prefs.rpcEnabled && prefs.rpcRelayUrl.isNotBlank()) {
            sendRpcRelay(artist, title, track, elapsedSec, durationSec, isPlaying)
        }

        if (!isPlaying) return

        // Last.fm updateNowPlaying & scrobble at min(50%, 240s)
        if (prefs.lastFmEnabled && prefs.lastFmSessionKey.isNotBlank()) {
            if (lastNowPlayingId != track.id) {
                lastNowPlayingId = track.id
                postLastFm(
                    mapOf(
                        "method" to "track.updateNowPlaying",
                        "api_key" to prefs.lastFmApiKey,
                        "sk" to prefs.lastFmSessionKey,
                        "artist" to artist,
                        "track" to title
                    )
                )
            }
            val threshold = minOf(durationSec / 2, 240L).coerceAtLeast(10L)
            if (scrobbledTrackId != track.id && elapsedSec >= threshold) {
                scrobbledTrackId = track.id
                postLastFm(
                    mapOf(
                        "method" to "track.scrobble",
                        "api_key" to prefs.lastFmApiKey,
                        "sk" to prefs.lastFmSessionKey,
                        "artist" to artist,
                        "track" to title,
                        "timestamp" to (System.currentTimeMillis() / 1000L).toString()
                    )
                )
            }
        }

        // Webhook at configured playback percentage
        if (prefs.webhookEnabled && prefs.webhookUrl.isNotBlank() && durationSec > 0) {
            val pct = (elapsedSec * 100.0) / durationSec.toDouble()
            if (webhookTrackId != track.id && pct >= prefs.webhookTriggerPercent) {
                webhookTrackId = track.id
                sendWebhook(artist, title, durationSec, track.permalinkUrl ?: "", SCArtworkUrl.hd(track.rawArtwork))
            }
        }
    }

    suspend fun sendTestWebhook(): String {
        val ok = sendWebhook(
            artist = "Daft Punk",
            track = "Instant Crush (Android Test)",
            durationSec = 337,
            originUrl = "https://soundcloud.com",
            artwork = "https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8fe7.png"
        )
        return if (ok) "Test webhook sent!" else "Webhook failed — check URL"
    }

    private suspend fun sendWebhook(
        artist: String,
        track: String,
        durationSec: Long,
        originUrl: String,
        artwork: String
    ): Boolean = withContext(Dispatchers.IO) {
        val url = prefs.webhookUrl.trim()
        if (url.isBlank()) return@withContext false
        val iso = isoNow()
        val isDiscord = prefs.webhookDiscordFormat || url.contains("discord.com/api/webhooks")
        val payload: Any = if (isDiscord) {
            mapOf(
                "username" to "SoundCloud RPC",
                "embeds" to listOf(
                    mapOf(
                        "title" to track,
                        "description" to "by **$artist**",
                        "url" to originUrl.ifBlank { "https://soundcloud.com" },
                        "color" to 16733440,
                        "thumbnail" to mapOf("url" to artwork),
                        "footer" to mapOf("text" to "SoundCloud RPC Android • ${formatSeconds(durationSec)}"),
                        "timestamp" to iso
                    )
                )
            )
        } else {
            mapOf(
                "timestamp" to iso,
                "artist" to artist,
                "track" to track,
                "duration" to durationSec,
                "originUrl" to originUrl,
                "trackArt" to artwork
            )
        }
        runCatching {
            val req = Request.Builder()
                .url(url)
                .post(gson.toJson(payload).toRequestBody(jsonMedia))
                .build()
            http.newCall(req).execute().use { it.isSuccessful }
        }.getOrDefault(false)
    }

    private suspend fun sendRpcRelay(
        artist: String,
        title: String,
        track: SCTrack,
        elapsedSec: Long,
        durationSec: Long,
        isPlaying: Boolean
    ) = withContext(Dispatchers.IO) {
        runCatching {
            val body = mapOf(
                "isPlaying" to isPlaying,
                "title" to title,
                "author" to artist,
                "artwork" to SCArtworkUrl.hd(track.rawArtwork),
                "elapsed" to formatSeconds(elapsedSec),
                "duration" to formatSeconds(durationSec),
                "url" to (track.permalinkUrl ?: "")
            )
            val req = Request.Builder()
                .url(prefs.rpcRelayUrl.trim())
                .post(gson.toJson(body).toRequestBody(jsonMedia))
                .build()
            http.newCall(req).execute().close()
        }
    }

    private suspend fun postLastFm(params: Map<String, String>) = withContext(Dispatchers.IO) {
        runCatching {
            val sig = md5(params.toSortedMap().entries.joinToString("") { "${it.key}${it.value}" } + prefs.lastFmSecret)
            val form = FormBody.Builder()
            params.forEach { (k, v) -> form.add(k, v) }
            form.add("api_sig", sig)
            form.add("format", "json")
            val req = Request.Builder()
                .url("https://ws.audioscrobbler.com/2.0/")
                .post(form.build())
                .build()
            http.newCall(req).execute().close()
        }
    }

    private fun md5(input: String): String {
        val bytes = MessageDigest.getInstance("MD5").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun isoNow(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date())
    }
}
