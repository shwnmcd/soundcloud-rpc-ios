package com.soundcloudrpc.android.model

import com.google.gson.annotations.SerializedName

data class SCUser(
    val id: Long = 0,
    val username: String? = null,
    @SerializedName("full_name") val fullName: String? = null,
    @SerializedName("avatar_url") val avatarUrl: String? = null,
    @SerializedName("permalink_url") val permalinkUrl: String? = null,
    @SerializedName("followers_count") val followersCount: Int? = null,
    @SerializedName("followings_count") val followingsCount: Int? = null,
    val visuals: SCVisuals? = null
) {
    val displayName: String
        get() = username?.takeIf { it.isNotBlank() }
            ?: fullName?.takeIf { it.isNotBlank() }
            ?: "Artist"
    val bannerUrl: String? get() = visuals?.visuals?.firstOrNull()?.visualUrl
}

data class SCVisuals(val visuals: List<SCVisualItem>? = null)
data class SCVisualItem(@SerializedName("visual_url") val visualUrl: String? = null)

data class SCMedia(val transcodings: List<SCTranscoding>? = null)
data class SCTranscoding(
    val url: String? = null,
    val preset: String? = null,
    val format: SCTranscodingFormat? = null,
    val snipped: Boolean? = null
)
data class SCTranscodingFormat(
    @SerializedName("protocol") val protocolName: String? = null,
    @SerializedName("mime_type") val mimeType: String? = null
)

data class SCTrack(
    val id: Long = 0,
    val title: String? = null,
    val duration: Long? = null,
    @SerializedName("artwork_url") val artworkUrl: String? = null,
    @SerializedName("permalink_url") val permalinkUrl: String? = null,
    @SerializedName("playback_count") val playbackCount: Long? = null,
    @SerializedName("likes_count") val likesCount: Long? = null,
    val user: SCUser? = null,
    val media: SCMedia? = null,
    @SerializedName("track_authorization") val trackAuthorization: String? = null
) {
    val isStub: Boolean get() = title.isNullOrBlank()
    val displayTitle: String get() = title?.ifBlank { "Untitled Track" } ?: "Untitled Track"
    val artistName: String get() = user?.displayName ?: "Unknown Artist"
    val durationSec: Long get() = (duration ?: 0L) / 1000L
    val formattedDuration: String get() = formatSeconds(durationSec)
    val rawArtwork: String? get() = artworkUrl?.takeIf { it.isNotBlank() } ?: user?.avatarUrl

    val formattedPlays: String
        get() {
            val c = playbackCount ?: return ""
            if (c <= 0) return ""
            return when {
                c >= 1_000_000 -> String.format("%.1fM", c / 1_000_000.0)
                c >= 1_000 -> String.format("%.1fK", c / 1_000.0)
                else -> c.toString()
            }
        }
}

data class SCPlaylist(
    val id: Long = 0,
    val title: String? = null,
    @SerializedName("short_title") val shortTitle: String? = null,
    @SerializedName("artwork_url") val artworkUrl: String? = null,
    @SerializedName("calculated_artwork_url") val calculatedArtworkUrl: String? = null,
    @SerializedName("permalink_url") val permalinkUrl: String? = null,
    @SerializedName("track_count") val trackCount: Int? = null,
    val duration: Long? = null,
    @SerializedName("is_album") val isAlbum: Boolean? = null,
    val sharing: String? = null,
    val user: SCUser? = null,
    val tracks: List<SCTrack>? = null
) {
    val resolvedTitle: String?
        get() = title?.trim()?.takeIf { it.isNotEmpty() }
            ?: shortTitle?.trim()?.takeIf { it.isNotEmpty() }
    val hasRealTitle: Boolean get() = resolvedTitle != null
    val displayTitle: String get() = resolvedTitle ?: "Untitled Playlist"
    val creatorName: String get() = user?.displayName ?: "SoundCloud"
    val isPrivate: Boolean get() = sharing == "private"
    val resolvedTrackCount: Int get() = trackCount ?: tracks?.size ?: 0
    val formattedDuration: String get() = formatSeconds((duration ?: 0L) / 1000L)
    val rawArtwork: String?
        get() = artworkUrl?.takeIf { it.isNotBlank() }
            ?: calculatedArtworkUrl?.takeIf { it.isNotBlank() }
            ?: tracks?.firstOrNull { !it.rawArtwork.isNullOrBlank() }?.rawArtwork
            ?: user?.avatarUrl
}

data class SCHomeShelf(
    val id: String,
    val title: String,
    val playlists: List<SCPlaylist>
)

data class SCQuickCard(
    val id: String,
    val title: String,
    val subtitle: String,
    val rawArtwork: String?,
    val isCircular: Boolean,
    val playlist: SCPlaylist? = null,
    val user: SCUser? = null
)

data class SCFeedItem(
    val id: String,
    val type: String,
    val reposter: SCUser?,
    val track: SCTrack?,
    val playlist: SCPlaylist?
) {
    val isRepost: Boolean get() = type.contains("repost")
}

enum class SearchFilter(val label: String) {
    ALL("All"),
    TRACKS("Tracks"),
    ARTISTS("Artists"),
    ALBUMS("Albums"),
    PLAYLISTS("Playlists")
}

object SCArtworkUrl {
    fun thumb(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        return raw.replace("-large.", "-t200x200.")
            .replace("-t50x50.", "-t200x200.")
            .replace("50x50.", "200x200.")
    }

    fun hd(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        return raw.replace("-large.", "-t500x500.")
            .replace("-t50x50.", "-t500x500.")
            .replace("-t200x200.", "-t500x500.")
            .replace("-t300x300.", "-t500x500.")
            .replace("50x50.", "500x500.")
    }

    fun original(raw: String?): String {
        if (raw.isNullOrBlank()) return ""
        return raw.replace("-large.", "-original.")
            .replace("-t50x50.", "-original.")
            .replace("-t200x200.", "-original.")
            .replace("-t300x300.", "-original.")
            .replace("-t500x500.", "-original.")
            .replace("50x50.", "original.")
    }
}

fun formatSeconds(totalSec: Long): String {
    val s = totalSec.coerceAtLeast(0L)
    val h = s / 3600
    val m = (s % 3600) / 60
    val rem = s % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, rem)
    else String.format("%d:%02d", m, rem)
}

/** Exact Kotlin port of richardhbtz/soundcloud-rpc's trackParser.ts */
object TrackParser {
    private val sepRegex = Regex("""(\s+[\u002D\u2013\u2014\u2015]+\s+|[\u002D\u2013\u2014\u2015]{2,})""")
    private val doubleDash = Regex("""[\u002D\u2013\u2014\u2015]{2,}""")
    private val dashes = setOf('-', '\u2013', '\u2014', '\u2015')

    private fun hasRepeated(text: String): Boolean {
        var prev: Char? = null
        var run = 0
        for (c in text) {
            if (c == prev) {
                run++
                if (run >= 5) return true
            } else {
                prev = c
                run = 1
            }
        }
        return false
    }

    private fun isInvalid(text: String): Boolean {
        val t = text.trim()
        if (t.isEmpty()) return true
        if (t.first() in dashes || t.last() in dashes) return true
        if (hasRepeated(t)) return true
        if (doubleDash.containsMatchIn(t)) return true
        return false
    }

    fun normalize(title: String, author: String, enabled: Boolean = true): Pair<String, String> {
        val fallbackArtist = author.trim().ifEmpty { "Unknown Artist" }
        val clean = title.substringBefore('\n').trim()
        val fallbackTrack = clean.ifEmpty { "Unknown Track" }
        if (!enabled || clean.isEmpty()) return fallbackArtist to fallbackTrack

        val m = sepRegex.find(clean)
        if (m != null && m.range.first > 0) {
            val a = clean.substring(0, m.range.first).trim()
            val t = clean.substring(m.range.last + 1).trim()
            if (a.isNotEmpty() && t.isNotEmpty() && !isInvalid(a) && !isInvalid(t)) {
                return a to t
            }
        }
        return fallbackArtist to fallbackTrack
    }
}
