package com.soundcloudrpc.android.data

import android.content.Context
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.reflect.TypeToken
import com.soundcloudrpc.android.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.Cache
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

private fun JsonObject.optString(key: String): String? {
    val el = this.get(key) ?: return null
    if (el.isJsonNull || !el.isJsonPrimitive) return null
    return runCatching { el.asString }.getOrNull()
}

private fun JsonObject.optLong(key: String): Long? {
    val el = this.get(key) ?: return null
    if (el.isJsonNull || !el.isJsonPrimitive) return null
    return runCatching { el.asLong }.getOrNull()
}

private fun JsonObject.optInt(key: String): Int? {
    val el = this.get(key) ?: return null
    if (el.isJsonNull || !el.isJsonPrimitive) return null
    return runCatching { el.asInt }.getOrNull()
}

private fun JsonObject.optBool(key: String): Boolean? {
    val el = this.get(key) ?: return null
    if (el.isJsonNull || !el.isJsonPrimitive) return null
    return runCatching { el.asBoolean }.getOrNull()
}

private fun JsonObject.optObj(key: String): JsonObject? {
    val el = this.get(key) ?: return null
    return if (el.isJsonObject) el.asJsonObject else null
}

private fun JsonObject.optArray(key: String): JsonArray? {
    val el = this.get(key) ?: return null
    return if (el.isJsonArray) el.asJsonArray else null
}

class SoundCloudApi(
    private val prefs: AppPrefs,
    context: Context? = null
) {
    private val gson = Gson()
    private val http: OkHttpClient = OkHttpClient.Builder().apply {
        connectTimeout(10, TimeUnit.SECONDS)
        readTimeout(12, TimeUnit.SECONDS)
        if (context != null) {
            cache(Cache(File(context.cacheDir, "sc_http_cache"), 16L * 1024L * 1024L))
        }
    }.build()

    private suspend fun requestJson(url: String, method: String = "GET"): String =
        withContext(Dispatchers.IO) {
            val base = url.toHttpUrlOrNull() ?: throw IllegalArgumentException("Bad URL: $url")
            val builder = base.newBuilder()
            if (base.queryParameter("client_id") == null && prefs.clientId.isNotBlank()) {
                builder.addQueryParameter("client_id", prefs.clientId)
            }
            val reqBuilder = Request.Builder()
                .url(builder.build())
                .header("Accept", "application/json")
                .header("Origin", "https://soundcloud.com")
                .header("Referer", "https://soundcloud.com/")
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36")

            if (prefs.oauthToken.isNotBlank()) {
                reqBuilder.header("Authorization", "OAuth ${prefs.oauthToken}")
            }

            when (method) {
                "PUT" -> reqBuilder.put("".toRequestBody(null))
                "DELETE" -> reqBuilder.delete()
                else -> reqBuilder.get()
            }

            http.newCall(reqBuilder.build()).execute().use { resp ->
                if (!resp.isSuccessful) {
                    throw RuntimeException("HTTP ${resp.code}")
                }
                resp.body?.string() ?: "{}"
            }
        }

    /** Safely parses both standard numeric playlists AND SoundCloud system_playlists (which have string URN IDs!) */
    private fun parsePlaylistElement(el: JsonElement?): SCPlaylist? {
        if (el == null || !el.isJsonObject) return null
        val obj = el.asJsonObject
        // Fast path when numeric id is present
        val numericId = obj.optLong("id")
        if (numericId != null) {
            return runCatching { gson.fromJson(obj, SCPlaylist::class.java) }.getOrNull()
        }
        // Fallback for SoundCloud system_playlist (string URN id!)
        val urn = obj.optString("urn") ?: obj.optString("id") ?: return null
        val safeId = urn.hashCode().toLong()
        val title = obj.optString("title") ?: obj.optString("short_title") ?: return null
        val artwork = obj.optString("artwork_url") ?: obj.optString("calculated_artwork_url")
        val permalink = obj.optString("permalink_url")
        val user = obj.optObj("user")?.let { runCatching { gson.fromJson(it, SCUser::class.java) }.getOrNull() }
        val tracks = obj.optArray("tracks")?.mapNotNull { tEl ->
            if (!tEl.isJsonObject) null else runCatching { gson.fromJson(tEl, SCTrack::class.java) }.getOrNull()
        }
        return SCPlaylist(
            id = safeId,
            title = title,
            artworkUrl = artwork,
            permalinkUrl = permalink,
            trackCount = obj.optInt("track_count") ?: tracks?.size,
            duration = obj.optLong("duration"),
            isAlbum = obj.optBool("is_album"),
            sharing = obj.optString("sharing"),
            user = user,
            tracks = tracks
        )
    }

    suspend fun fetchMe(): SCUser? = runCatching {
        gson.fromJson(requestJson("https://api-v2.soundcloud.com/me"), SCUser::class.java)
    }.getOrNull()

    suspend fun fetchHomeSelections(): List<SCHomeShelf> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/mixed-selections?variant_ids=&limit=10")
        ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList()
        val collection = root.optArray("collection") ?: return@runCatching emptyList()
        val result = mutableListOf<SCHomeShelf>()
        var shelfIdx = 0
        for (el in collection) {
            if (!el.isJsonObject) continue
            val obj = el.asJsonObject
            val id = obj.optString("urn") ?: "shelf-$shelfIdx"
            val title = obj.optString("title") ?: "Recommended"
            val itemsCol = obj.optObj("items")?.optArray("collection") ?: continue
            val playlists = itemsCol.mapNotNull { item -> parsePlaylistElement(item) }.filter { it.hasRealTitle }
            if (playlists.isNotEmpty()) {
                result.add(SCHomeShelf("$id-$shelfIdx", title, playlists))
                shelfIdx++
            }
        }
        result
    }.getOrDefault(emptyList())

    suspend fun fetchLikes(userId: Long, nextHref: String? = null, limit: Int = 50): Pair<List<SCTrack>, String?> =
        runCatching<Pair<List<SCTrack>, String?>> {
            val url = nextHref
                ?: "https://api-v2.soundcloud.com/users/$userId/track_likes?limit=$limit&linked_partitioning=1"
            val root = JsonParser.parseString(requestJson(url))
                .takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching (emptyList<SCTrack>() to null)
            val col = root.optArray("collection") ?: return@runCatching (emptyList<SCTrack>() to null)
            val next = root.optString("next_href")
            val tracks = col.mapNotNull { el ->
                if (!el.isJsonObject) return@mapNotNull null
                val raw = el.asJsonObject.optObj("track") ?: return@mapNotNull null
                runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
            }
            tracks to next
        }.getOrDefault(emptyList<SCTrack>() to null)

    suspend fun fetchLibraryPlaylistsAndAlbums(userId: Long? = null): Pair<List<SCPlaylist>, List<SCPlaylist>> =
        coroutineScope {
            val allLibDef = async {
                runCatching {
                    val root = JsonParser.parseString(
                        requestJson("https://api-v2.soundcloud.com/me/library/all?limit=100")
                    ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList<SCPlaylist>()
                    val col = root.optArray("collection") ?: return@runCatching emptyList<SCPlaylist>()
                    col.mapNotNull { el ->
                        if (!el.isJsonObject) return@mapNotNull null
                        val obj = el.asJsonObject
                        val raw = obj.optObj("playlist") ?: obj.optObj("system_playlist") ?: return@mapNotNull null
                        parsePlaylistElement(raw)
                    }
                }.getOrDefault(emptyList())
            }

            val createdDef = async {
                if (userId == null) return@async emptyList<SCPlaylist>()
                runCatching {
                    val root = JsonParser.parseString(
                        requestJson("https://api-v2.soundcloud.com/users/$userId/playlists_without_albums?limit=100")
                    ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList<SCPlaylist>()
                    root.optArray("collection")?.mapNotNull { parsePlaylistElement(it) } ?: emptyList()
                }.getOrDefault(emptyList())
            }

            val likedPlDef = async {
                if (userId == null) return@async emptyList<SCPlaylist>()
                runCatching {
                    val root = JsonParser.parseString(
                        requestJson("https://api-v2.soundcloud.com/users/$userId/playlist_likes?limit=100")
                    ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList<SCPlaylist>()
                    root.optArray("collection")?.mapNotNull { el ->
                        if (!el.isJsonObject) return@mapNotNull null
                        val raw = el.asJsonObject.optObj("playlist") ?: el
                        parsePlaylistElement(raw)
                    } ?: emptyList()
                }.getOrDefault(emptyList())
            }

            val albumsDef = async {
                if (userId == null) return@async emptyList<SCPlaylist>()
                runCatching {
                    val root = JsonParser.parseString(
                        requestJson("https://api-v2.soundcloud.com/users/$userId/albums?limit=100")
                    ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList<SCPlaylist>()
                    root.optArray("collection")?.mapNotNull { parsePlaylistElement(it) } ?: emptyList()
                }.getOrDefault(emptyList())
            }

            val orderedIds = mutableListOf<Long>()
            val byId = LinkedHashMap<Long, SCPlaylist>()

            fun merge(list: List<SCPlaylist>) {
                for (pl in list) {
                    val existing = byId[pl.id]
                    if (existing != null) {
                        val oldScore = (if (existing.hasRealTitle) 10 else 0) + (if (!existing.artworkUrl.isNullOrBlank()) 4 else 0) + (existing.tracks?.size ?: 0)
                        val newScore = (if (pl.hasRealTitle) 10 else 0) + (if (!pl.artworkUrl.isNullOrBlank()) 4 else 0) + (pl.tracks?.size ?: 0)
                        if (newScore > oldScore) byId[pl.id] = pl
                    } else {
                        orderedIds.add(pl.id)
                        byId[pl.id] = pl
                    }
                }
            }

            merge(createdDef.await())
            merge(likedPlDef.await())
            merge(albumsDef.await())
            merge(allLibDef.await())

            // Hydrate any remaining stub playlists missing a title
            val missing = orderedIds.filter { id ->
                val p = byId[id]
                p != null && !p.hasRealTitle && p.id > 0L
            }.take(20)

            for (stubId in missing) {
                runCatching {
                    val full = gson.fromJson(
                        requestJson("https://api-v2.soundcloud.com/playlists/$stubId"),
                        SCPlaylist::class.java
                    )
                    if (full != null && full.hasRealTitle) byId[stubId] = full
                }
            }

            val playlists = mutableListOf<SCPlaylist>()
            val albums = mutableListOf<SCPlaylist>()
            for (id in orderedIds) {
                val pl = byId[id] ?: continue
                if (!pl.hasRealTitle) continue
                if (pl.isAlbum == true) albums.add(pl) else playlists.add(pl)
            }
            playlists.toList() to albums.toList()
        }

    suspend fun fetchFullPlaylistTracks(playlistId: Long, fallbackTracks: List<SCTrack>? = null): Pair<SCPlaylist?, List<SCTrack>> =
        runCatching<Pair<SCPlaylist?, List<SCTrack>>> {
            if (playlistId <= 0L && !fallbackTracks.isNullOrEmpty()) {
                return@runCatching (null to hydrateTracks(fallbackTracks))
            }
            val pl = gson.fromJson(
                requestJson("https://api-v2.soundcloud.com/playlists/$playlistId?representation=full"),
                SCPlaylist::class.java
            )
            val hydrated = hydrateTracks(pl.tracks.orEmpty())
            pl to hydrated
        }.getOrDefault(null to fallbackTracks.orEmpty())

    suspend fun hydrateTracks(tracks: List<SCTrack>): List<SCTrack> {
        val stubIds = tracks.filter { it.isStub && it.id > 0L }.map { it.id }
        if (stubIds.isEmpty()) return tracks
        val map = mutableMapOf<Long, SCTrack>()
        val listType = object : TypeToken<List<SCTrack>>() {}.type
        for (chunk in stubIds.chunked(50)) {
            val idsParam = chunk.joinToString(",")
            runCatching {
                val json = requestJson("https://api-v2.soundcloud.com/tracks?ids=$idsParam")
                val loaded: List<SCTrack> = gson.fromJson(json, listType)
                loaded.forEach { map[it.id] = it }
            }
        }
        return tracks.mapNotNull { if (!it.isStub) it else map[it.id] }
    }

    suspend fun fetchFeed(nextHref: String? = null): Pair<List<SCFeedItem>, String?> =
        runCatching<Pair<List<SCFeedItem>, String?>> {
            val url = nextHref ?: "https://api-v2.soundcloud.com/stream?limit=30&linked_partitioning=1"
            val root = JsonParser.parseString(requestJson(url))
                .takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching (emptyList<SCFeedItem>() to null)
            val col = root.optArray("collection") ?: return@runCatching (emptyList<SCFeedItem>() to null)
            val next = root.optString("next_href")
            val items = mutableListOf<SCFeedItem>()
            var idx = 0
            for (el in col) {
                if (!el.isJsonObject) continue
                val obj = el.asJsonObject
                val type = obj.optString("type") ?: "track"
                if (type.contains("promoted", ignoreCase = true) || type.contains("ad", ignoreCase = true)) continue
                val createdAt = obj.optString("created_at") ?: ""
                val reposter = obj.optObj("user")?.let { runCatching { gson.fromJson(it, SCUser::class.java) }.getOrNull() }
                val track = obj.optObj("track")?.let { runCatching { gson.fromJson(it, SCTrack::class.java) }.getOrNull() }
                val pl = obj.optObj("playlist")?.let { parsePlaylistElement(it) }
                if (track != null) {
                    items.add(SCFeedItem("f-$idx-$type-${track.id}-$createdAt", type, reposter, track, null))
                    idx++
                } else if (pl != null) {
                    items.add(SCFeedItem("f-$idx-$type-${pl.id}-$createdAt", type, reposter, null, pl))
                    idx++
                }
            }
            items to next
        }.getOrDefault(emptyList<SCFeedItem>() to null)

    suspend fun fetchHistory(): List<SCTrack> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/me/play-history/tracks?limit=50")
        ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList()
        val col = root.optArray("collection") ?: return@runCatching emptyList()
        col.mapNotNull { el ->
            if (!el.isJsonObject) return@mapNotNull null
            val raw = el.asJsonObject.optObj("track") ?: return@mapNotNull null
            runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
        }
    }.getOrDefault(emptyList())

    suspend fun fetchFollowing(userId: Long): List<SCUser> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/users/$userId/followings?limit=60")
        ).takeIf { it.isJsonObject }?.asJsonObject ?: return@runCatching emptyList()
        val col = root.optArray("collection") ?: return@runCatching emptyList()
        col.mapNotNull { if (!it.isJsonObject) null else runCatching { gson.fromJson(it, SCUser::class.java) }.getOrNull() }
    }.getOrDefault(emptyList())

    data class ArtistProfileData(
        val user: SCUser?,
        val playlists: List<SCPlaylist>,
        val tracks: List<SCTrack>,
        val reposts: List<SCTrack>,
        val likes: List<SCTrack>
    )

    suspend fun fetchArtistProfile(userId: Long): ArtistProfileData = coroutineScope {
        val userDeferred = async {
            runCatching { gson.fromJson(requestJson("https://api-v2.soundcloud.com/users/$userId"), SCUser::class.java) }.getOrNull()
        }
        val playlistsDeferred = async {
            runCatching {
                val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/playlists?limit=20")).asJsonObject
                root.optArray("collection")?.mapNotNull { parsePlaylistElement(it) } ?: emptyList()
            }.getOrDefault(emptyList())
        }
        val tracksDeferred = async {
            runCatching {
                val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/tracks?limit=30")).asJsonObject
                root.optArray("collection")?.mapNotNull { if (!it.isJsonObject) null else runCatching { gson.fromJson(it, SCTrack::class.java) }.getOrNull() } ?: emptyList()
            }.getOrDefault(emptyList())
        }
        val repostsDeferred = async {
            runCatching {
                val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/stream/users/$userId/reposts?limit=20")).asJsonObject
                root.optArray("collection")?.mapNotNull { el ->
                    if (!el.isJsonObject) return@mapNotNull null
                    val raw = el.asJsonObject.optObj("track") ?: return@mapNotNull null
                    runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
                } ?: emptyList()
            }.getOrDefault(emptyList())
        }
        val likesDeferred = async {
            runCatching {
                val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/track_likes?limit=20")).asJsonObject
                root.optArray("collection")?.mapNotNull { el ->
                    if (!el.isJsonObject) return@mapNotNull null
                    val raw = el.asJsonObject.optObj("track") ?: return@mapNotNull null
                    runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
                } ?: emptyList()
            }.getOrDefault(emptyList())
        }
        ArtistProfileData(
            user = userDeferred.await(),
            playlists = playlistsDeferred.await(),
            tracks = tracksDeferred.await(),
            reposts = repostsDeferred.await(),
            likes = likesDeferred.await()
        )
    }

    data class SearchResult(
        val tracks: List<SCTrack>,
        val users: List<SCUser>,
        val playlists: List<SCPlaylist>
    )

    suspend fun search(query: String, filter: SearchFilter): SearchResult = runCatching {
        val q = URLEncoder.encode(query.trim(), "UTF-8")
        val endpoint = when (filter) {
            SearchFilter.ALL -> "https://api-v2.soundcloud.com/search?q=$q&limit=30"
            SearchFilter.TRACKS -> "https://api-v2.soundcloud.com/search/tracks?q=$q&limit=30"
            SearchFilter.ARTISTS -> "https://api-v2.soundcloud.com/search/users?q=$q&limit=30"
            SearchFilter.ALBUMS -> "https://api-v2.soundcloud.com/search/albums?q=$q&limit=30"
            SearchFilter.PLAYLISTS -> "https://api-v2.soundcloud.com/search/playlists_without_albums?q=$q&limit=30"
        }
        val root = JsonParser.parseString(requestJson(endpoint))
            .takeIf { it.isJsonObject }?.asJsonObject
            ?: return@runCatching SearchResult(emptyList(), emptyList(), emptyList())
        val col = root.optArray("collection")
            ?: return@runCatching SearchResult(emptyList(), emptyList(), emptyList())
        val tracks = mutableListOf<SCTrack>()
        val users = mutableListOf<SCUser>()
        val playlists = mutableListOf<SCPlaylist>()
        for (el in col) {
            if (!el.isJsonObject) continue
            val kind = el.asJsonObject.optString("kind") ?: continue
            when (kind) {
                "track" -> runCatching { gson.fromJson(el, SCTrack::class.java) }.getOrNull()?.let(tracks::add)
                "user" -> runCatching { gson.fromJson(el, SCUser::class.java) }.getOrNull()?.let(users::add)
                "playlist" -> parsePlaylistElement(el)?.let(playlists::add)
            }
        }
        SearchResult(tracks, users, playlists)
    }.getOrDefault(SearchResult(emptyList(), emptyList(), emptyList()))

    suspend fun toggleLike(userId: Long, trackId: Long, currentlyLiked: Boolean): Boolean = runCatching {
        requestJson(
            url = "https://api-v2.soundcloud.com/users/$userId/track_likes/$trackId",
            method = if (currentlyLiked) "DELETE" else "PUT"
        )
        !currentlyLiked
    }.getOrDefault(currentlyLiked)

    suspend fun resolveStreamUrl(track: SCTrack): String? = runCatching {
        var transcodings = track.media?.transcodings.orEmpty()
        var trackAuth = track.trackAuthorization
        if (transcodings.isEmpty()) {
            val full = gson.fromJson(
                requestJson("https://api-v2.soundcloud.com/tracks/${track.id}"),
                SCTrack::class.java
            )
            transcodings = full.media?.transcodings.orEmpty()
            trackAuth = full.trackAuthorization
        }

        val ordered = transcodings
            .filter { it.format?.protocolName == "hls" || it.format?.protocolName == "progressive" }
            .sortedByDescending { t ->
                var score = if (t.snipped != true) 100 else 0
                val proto = t.format?.protocolName ?: ""
                val mime = t.format?.mimeType ?: ""
                score += when {
                    proto == "hls" && mime.contains("mpeg") -> 50
                    proto == "progressive" -> 45
                    proto == "hls" && mime.contains("mp4") -> 40
                    else -> 20
                }
                score
            }

        for (t in ordered) {
            var base = t.url?.takeIf { it.isNotBlank() } ?: continue
            if (!trackAuth.isNullOrBlank()) {
                val sep = if (base.contains("?")) "&" else "?"
                base += "${sep}track_authorization=$trackAuth"
            }
            val obj = runCatching { JsonParser.parseString(requestJson(base)).asJsonObject }.getOrNull()
            val resolved = obj?.optString("url")
            if (!resolved.isNullOrBlank()) return@runCatching resolved
        }
        null
    }.getOrNull()
}
